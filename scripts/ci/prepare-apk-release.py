#!/usr/bin/env python3
"""Configure a versioned CI build, then verify and package its signed APK."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "com.pureswift.swiftandroidui"


def positive_env(name: str) -> int:
    value = os.environ.get(name, "")
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise ValueError(f"{name} must be a positive integer")
    return int(value)


def version() -> tuple[int, str, str]:
    number = positive_env("GITHUB_RUN_NUMBER")
    code = 1000 + number
    if code > 2_100_000_000:
        raise ValueError("Android versionCode capacity exceeded")
    return code, f"1.0.{number}", f"v1.0.{number}"


def expected_signer() -> str:
    value = os.environ.get("ANDROID_SIGNING_CERT_SHA256", "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ValueError("Set the ANDROID_SIGNING_CERT_SHA256 repository variable")
    return value


def configure() -> None:
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("Signing restoration is restricted to the hosted CI job")
    code, name, tag = version()
    expected = expected_signer()
    encoded = os.environ.get("ANDROID_DEBUG_KEYSTORE_BASE64", "")
    if not encoded:
        raise ValueError("Set the ANDROID_DEBUG_KEYSTORE_BASE64 Actions secret")
    data = base64.b64decode(encoded, validate=True)
    if not 100 <= len(data) <= 65536:
        raise ValueError("Unexpected signing keystore size")
    path = Path.home() / ".android" / "debug.keystore"
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.exists():
        if path.is_symlink() or path.read_bytes() != data:
            raise ValueError("CI runner already has a different debug keystore")
    else:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
    path.chmod(0o600)
    # This is the existing Android development keystore, with the conventional
    # debug alias/password. The private keystore itself is an Actions secret.
    result = subprocess.run(
        [str(Path(os.environ["JAVA_HOME"]) / "bin/keytool"), "-list", "-v",
         "-keystore", str(path), "-alias", "androiddebugkey",
         "-storepass:env", "SWIFTKEY_DEBUG_STORE_PASSWORD"],
        env={**os.environ, "SWIFTKEY_DEBUG_STORE_PASSWORD": "android"},
        capture_output=True, text=True, check=True,
    )
    match = re.search(r"SHA256:\s*([0-9A-Fa-f:]+)", result.stdout)
    if not match or match[1].replace(":", "").lower() != expected:
        raise ValueError("Restored signing certificate does not match the repository pin")
    with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
        stream.write(f"ORG_GRADLE_PROJECT_swiftkeyVersionCode={code}\n")
        stream.write(f"ORG_GRADLE_PROJECT_swiftkeyVersionName={name}\n")
    print(f"Configured {tag}, Android versionCode {code}, with the pinned signing certificate")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def package(destination: Path) -> None:
    code, name, tag = version()
    commit = os.environ.get("GITHUB_SHA", "")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("GITHUB_SHA must identify the exact source commit")
    output = ROOT / "AndroidSwiftUI/Demo/app/build/outputs/apk/debug"
    metadata = json.loads((output / "output-metadata.json").read_text())
    elements = metadata["elements"]
    if metadata["applicationId"] != PACKAGE or len(elements) != 1:
        raise ValueError("Unexpected APK output metadata")
    element = elements[0]
    if element["versionCode"] != code or element["versionName"] != name:
        raise ValueError("Gradle did not apply the CI version to the APK")
    filename = element["outputFile"]
    if Path(filename).name != filename or not filename.endswith(".apk"):
        raise ValueError("Unsafe APK output filename")
    apk = output / filename
    sdk = Path(os.environ["ANDROID_HOME"]) / "build-tools/35.0.0"
    verified = subprocess.run(
        [str(sdk / "apksigner"), "verify", "--verbose", "--print-certs", str(apk)],
        capture_output=True, text=True, check=True,
    )
    certificates = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-f]+)", verified.stdout)
    if certificates != [expected_signer()]:
        raise ValueError("APK is not signed by the pinned development certificate")
    badging = subprocess.check_output([str(sdk / "aapt"), "dump", "badging", str(apk)], text=True)
    header = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    if not header or header.groups() != (PACKAGE, str(code), name):
        raise ValueError("Packaged Android manifest has the wrong application/version")
    native = re.search(r"^native-code: (.+)$", badging, re.M)
    if not native or re.findall(r"'([^']+)'", native[1]) != ["arm64-v8a"]:
        raise ValueError("APK must contain exactly the supported ARM64 ABI")
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        for library in ("libSwiftAndroidApp.so", "libSwiftJava.so", "libswiftCore.so"):
            if f"lib/arm64-v8a/{library}" not in names:
                raise ValueError(f"APK lacks the native runtime {library}")
        if any(re.match(r"lib/[^/]+/lib(?:XCTest|Testing|_Testing)", item) for item in names):
            raise ValueError("APK contains a test runtime")
    destination.mkdir(parents=True, exist_ok=False)
    final_name = f"SwiftKey-{tag}-arm64.apk"
    final_apk = destination / final_name
    shutil.copyfile(apk, final_apk)
    record = {
        "version_name": name, "version_code": code, "tag": tag, "commit": commit,
        "run_id": positive_env("GITHUB_RUN_ID"), "run_number": positive_env("GITHUB_RUN_NUMBER"),
        "run_attempt": positive_env("GITHUB_RUN_ATTEMPT"), "branch": os.environ["GITHUB_REF_NAME"],
        "apk": final_name, "sha256": digest(final_apk),
        "signing_certificate_sha256": certificates[0], "variant": "debug", "abi": "arm64-v8a",
        "package": PACKAGE,
    }
    manifest = destination / "build.json"
    manifest.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    (destination / "SHA256SUMS").write_text(
        f"{record['sha256']}  {final_name}\n{digest(manifest)}  build.json\n"
    )
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("configure", "package"))
    parser.add_argument("destination", nargs="?", type=Path, default=ROOT / "dist/android-release")
    args = parser.parse_args()
    if args.command == "configure":
        configure()
    else:
        package(args.destination)
