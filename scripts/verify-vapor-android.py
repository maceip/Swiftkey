#!/usr/bin/env python3
"""Check the already installed, enrolled Android app against the running authority.

Requires an authorized ADB device and an expired prior epoch credential. Never
installs, clears app data, changes provisioning, or exports private client state.
It launches/restarts the installed app and sets its existing loopback adb reverse.
Use --resume-first-run-pid only for an already completed first launch whose
original android-before.json and authority-before-device.json were saved.
If logcat has rolled, --first-run-log may supply the preserved threadtime log.
"""
import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.pureswift.swiftandroidui"
ACTIVITY = PACKAGE + "/com.pureswift.swiftandroid.MainActivity"


def public_credential(credential):
    """A credential contains public proofs; explicitly exclude any extra fields."""
    if credential is None:
        return None
    pick = lambda value, names: {name: value[name] for name in names if name in value}
    authorization = credential["authorization"]
    return {
        "delegation": pick(credential["delegation"], ["accountID", "deviceID", "epoch", "publicKey",
                                                       "previousPublicKeyHash", "audience"]),
        "authorization": {**pick(authorization, ["kind", "signature"]),
                          "challenge": pick(authorization["challenge"], ["accountID", "deviceID", "operation",
                             "sequence", "nonce", "expiresAt", "payloadHash"])},
        "serverSignature": credential["serverSignature"],
    }


def protocol_records(text):
    return [dict(re.findall(r"\b([A-Za-z][A-Za-z0-9]*)=([^\s]+)", line.split("SwiftKeyProtocol ", 1)[1]))
            for line in text.splitlines() if "SwiftKeyProtocol " in line]


def saved_run_log(text, pid):
    """Accept only relevant threadtime lines bound to the explicitly resumed PID."""
    relevant = [line for line in text.splitlines()
                if "SwiftKeyHardware:" in line or "SwiftKeyProtocol " in line]
    assert relevant, "Saved first-run log contains no hardware/protocol evidence"
    for line in relevant:
        columns = line.split(maxsplit=6)
        assert len(columns) == 7 and re.fullmatch(r"[0-9]{2}-[0-9]{2}", columns[0]) \
            and re.fullmatch(r"[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+", columns[1]) \
            and columns[2].isdecimal() and columns[3].isdecimal() \
            and columns[4] in "VDIWEFAS" and len(columns[4]) == 1, \
            "Saved evidence is not in Android threadtime format"
        assert int(columns[2]) == pid, "Saved evidence contains a different process PID"
    return "\n".join(relevant) + "\n"


def completion_profile(text):
    records = protocol_records(text)
    if any(record.get("complete") == "true" for record in records):
        return "workload-demonstration"
    if any(record.get("credentialReady") == "true" for record in records):
        return "credential-only"
    return None


def validate_run(text, public, profile, fresh):
    credential = public["credential"]
    assert credential, "App has no public epoch credential"
    delegation, enrollment = credential["delegation"], public["enrollment"]
    for field in ["accountID", "deviceID"]:
        assert delegation[field] == enrollment[field], "Credential does not match the preserved enrolled identity"
        assert credential["authorization"]["challenge"][field] == enrollment[field], "Root proof identity changed"
    assert delegation["audience"] == public["configuration"]["audience"], "Credential audience changed"
    assert credential["authorization"]["kind"] == "androidStrongBoxP256"
    assert credential["authorization"]["challenge"]["operation"] == "issueEpoch"
    root_hex = base64.b64decode(enrollment["publicKey"], validate=True).hex()
    assert any("SwiftKeyHardware:" in line and "securityLevel=STRONGBOX" in line
               and "signVerify=true" in line and "publicKeyHex=" + root_hex in line
               for line in text.splitlines()), "No fresh matching StrongBox possession check"
    records = protocol_records(text)
    marker = "epochCredentialVerified" if fresh else "epochCredentialReused"
    assert any(record.get(marker) == "true" and (not fresh or record.get("epoch") == str(delegation["epoch"]))
               for record in records), "App did not report the required epoch issuance/reuse"
    completion = "complete" if profile == "workload-demonstration" else "credentialReady"
    completed = [record for record in records if record.get(completion) == "true"]
    assert completed, "Expected app profile did not complete"
    last = completed[-1]
    assert last.get("epoch") == str(delegation["epoch"]), "Completion log epoch differs from saved credential"
    assert last.get("epochPublicKey") == base64.b64decode(delegation["publicKey"], validate=True).hex(), \
        "Completion log leaf differs from saved credential"
    if profile == "workload-demonstration":
        assert last.get("workloadAccepted") == "true" and last.get("replayRejected") == "true"
        assert any(record.get("serverWorkloadAccepted") == "true" for record in records)
        assert any(record.get("workloadReplayRejected") == "true" for record in records)
    else:
        assert last.get("accountID") == enrollment["accountID"] and last.get("deviceID") == enrollment["deviceID"]


