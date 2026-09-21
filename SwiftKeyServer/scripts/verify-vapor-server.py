#!/usr/bin/env python3
"""Exercise the built production executable with disposable state and credentials.

Requires network access to Google's official Android attestation trust endpoints.
Does not read or change the normal authority's state/configuration or enroll a phone.
"""
import argparse
import gzip
import hashlib
import http.client
import json
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import tempfile
import time
import uuid


SERVER = Path(__file__).resolve().parents[1]


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=SERVER / ".build/debug/swiftkey-server")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    checks = []
    marker = "private-smoke-marker-" + secrets.token_hex(16)
    with tempfile.TemporaryDirectory(prefix="swiftkey-vapor-smoke-") as temporary:
        directory = Path(temporary)
        admin, bootstrap = secrets.token_hex(32), secrets.token_hex(32)
        for name, token in [("admin", admin), ("bootstrap", bootstrap)]:
            path = directory / name
            path.write_text(token + "\n")
            path.chmod(0o600)
        port, override_port = free_port(), free_port()
        while override_port == port:
            override_port = free_port()
        origin = f"http://127.0.0.1:{port}"
        config = json.loads((SERVER / "config/device.json").read_text())
        config.update(host="127.0.0.1", port=port, stateDirectory=str(directory / "state"),
                      pairingV2={"enabled": True, "origin": origin})
        config_path = directory / "config.json"
        config_path.write_text(json.dumps(config))
        command = [str(binary), "--config", str(config_path), "--bootstrap-token-file",
                   str(directory / "bootstrap"), "--admin-token-file", str(directory / "admin"),
                   "--hostname", "0.0.0.0", "--port", str(override_port)]
        log_path = directory / "server.log"
        process = None

        def request(method, path, body=None, auth=False, headers=None, partial_body=False, chunked=False):
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            supplied = dict(headers or {})
            if auth:
                supplied["Authorization"] = "Bearer " + admin
            try:
                if partial_body:
                    connection.putrequest(method, path)
                    for name, value in supplied.items():
                        connection.putheader(name, value)
                    connection.endheaders()
                    # Vapor dispatches a streaming request on its first body
                    # chunk. Withhold the remainder to prove the guard responds
                    # before full collection or JSON decoding.
                    connection.send(b"{")
                else:
                    if chunked:
                        raw_body = body
                        body = (raw_body[offset:offset + 8192] for offset in range(0, len(raw_body), 8192))
                    connection.request(method, path, body=body, headers=supplied, encode_chunked=chunked)
                response = connection.getresponse()
                status, received, content = response.status, dict(response.getheaders()), response.read()
                received = {name.lower(): value for name, value in received.items()}
                assert received.get("cache-control") == "no-store"
                assert received.get("x-content-type-options") == "nosniff"
                assert received.get("x-frame-options") == "DENY"
                assert received.get("referrer-policy") == "no-referrer"
                assert "frame-ancestors 'none'" in received.get("content-security-policy", "")
                return status, received, content
            finally:
                connection.close()

        def start():
            nonlocal process
            with log_path.open("ab") as log:
                process = subprocess.Popen(command, cwd=SERVER, stdout=log, stderr=log)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                assert process.poll() is None, "Production server exited during startup; private log withheld"
                try:
                    status, _, body = request("GET", "/health")
                    assert status == 200 and json.loads(body)["status"] == "ok"
                    return
                except (OSError, http.client.HTTPException):
                    time.sleep(0.1)
            raise AssertionError("Production server did not become ready within 45 seconds")

        def stop(sig):
            nonlocal process
            process.send_signal(sig)
            try:
                assert process.wait(timeout=15) == 0, "Server did not shut down cleanly"
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                raise AssertionError("Server shutdown timed out") from None
            process = None

        try:
            start()
            checks.append("production startup with real Google trust refresh")
            listeners = subprocess.check_output(
                ["lsof", "-nP", "-a", "-p", str(process.pid), "-iTCP", "-sTCP:LISTEN", "-Fn"], text=True)
            assert [line for line in listeners.splitlines() if line.startswith("n")] == [f"n127.0.0.1:{port}"]
            checks.append("validated loopback binding ignores Vapor CLI overrides")
            resources = SERVER / "Sources/SwiftKeyServer/Resources"
            for route, filename in [("/", "index.html"), ("/app.js", "app.js"), ("/style.css", "style.css"),
                                    ("/fonts/space-grotesk.woff2", "space-grotesk.woff2"),
                                    ("/fonts/ibm-plex-mono.woff2", "ibm-plex-mono.woff2")]:
                status, _, body = request("GET", route)
                assert status == 200 and body == (resources / filename).read_bytes()
            assert request("HEAD", "/")[0::2] == (200, b"")
            checks.append("bundled console scripts styles fonts and HEAD over real HTTP")
            status, _, body = request("POST", "/v1/admin/workspace", partial_body=True,
                                      headers={"Content-Length": "2000001"})
            assert status == 403 and json.loads(body)["code"] == "unauthorized"
            status, _, body = request("PATCH", "/v1/admin/missing?probe=" + marker)
            assert status == 403 and json.loads(body)["code"] == "unauthorized"
            checks.append("admin authentication precedes body collection and unknown route lookup")
            status, _, body = request("POST", "/v2/identities/prepare", json.dumps(
                {"requestID": str(uuid.uuid4()), "rootKind": "android-strongbox-p256"}))
            assert status == 200 and json.loads(body)["challenge"]["payload"]["origin"] == origin
            checks.append("v2 preparation uses real authority and configured origin")
            status, _, body = request("POST", "/v2/operations", b" " * 750001)
            assert status == 413 and json.loads(body)["code"] == "invalidRequest"
            status, _, body = request("POST", "/v2/operations", gzip.compress(b"{}"),
                                      headers={"Content-Encoding": "gzip"})
            assert status == 400 and json.loads(body)["code"] == "invalidRequest"
            checks.append("raw JSON size bound and no implicit request decompression")
            for size, expected in [(750000, 400), (750001, 413)]:
                status, _, body = request("POST", "/v2/challenges", b"{}" + b" " * (size - 2), chunked=True)
                assert status == expected and json.loads(body)["code"] == "invalidRequest"
            checks.append("chunked HTTP bodies enforce exact v2 byte limit")
            for _ in range(15):
                status, _, _ = request("POST", "/v2/identities/attest", b"{}")
                assert status == 400
            status, _, body = request("POST", "/v2/identities/attest", partial_body=True,
                                      headers={"Content-Length": "750000"})
            assert status == 429 and json.loads(body)["code"] == "rateLimited"
            checks.append("v2 transport budget rejects before waiting for body")
            with socket.create_connection(("127.0.0.1", port), timeout=35) as stalled:
                stalled.sendall(b"POST /v2/challenges HTTP/1.1\r\nHost: localhost\r\n")
                assert stalled.recv(1) == b"", "Idle partial-header connection was not closed"
            checks.append("idle partial-header socket closes before request dispatch")
            status, _, body = request("GET", "/v1/admin/status", auth=True)
            before = json.loads(body)
            assert status == 200 and before["accountCount"] == 0
            assert before["schemaVersion"] == 3 and before["legacyProvisioningAllowed"] is False
            status, _, body = request("POST", "/v1/admin/ui/sessions", auth=True)
            session = json.loads(body)
            assert status == 201 and session
            checks.append("authenticated shared Swift UI session through Vapor")
            stop(signal.SIGTERM)
            start()
            status, _, body = request("GET", "/v1/admin/status", auth=True)
            after = json.loads(body)
            assert status == 200 and after["serverPublicKey"] == before["serverPublicKey"]
            assert after["ledgerHead"]["sequence"] == before["ledgerHead"]["sequence"]
            assert after["ledgerHead"]["hash"] == before["ledgerHead"]["hash"]
            stop(signal.SIGINT)
            checks.append("SIGTERM and SIGINT shutdown restart with unchanged pin and ledger")
            log = log_path.read_text()
            assert all(value not in log for value in [admin, bootstrap, marker])
            checks.append("credentials and request query marker absent from production logs")
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

    result = {"status": "passed", "checks": checks, "real_attestation_trust_fetch": True,
              "physical_phone_enrollment": False, "live_authority_state_modified": False,
              "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    rendered = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()
