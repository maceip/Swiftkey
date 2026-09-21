#!/usr/bin/env python3
"""Publish one validated Android artifact set without replacing published assets.

Usage: GH_REPO=owner/repo GH_TOKEN=... python3 publish-apk-release.py ARTIFACT_DIR
The caller must serialize publishers. This script never deletes or moves a tag.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any


class PublishError(Exception):
    pass


METADATA_KEYS = {
    "version_name", "version_code", "tag", "commit", "run_id", "run_number",
    "run_attempt", "branch", "apk", "sha256", "signing_certificate_sha256",
    "variant", "abi", "package",
}
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
COMMIT = re.compile(r"[0-9a-f]{40}\Z")
VERSION = re.compile(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PublishError(message)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def decode_json(data: bytes) -> Any:
    def object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key")
            result[key] = value
        return result

    def invalid_constant(_: str) -> None:
        raise PublishError("Non-finite JSON number")

    try:
        return json.loads(data, object_pairs_hook=object_pairs, parse_constant=invalid_constant)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PublishError("Invalid JSON") from error


def metadata(data: bytes) -> dict[str, Any]:
    require(0 < len(data) <= 32768, "build.json exceeds its size limit")
    value = decode_json(data)
    require(isinstance(value, dict) and set(value) == METADATA_KEYS, "Unexpected build.json fields")
    for key in ("version_code", "run_id", "run_number", "run_attempt"):
        require(type(value[key]) is int and value[key] > 0, f"{key} must be a positive JSON integer")
    version = f"1.0.{value['run_number']}"
    require(value["version_name"] == version and value["tag"] == "v" + version, "Version/tag/run number mismatch")
    require(value["version_code"] == 1000 + value["run_number"] <= 2100000000, "Invalid Android version code")
    for key, pattern in (("commit", COMMIT), ("sha256", SHA256), ("signing_certificate_sha256", SHA256)):
        require(isinstance(value[key], str) and pattern.fullmatch(value[key]) is not None, f"Invalid {key}")
    require(value["apk"] == f"SwiftKey-v{version}-arm64.apk", "Unexpected APK filename")
    require(value["variant"] == "debug" and value["abi"] == "arm64-v8a"
            and value["package"] == "com.pureswift.swiftandroidui", "Unexpected Android artifact identity")
    branch = value["branch"]
    require(isinstance(branch, str) and 0 < len(branch.encode("utf-8")) <= 1024
            and not any(ord(c) < 32 or ord(c) == 127 for c in branch), "Invalid branch")
    return value


def checksums(data: bytes, build: dict[str, Any], build_bytes: bytes) -> dict[str, str]:
    require(0 < len(data) <= 4096, "Invalid SHA256SUMS size")
    try:
        lines = data.decode("ascii").splitlines()
    except UnicodeDecodeError as error:
        raise PublishError("SHA256SUMS must be ASCII") from error
    sums: dict[str, str] = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64}) [ *]([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        require(match is not None, "Malformed SHA256SUMS entry")
        checksum, name = match.groups()
        require(name not in sums, "Duplicate SHA256SUMS entry")
        sums[name] = checksum
    require(set(sums) == {build["apk"], "build.json"}, "SHA256SUMS must contain exactly APK and build.json")
    require(sums["build.json"] == digest(build_bytes), "build.json checksum mismatch")
    require(sums[build["apk"]] == build["sha256"], "APK checksum metadata mismatch")
    return sums


def regular_file(directory: Path, name: str) -> Path:
    path = directory / name
    require(not path.is_symlink() and path.is_file(), f"Missing or unsafe artifact: {name}")
    return path


def validate_local(directory: Path) -> tuple[dict[str, Any], list[Path]]:
    require(directory.is_dir(), "Artifact directory does not exist")
    build_file = regular_file(directory, "build.json")
    require(build_file.stat().st_size <= 32768, "build.json exceeds its size limit")
    build_bytes = build_file.read_bytes()
    build = metadata(build_bytes)
    sums_file = regular_file(directory, "SHA256SUMS")
    require(sums_file.stat().st_size <= 4096, "SHA256SUMS exceeds its size limit")
    checksums(sums_file.read_bytes(), build, build_bytes)
    apk_file = regular_file(directory, build["apk"])
    require(apk_file.stat().st_size > 0, "APK is empty")
    with apk_file.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    require(actual == build["sha256"], "APK checksum mismatch")
    return build, [apk_file, sums_file, build_file]


class GitHub:
    def __init__(self, repo: str, runner=None):
        require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repo) is not None,
                "GH_REPO must be owner/repository")
        self.repo = repo
        self.prefix = f"repos/{repo}/"
        self.runner = runner or subprocess.run

    def run(self, *args: str):
        return self.runner(["gh", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)

    def command(self, *args: str) -> None:
        result = self.run(*args)
        require(result.returncode == 0, f"gh {' '.join(args[:2])} failed (exit {result.returncode})")

    def api(self, endpoint: str, *, missing_ok: bool = False, payload: dict | None = None) -> Any:
        with tempfile.TemporaryDirectory(prefix="swiftkey-release-api-") as temporary:
            args = ["api", self.prefix + endpoint, "--include"]
            if payload is not None:
                body = Path(temporary) / "request.json"
                body.write_text(json.dumps(payload), encoding="utf-8")
                args += ["--method", "PATCH", "--input", str(body)]
            result = self.run(*args)
        header, separator, body = result.stdout.replace(b"\r\n", b"\n", 1).partition(b"\n")
        match = re.fullmatch(rb"HTTP/\S+ (\d{3})(?: .*)?", header.strip())
        require(separator != b"" and match is not None, "GitHub API did not return an HTTP status")
        # gh --include uses either CRLF or LF for the complete header block.
        rest = body.replace(b"\r\n", b"\n")
        _, separator, body = rest.partition(b"\n\n")
        # A response with no additional headers has a single blank line left.
        if rest.startswith(b"\n"):
            separator, body = b"\n", rest[1:]
        status = int(match.group(1))
        if status == 404 and missing_ok:
            return None
        require(result.returncode == 0 and 200 <= status < 300, f"GitHub API {endpoint} returned HTTP {status}")
        require(separator != b"", "GitHub API response headers are incomplete")
        return decode_json(body)

    def download(self, asset: dict, *, limit: int | None = None) -> bytes:
        asset_id, size = asset.get("id"), asset.get("size")
        require(type(asset_id) is int and asset_id > 0 and type(size) is int and size > 0,
                "Invalid release asset metadata")
        if limit is not None:
            require(size <= limit, "Remote metadata asset exceeds size limit")
        result = self.run("api", self.prefix + f"releases/assets/{asset_id}",
                          "--header", "Accept: application/octet-stream")
        require(result.returncode == 0 and len(result.stdout) == size, "Could not verify release asset bytes")
        return result.stdout

    def tag_commit(self, tag: str) -> str | None:
        ref = self.api("git/ref/tags/" + tag, missing_ok=True)
        if ref is None:
            return None
        obj = ref.get("object", {})
        seen = set()
        for _ in range(8):
            sha, kind = obj.get("sha"), obj.get("type")
            require(isinstance(sha, str) and COMMIT.fullmatch(sha) is not None, "Malformed tag target")
            require(sha not in seen, "Annotated tag cycle")
            seen.add(sha)
            if kind == "commit":
                return sha
            require(kind == "tag", "Tag does not point to a commit")
            obj = self.api("git/tags/" + sha).get("object", {})
        raise PublishError("Annotated tag nesting exceeds limit")

    def find_release(self, tag: str) -> dict | None:
        release = self.api("releases/tags/" + tag, missing_ok=True)
        if release is not None:
            require(isinstance(release, dict), "Invalid release response")
            return release
        # The tag endpoint is documented for published releases. Authenticated
        # listings include drafts for this publisher's Contents-write token.
        matches = []
        for page in range(1, 101):
            releases = self.api(f"releases?per_page=100&page={page}")
            require(isinstance(releases, list) and all(isinstance(r, dict) for r in releases),
                    "Invalid release listing")
            matches.extend(r for r in releases if r.get("tag_name") == tag)
            require(len(matches) <= 1, "Multiple releases use the requested tag")
            if len(releases) < 100:
                return matches[0] if matches else None
        raise PublishError("Release history exceeds safe draft lookup limit")


def release_assets(release: dict, *, require_uploaded: bool = True) -> dict[str, dict]:
    result: dict[str, dict] = {}
    assets = release.get("assets")
    require(isinstance(assets, list), "Release asset list is unavailable")
    for asset in assets:
        require(isinstance(asset, dict) and isinstance(asset.get("name"), str), "Invalid release asset")
        name = asset["name"]
        require(name not in result and (not require_uploaded or asset.get("state") == "uploaded"),
                "Duplicate or incomplete release asset")
        result[name] = asset
    return result


def verify_release(gh: GitHub, release: dict, expected: dict[str, Any]) -> None:
    require(release.get("tag_name") == expected["tag"], "Release tag mismatch")
    assets = release_assets(release)
    require(set(assets) == {expected["apk"], "SHA256SUMS", "build.json"}, "Release assets are incomplete or unexpected")
    build_bytes = gh.download(assets["build.json"], limit=32768)
    original = metadata(build_bytes)
    for key in ("tag", "commit", "version_name", "version_code", "apk"):
        require(original[key] == expected[key], f"Published {key} differs from requested release")
    checksums(gh.download(assets["SHA256SUMS"], limit=4096), original, build_bytes)
    apk = assets[original["apk"]]
    require(type(apk.get("size")) is int and apk["size"] > 0, "Remote APK is empty")
    server_digest = apk.get("digest")
    if isinstance(server_digest, str) and server_digest.startswith("sha256:"):
        require(server_digest == "sha256:" + original["sha256"], "Published APK checksum mismatch")
    else:
        require(digest(gh.download(apk)) == original["sha256"], "Published APK checksum mismatch")


def version_tuple(tag: Any) -> tuple[int, int, int] | None:
    match = VERSION.fullmatch(tag) if isinstance(tag, str) else None
    return tuple(map(int, match.groups())) if match else None


def publish(directory: Path, gh: GitHub) -> dict[str, Any]:
    build, files = validate_local(directory.resolve())
    tag, commit = build["tag"], build["commit"]
    target = gh.tag_commit(tag)
    require(target is None or target == commit, "Existing tag targets another commit; refusing to move it")
    release = gh.find_release(tag)
    if release is not None:
        require(type(release.get("draft")) is bool, "Invalid release draft state")
        if not release["draft"]:
            require(target == commit, "Published release has no matching immutable tag")
            verify_release(gh, release, build)
            return {"status": "already-published", "tag": tag, "commit": commit}
        require(target == commit or release.get("target_commitish") == commit,
                "Existing draft targets another commit")
        require(set(release_assets(release, require_uploaded=False)).issubset({build["apk"], "SHA256SUMS", "build.json"}),
                "Existing draft contains unexpected assets")
    else:
        with tempfile.TemporaryDirectory(prefix="swiftkey-release-notes-") as temporary:
            notes = Path(temporary) / "notes.md"
            notes.write_text(f"Automated SwiftKey Android debug build from `{commit}`.\n\n"
                             f"Version {build['version_name']} ({build['version_code']}); arm64-v8a.\n"
                             "APK checksum and build provenance are attached.\n", encoding="utf-8")
            args = ["release", "create", tag, "--repo", gh.repo, "--draft", "--target", commit,
                    "--title", "SwiftKey " + build["version_name"], "--notes-file", str(notes)]
            if target is not None:
                args.append("--verify-tag")
            gh.command(*args)
        release = gh.find_release(tag)
    require(isinstance(release, dict), "Created release is unavailable")
    require(release.get("draft") is True and release.get("tag_name") == tag, "Expected an unpublished draft")
    require(type(release.get("id")) is int and release["id"] > 0, "Invalid release ID")
    release_id = release["id"]
    gh.command("release", "upload", tag, "--repo", gh.repo, "--clobber", *(str(p) for p in files))
    release = gh.api(f"releases/{release_id}")
    require(release.get("draft") is True, "Release was published concurrently; refusing further changes")
    verify_release(gh, release, build)
    target = gh.tag_commit(tag)
    require(target == commit or (target is None and release.get("target_commitish") == commit),
            "Draft/tag target changed before publication")
    latest = gh.api("releases/latest", missing_ok=True)
    candidate_version = version_tuple(tag)
    latest_version = version_tuple(latest.get("tag_name")) if latest is not None else None
    make_latest = latest is None or (latest_version is not None and candidate_version > latest_version)
    gh.api(f"releases/{release_id}", payload={"draft": False, "prerelease": False,
                                           "make_latest": "true" if make_latest else "false"})
    require(gh.tag_commit(tag) == commit, "Published tag target verification failed")
    published = gh.api(f"releases/{release_id}")
    require(published.get("draft") is False, "Release is still a draft")
    verify_release(gh, published, build)
    return {"status": "published", "tag": tag, "commit": commit, "made_latest": make_latest}


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    try:
        require(len(args) == 1, "Usage: publish-apk-release.py ARTIFACT_DIR")
        require(bool(os.environ.get("GH_TOKEN")), "GH_TOKEN is required")
        gh = GitHub(os.environ.get("GH_REPO", ""))
        print(json.dumps(publish(Path(args[0]), gh), sort_keys=True))
        return 0
    except (PublishError, OSError, ValueError) as error:
        print(f"Release publication failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