def validate_ledger_range(page, before_head, after_head):
    assert not page.get("hasMore"), "Acceptance ledger range was truncated"
    for field in ["sequence", "hash"]:
        assert page["head"][field] == after_head[field], "Ledger changed during acceptance readback"
    events = page["events"]
    assert len(events) == after_head["sequence"] - before_head["sequence"], "Unexpected ledger range length"
    previous_hash = before_head["hash"]
    for offset, event in enumerate(events, 1):
        assert event["sequence"] == before_head["sequence"] + offset and event["previousHash"] == previous_hash
        previous_hash = event["hash"]
    assert previous_hash == after_head["hash"], "Ledger range does not reach the observed head"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/vapor-hardware")
    parser.add_argument("--resume-first-run-pid", type=int,
                        help="Read this still-running first-launch PID; retain the original saved public baseline")
    parser.add_argument("--first-run-log", type=Path,
                        help="Preserved threadtime first-run log; requires --resume-first-run-pid")
    args = parser.parse_args()
    if args.resume_first_run_pid is not None and args.resume_first_run_pid <= 0:
        parser.error("--resume-first-run-pid must be a positive PID")
    if args.first_run_log is not None and args.resume_first_run_pid is None:
        parser.error("--first-run-log requires --resume-first-run-pid")
    args.output.mkdir(parents=True, exist_ok=True)
    server = ROOT / "SwiftKeyServer"
    config = json.loads((server / "config/device.json").read_text())
    origin = f"http://{config['host']}:{config['port']}"
    pin = (server / ".state/server-public-key.txt").read_text().strip()
    admin_token = (server / ".state/admin-token").read_text().strip()

    def adb(*command):
        return subprocess.check_output(["adb", "-s", args.serial, *command], stderr=subprocess.PIPE)

    def api(path, body=None, admin=False):
        headers = {"Content-Type": "application/json"}
        if admin:
            headers["Authorization"] = "Bearer " + admin_token
        request = urllib.request.Request(origin + path, headers=headers,
                                         data=None if body is None else json.dumps(body).encode())
        try:
            with urllib.request.urlopen(request, timeout=35) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    def read_api(path):
        status, value = api(path, admin=True)
        assert status == 200, "Public authority readback failed"
        return value

    def is_saved_log(path):
        return args.first_run_log is not None and (path.resolve() == args.first_run_log.resolve()
            or (path.exists() and args.first_run_log.exists() and path.samefile(args.first_run_log)))

    def write_evidence(name, value):
        destination = args.output / name
        assert not is_saved_log(destination), "Refusing to overwrite the preserved first-run source log"
        destination.write_bytes(value.encode() if isinstance(value, str) else value)

    def save(name, value):
        write_evidence(name, json.dumps(value, indent=2) + "\n")

    def public_state():
        # Both files contain secrets. Keep raw JSON only in memory and emit
        # explicit public-field allowlists. No private key or bearer is saved.
        configuration = json.loads(adb("exec-out", "run-as", PACKAGE, "cat", "files/swiftkey-client.json"))
        state = json.loads(adb("exec-out", "run-as", PACKAGE, "cat", "files/swiftkey-protocol-state.json"))
        assert configuration["serverURL"] == state["serverURL"] == origin, "Installed app targets a different authority URL"
        assert configuration["serverPublicKey"] == pin == state["serverPublicKey"], "Authority pin mismatch"
        assert state.get("enrollment"), "Installed app must already be enrolled"
        enrollment = state["enrollment"]
        assert enrollment["serverPublicKey"] == pin
        expected = configuration.get("expectedAccountID")
        assert expected is None or expected == enrollment["accountID"], "Configured account differs from enrollment"
        return {"configuration": {key: configuration.get(key) for key in
                                  ["serverURL", "serverPublicKey", "expectedAccountID", "audience"]},
                "enrollment": {key: enrollment[key] for key in ["accountID", "deviceID", "publicKey", "serverPublicKey"]},
                "credential": public_credential((state.get("epochSnapshot") or {}).get("credential"))}

    def current_pids():
        try:
            values = adb("shell", "pidof", PACKAGE).decode().split()
            return [int(value) for value in values if value.isdecimal()]
        except subprocess.CalledProcessError:
            return []  # A newly launched process may not have a PID yet.

    def launch(name, resume_pid=None, previous_pid=None, saved_log=None):
        if resume_pid is None:
            prior_pids = current_pids()
            adb("shell", "am", "force-stop", PACKAGE)
            adb("shell", "am", "start", "-n", ACTIVITY)
        else:
            prior_pids = []
            assert resume_pid in current_pids(), "The explicitly resumed first-launch PID is no longer running"
            if saved_log is not None:
                text = saved_run_log(saved_log.read_text(), resume_pid)
                assert "SwiftKeyProtocol failed" not in text and "configurationUnavailable=true" not in text, \
                    "Saved first-run log contains a protocol failure"
                profile = completion_profile(text)
                assert profile is not None, "Saved first-run log does not contain a completed app profile"
                if not is_saved_log(args.output / name):
                    write_evidence(name, text)
                return text, resume_pid, profile
        deadline, text, observed_pid = time.monotonic() + 40, "", None
        while time.monotonic() < deadline:
            pids = current_pids()
            eligible = [pid for pid in pids if pid not in prior_pids and pid != previous_pid]
            if resume_pid is not None:
                assert resume_pid in pids, "The resumed first-launch process exited before evidence capture"
                eligible = [resume_pid]
            if len(eligible) != 1:
                time.sleep(0.25)
                continue
            observed_pid = eligible[0]
            raw = adb("logcat", "-d", "--pid=" + str(observed_pid), "-v", "threadtime").decode(errors="replace")
            lines = [line for line in raw.splitlines() if "SwiftKeyHardware:" in line or "SwiftKeyProtocol " in line]
            text = "\n".join(lines) + "\n"
            # Preserve the latest filtered evidence even if this polling run fails.
            write_evidence(name, text)
            if "SwiftKeyProtocol failed" in text or "configurationUnavailable=true" in text:
                raise AssertionError("Installed app reported a protocol failure; see filtered evidence log")
            profile = completion_profile(text)
            if profile:
                return text, observed_pid, profile
            time.sleep(0.25)
        write_evidence(name, text)
        raise AssertionError("Installed app did not complete its credential/workload profile within 40 seconds")

    if args.resume_first_run_pid is not None:
        # Never replace the expired-credential/head baseline with post-issuance
        # state. Resumption is only an evidence-capture retry, not another launch.
        before = json.loads((args.output / "android-before.json").read_text())
        authority_before = json.loads((args.output / "authority-before-device.json").read_text())
        assert before["configuration"]["serverURL"] == origin
        assert before["configuration"]["serverPublicKey"] == before["enrollment"]["serverPublicKey"] == pin
        assert public_state()["enrollment"] == before["enrollment"], "Resumed device differs from original baseline"
    else:
        before = public_state()
        authority_before = read_api("/v1/admin/status")
        save("android-before.json", before)
        save("authority-before-device.json", authority_before)
    assert authority_before["serverPublicKey"] == pin
    assert before["credential"] and before["credential"]["delegation"]["epoch"] < authority_before["epoch"], \
        "A fresh issuance is required; the original baseline credential is not from an earlier epoch"
    device = {"model": adb("shell", "getprop", "ro.product.model").decode().strip(),
              "sdk": adb("shell", "getprop", "ro.build.version.sdk").decode().strip(),
              "serialSHA256": hashlib.sha256(args.serial.encode()).hexdigest()}
    apk_path = adb("shell", "pm", "path", PACKAGE).decode().strip().splitlines()[0].removeprefix("package:")
    device["installedAPK_SHA256"] = adb("shell", "sha256sum", apk_path).decode().split()[0]
    adb("reverse", f"tcp:{config['port']}", f"tcp:{config['port']}")
    first_log, first_pid, profile = launch("android-fresh-epoch.log", resume_pid=args.resume_first_run_pid,
                                         saved_log=args.first_run_log)
    after = public_state()
    assert after["enrollment"] == before["enrollment"] and after["configuration"] == before["configuration"], \
        "Existing enrolled identity or public configuration changed"
    validate_run(first_log, after, profile, fresh=True)
    credential, enrollment = after["credential"], after["enrollment"]
    assert credential["delegation"]["epoch"] == authority_before["epoch"]
    assert credential["authorization"]["challenge"]["sequence"] > before["credential"]["authorization"]["challenge"]["sequence"]
    save("android-fresh-epoch.json", after)
    status, verification = api("/v1/credentials/verify", {"credential": credential})
    assert status == 200
    for field in ["accountID", "deviceID", "epoch"]:
        assert verification[field] == credential["delegation"][field], "Online verification returned a different identity or epoch"
    save("credential-verification.json", verification)
    tampered = copy.deepcopy(credential)
    signature = bytearray(base64.b64decode(tampered["serverSignature"], validate=True))
    signature[-1] ^= 1
    tampered["serverSignature"] = base64.b64encode(signature).decode()
    status, rejection = api("/v1/credentials/verify", {"credential": tampered})
    assert status == 403 and rejection.get("code") == "unknownCredential"
    save("tampered-credential-rejection.json", {"status": status, "response": rejection})
    ledger = read_api(f"/v1/admin/ledger?after={authority_before['ledgerHead']['sequence']}&limit=200")
    authority_after = read_api("/v1/admin/status")
    save("device-issuance-ledger.json", ledger)
    save("authority-after-first-run.json", authority_after)
    validate_ledger_range(ledger, authority_before["ledgerHead"], authority_after["ledgerHead"])
    expected_kinds = ["challenge.issued", "epoch.issued"]
    if profile == "workload-demonstration":
        expected_kinds.append("workload.accepted")
    # Another already-enrolled phone may issue its epoch after this original
    # baseline. Verify the complete global range, but bind first-run mutations
    # to this exact account/device instead of attributing its peer's events here.
    first_events = [event for event in ledger["events"]
                    if event.get("accountID") == enrollment["accountID"]
                    and event.get("deviceID") == enrollment["deviceID"]]
    assert [event["kind"] for event in first_events] == expected_kinds, "Unexpected first-launch device ledger mutations"
    save("device-issuance-events.json", first_events)
    challenge_event, issued_event = first_events[:2]
    assert challenge_event["details"]["operation"] == "issueEpoch"
    assert challenge_event["details"]["sequence"] == str(credential["authorization"]["challenge"]["sequence"])
    assert issued_event["details"]["epoch"] == str(credential["delegation"]["epoch"])
    assert issued_event["details"]["publicKey"] == base64.b64decode(credential["delegation"]["publicKey"], validate=True).hex()

    def validate_workload(event):
        assert event["kind"] == "workload.accepted"
        assert event.get("accountID") == enrollment["accountID"] and event.get("deviceID") == enrollment["deviceID"]
        assert event.get("actorDeviceID") == enrollment["deviceID"]
        assert event["details"]["epoch"] == str(credential["delegation"]["epoch"])
        assert event["details"]["domain"] == config["workloadDomain"]
        assert event["details"]["audience"] == config["workloadAudience"]
        assert re.fullmatch(r"[0-9a-f]{64}", event["details"]["nonceHash"])

    if profile == "workload-demonstration":
        validate_workload(first_events[-1])
    restart_log, restart_pid, restart_profile = launch("android-restart.log", previous_pid=first_pid)
    restarted = public_state()
    assert restart_pid != first_pid and restart_profile == profile
    assert restarted == after, "Restart did not preserve exact enrollment and credential"
    validate_run(restart_log, restarted, profile, fresh=False)
    restart_ledger = read_api(f"/v1/admin/ledger?after={authority_after['ledgerHead']['sequence']}&limit=200")
    authority_restarted = read_api("/v1/admin/status")
    save("device-restart-ledger.json", restart_ledger)
    validate_ledger_range(restart_ledger, authority_after["ledgerHead"], authority_restarted["ledgerHead"])
    expected_restart = ["workload.accepted"] if profile == "workload-demonstration" else []
    assert [event["kind"] for event in restart_ledger["events"]] == expected_restart, "Restart added unexpected ledger mutations"
    if profile == "workload-demonstration":
        validate_workload(restart_ledger["events"][0])
        assert restart_ledger["events"][0]["details"]["nonceHash"] != first_events[-1]["details"]["nonceHash"]
    for field in ["accountCount", "activeDeviceCount", "revokedDeviceCount"]:
        assert authority_restarted[field] == authority_before[field], "Device test changed account membership"
    # Global credential totals can also include the other observed phone.
    issued_count = sum(event["kind"] == "epoch.issued" for event in ledger["events"])
    assert authority_after["credentialCount"] == authority_before["credentialCount"] + issued_count
    assert authority_restarted["credentialCount"] == authority_after["credentialCount"]
    save("android-restart.json", restarted)
    save("authority-after-device.json", authority_restarted)
    write_evidence("android.png", adb("exec-out", "screencap", "-p"))
    save("verification.json", {"status": "passed", "device": device, "server": "Vapor 4.122.2",
         "installed_app_profile": profile, "first_run_pid": first_pid, "restart_pid": restart_pid,
         "resumed_first_run": args.resume_first_run_pid is not None,
         "first_run_log_preserved": args.first_run_log is not None,
         "existing_installed_app": True, "apk_reinstalled": False, "root_replaced": False,
         "fresh_strongbox_sign_verify": True, "fresh_vapor_epoch_issuance": True,
         "credential_verified_by_app_and_authority": True, "tampered_credential_rejected": True,
         "restart_reuses_same_credential": True, "restart_issued_another_epoch": False,
         "restart_reuses_same_credential_without_ledger_mutation": profile == "credential-only",
         "restart_accepted_workloads": len(restart_ledger["events"]),
         "fresh_boot_attestation": False, "workload_and_replay_exercised": profile == "workload-demonstration",
         "two_phone_v2_pairing_exercised": False})
    print("PASS: installed Android StrongBox identity verified a fresh Vapor epoch and preserved it across process restart; profile=" + profile)


if __name__ == "__main__":
    main()
