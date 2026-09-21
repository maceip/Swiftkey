#!/usr/bin/env python3
"""Offline release lifecycle tests. All gh invocations use an in-memory fake."""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("publish-apk-release.py"))
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)
COMMIT = "a" * 40
OTHER_COMMIT = "b" * 40


def artifacts(directory, number=12, *, apk_bytes=b"APK-original", commit=COMMIT, attempt=1):
    directory.mkdir(parents=True, exist_ok=True)
    build = {
        "version_name": f"1.0.{number}", "version_code": 1000 + number, "tag": f"v1.0.{number}",
        "commit": commit, "run_id": 87654, "run_number": number, "run_attempt": attempt,
        "branch": "feature/test", "apk": f"SwiftKey-v1.0.{number}-arm64.apk",
        "sha256": hashlib.sha256(apk_bytes).hexdigest(), "signing_certificate_sha256": "c" * 64,
        "variant": "debug", "abi": "arm64-v8a", "package": "com.pureswift.swiftandroidui",
    }
    (directory / build["apk"]).write_bytes(apk_bytes)
    write_metadata(directory, build)
    return build


def write_metadata(directory, build):
    data = (json.dumps(build, indent=2) + "\n").encode()
    (directory / "build.json").write_bytes(data)
    (directory / "SHA256SUMS").write_text(
        f"{build['sha256']}  {build['apk']}\n{hashlib.sha256(data).hexdigest()}  build.json\n")


class FakeGh:
    """Models tags, drafts, upload interruption, asset digests and latest state."""

    def __init__(self):
        self.calls = []
        self.tags = {}
        self.annotated = {}
        self.releases = {}
        self.asset_bytes = {}
        self.latest = None
        self.next_id = 1
        self.fail_upload_after = None
        self.api_status = {}
        self.patch_status = None
        self.post_status = None
        self.create_response_overrides = {}
        self.hide_new_drafts_from_listing = False
        self.created_tags = set()
        self.release_read_statuses = []

    @staticmethod
    def response(argv, data=None, status=200):
        body = json.dumps(data).encode()
        raw = f"HTTP/2.0 {status} Status\r\nContent-Type: application/json\r\n\r\n".encode() + body
        return subprocess.CompletedProcess(argv, 0 if status < 400 else 1, raw, b"")

    def mutations(self):
        return [c for c in self.calls if c[1] == "release" or "PATCH" in c or "POST" in c]

    def add_asset(self, release, name, data):
        release["assets"] = [a for a in release["assets"] if a["name"] != name]
        asset = {"id": self.next_id, "name": name, "state": "uploaded", "size": len(data),
                 "digest": "sha256:" + hashlib.sha256(data).hexdigest()}
        self.next_id += 1
        self.asset_bytes[asset["id"]] = data
        release["assets"].append(asset)

    def add_release(self, directory, *, draft=False, latest=False, target=None):
        build = json.loads((directory / "build.json").read_bytes())
        release = {"id": self.next_id, "tag_name": build["tag"], "draft": draft, "prerelease": False,
                   "target_commitish": target or build["commit"], "assets": []}
        self.next_id += 1
        self.releases[build["tag"]] = release
        for name in [build["apk"], "SHA256SUMS", "build.json"]:
            self.add_asset(release, name, (directory / name).read_bytes())
        if not draft:
            self.tags[build["tag"]] = {"type": "commit", "sha": target or build["commit"]}
        if latest:
            self.latest = build["tag"]
        return release

    def __call__(self, argv, **kwargs):
        self.calls.append(list(argv))
        assert argv[0] == "gh"
        if argv[1] == "api":
            endpoint = argv[2].removeprefix("repos/maceip/SwiftKey/")
            if endpoint in self.api_status:
                return self.response(argv, {"message": "failure"}, self.api_status[endpoint])
            if endpoint.startswith("releases/assets/"):
                data = self.asset_bytes[int(endpoint.rsplit("/", 1)[1])]
                return subprocess.CompletedProcess(argv, 0, data, b"")
            if "POST" in argv:
                assert endpoint == "releases"
                if self.post_status is not None:
                    return self.response(argv, {"message": "failure"}, self.post_status)
                payload = json.loads(Path(argv[argv.index("--input") + 1]).read_bytes())
                self.last_create = payload
                tag = payload["tag_name"]
                assert tag not in self.releases and payload["draft"] is True
                release = dict(payload, id=self.next_id, assets=[])
                self.next_id += 1
                self.releases[tag] = release
                self.created_tags.add(tag)
                return self.response(argv, dict(release, **self.create_response_overrides), 201)
            if "PATCH" in argv:
                if self.patch_status is not None:
                    return self.response(argv, {"message": "failure"}, self.patch_status)
                release_id = int(endpoint.rsplit("/", 1)[1])
                release = next(r for r in self.releases.values() if r["id"] == release_id)
                payload = json.loads(Path(argv[argv.index("--input") + 1]).read_bytes())
                self.last_patch = payload
                release["draft"] = payload["draft"]
                release["prerelease"] = payload["prerelease"]
                self.tags.setdefault(release["tag_name"], {"type": "commit", "sha": release["target_commitish"]})
                if payload["make_latest"] == "true":
                    self.latest = release["tag_name"]
                return self.response(argv, release)
            if endpoint.startswith("git/ref/tags/"):
                obj = self.tags.get(endpoint.removeprefix("git/ref/tags/"))
                return self.response(argv, {"object": obj} if obj else {}, 200 if obj else 404)
            if endpoint.startswith("git/tags/"):
                return self.response(argv, {"object": self.annotated[endpoint.rsplit("/", 1)[1]]})
            if endpoint == "releases/latest":
                return self.response(argv, self.releases.get(self.latest), 200 if self.latest else 404)
            if endpoint.startswith("releases/tags/"):
                release = self.releases.get(endpoint.removeprefix("releases/tags/"))
                if release and release.get("draft"):
                    release = None
                return self.response(argv, release, 200 if release else 404)
            if endpoint.startswith("releases?per_page=100&page="):
                page = int(endpoint.rsplit("=", 1)[1])
                releases = [r for tag, r in self.releases.items()
                            if not (self.hide_new_drafts_from_listing and tag in self.created_tags)]
                return self.response(argv, releases[(page - 1) * 100:page * 100])
            if endpoint.startswith("releases/"):
                if self.release_read_statuses:
                    status = self.release_read_statuses.pop(0)
                    if status != 200:
                        return self.response(argv, {"message": "failure"}, status)
                release_id = int(endpoint.rsplit("/", 1)[1])
                return self.response(argv, next(r for r in self.releases.values() if r["id"] == release_id))
            raise AssertionError("Unexpected API endpoint " + endpoint)
        if argv[1:3] == ["release", "upload"]:
            release = self.releases[argv[3]]
            assert release["draft"], "A published release must never be modified"
            files = argv[argv.index("--clobber") + 1:]
            for count, name in enumerate(files, 1):
                path = Path(name)
                self.add_asset(release, path.name, path.read_bytes())
                if self.fail_upload_after == count:
                    return subprocess.CompletedProcess(argv, 1, b"", b"interrupted")
            return subprocess.CompletedProcess(argv, 0, b"", b"")
        raise AssertionError("Unexpected gh invocation " + str(argv))


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name) / "artifacts"
        self.build = artifacts(self.directory)
        self.fake = FakeGh()
        self.sleeps = []
        self.gh = publisher.GitHub("maceip/SwiftKey", runner=self.fake, sleeper=self.sleeps.append)

    def publish(self):
        return publisher.publish(self.directory, self.gh)

    def test_first_release_uploads_verified_assets_while_draft_then_becomes_latest(self):
        result = self.publish()
        self.assertEqual(result["status"], "published")
        self.assertTrue(result["made_latest"])
        self.assertEqual(self.fake.latest, self.build["tag"])
        self.assertEqual(self.fake.tags[self.build["tag"]]["sha"], COMMIT)
        self.assertEqual(set(self.fake.last_patch), {"draft", "prerelease", "make_latest"})
        operations = [(c[1:3] if c[1] == "release" else [c[c.index("--method") + 1]])
                      for c in self.fake.mutations()]
        self.assertEqual(operations, [["POST"], ["release", "upload"], ["PATCH"]])
        self.assertEqual(self.fake.last_create["target_commitish"], COMMIT)

    def test_creation_uses_returned_id_even_when_draft_listing_remains_stale(self):
        self.fake.hide_new_drafts_from_listing = True
        self.assertEqual(self.publish()["status"], "published")
        create_index = next(i for i, c in enumerate(self.fake.calls) if "POST" in c)
        after_create = self.fake.calls[create_index + 1:]
        self.assertFalse(any("releases?" in c[2] or "releases/tags/" in c[2] for c in after_create))
        release_id = self.fake.releases[self.build["tag"]]["id"]
        self.assertEqual(sum(c[2].endswith(f"releases/{release_id}") and "GET" in c
                             for c in after_create), 2)

    def test_created_draft_identity_is_checked_before_upload(self):
        for override in ({"target_commitish": OTHER_COMMIT}, {"tag_name": "v1.0.999"},
                         {"id": True}, {"draft": False}):
            with self.subTest(override=override):
                fake = FakeGh()
                fake.create_response_overrides = override
                gh = publisher.GitHub("maceip/SwiftKey", runner=fake)
                with self.assertRaises(publisher.PublishError):
                    publisher.publish(self.directory, gh)
                self.assertEqual(len(fake.mutations()), 1)
                self.assertIn("POST", fake.mutations()[0])

    def test_transient_by_id_reads_retry_with_bounded_backoff_only(self):
        self.fake.release_read_statuses = [404, 503, 200, 502, 200]
        self.assertEqual(self.publish()["status"], "published")
        self.assertEqual(self.sleeps, [1, 2, 1])
        self.assertEqual(sum("POST" in c for c in self.fake.calls), 1)
        self.assertEqual(sum("PATCH" in c for c in self.fake.calls), 1)

    def test_api_reads_revalidate_cached_responses_after_upload_and_publication(self):
        self.publish()
        reads = [c for c in self.fake.calls if c[1] == "api" and "GET" in c]
        self.assertGreater(len(reads), 0)
        for call in reads:
            self.assertIn("Cache-Control: no-cache", call)
        release_id = self.fake.releases[self.build["tag"]]["id"]
        post_upload_reads = [c for c in reads if c[2].endswith(f"releases/{release_id}")]
        self.assertEqual(len(post_upload_reads), 2)

    def test_by_id_retry_exhaustion_leaves_complete_draft_unpublished(self):
        self.fake.release_read_statuses = [404] * 4
        with self.assertRaisesRegex(publisher.PublishError, "HTTP 404"):
            self.publish()
        self.assertEqual(self.sleeps, [1, 2, 4])
        release = self.fake.releases[self.build["tag"]]
        self.assertTrue(release["draft"])
        self.assertEqual(len(release["assets"]), 3)
        self.assertFalse(any("PATCH" in c for c in self.fake.calls))

    def test_by_id_auth_error_does_not_retry_or_publish(self):
        self.fake.release_read_statuses = [403]
        with self.assertRaisesRegex(publisher.PublishError, "HTTP 403"):
            self.publish()
        self.assertEqual(self.sleeps, [])
        self.assertFalse(any("PATCH" in c for c in self.fake.calls))

    def test_creation_error_is_never_retried(self):
        self.fake.post_status = 503
        with self.assertRaisesRegex(publisher.PublishError, "HTTP 503"):
            self.publish()
        self.assertEqual(self.sleeps, [])
        self.assertEqual(len(self.fake.mutations()), 1)

    def test_published_rerun_preserves_original_bytes_and_metadata(self):
        release = self.fake.add_release(self.directory, latest=True)
        original = copy.deepcopy(release)
        original_bytes = copy.deepcopy(self.fake.asset_bytes)
        artifacts(self.directory, apk_bytes=b"different valid rebuilt APK", attempt=2)
        self.assertEqual(self.publish()["status"], "already-published")
        self.assertEqual(self.fake.mutations(), [])
        self.assertEqual(release, original)
        self.assertEqual(self.fake.asset_bytes, original_bytes)

    def test_out_of_order_release_does_not_replace_newer_latest(self):
        newer = Path(self.temporary.name) / "newer"
        artifacts(newer, number=20)
        self.fake.add_release(newer, latest=True)
        self.assertFalse(self.publish()["made_latest"])
        self.assertEqual(self.fake.latest, "v1.0.20")

    def test_newer_release_promotes_latest(self):
        older = Path(self.temporary.name) / "older"
        artifacts(older, number=9)
        self.fake.add_release(older, latest=True)
        self.assertTrue(self.publish()["made_latest"])
        self.assertEqual(self.fake.latest, "v1.0.12")

    def test_unknown_latest_version_is_preserved(self):
        self.fake.latest = "preview-custom"
        self.fake.releases[self.fake.latest] = {"id": 9999, "tag_name": self.fake.latest}
        self.assertFalse(self.publish()["made_latest"])
        self.assertEqual(self.fake.latest, "preview-custom")

    def test_upload_failure_leaves_draft_then_rerun_repairs_it(self):
        self.fake.fail_upload_after = 1
        with self.assertRaisesRegex(publisher.PublishError, "upload failed"):
            self.publish()
        release = self.fake.releases[self.build["tag"]]
        self.assertTrue(release["draft"])
        self.assertIsNone(self.fake.latest)
        self.assertEqual(len(release["assets"]), 1)
        # GitHub may retain a starter asset after a failed upload.
        release["assets"][0]["state"] = "starter"
        self.fake.fail_upload_after = None
        self.assertEqual(self.publish()["status"], "published")
        self.assertEqual(len(release["assets"]), 3)

    def test_existing_draft_with_wrong_commit_is_not_repaired(self):
        self.fake.add_release(self.directory, draft=True, target=OTHER_COMMIT)
        with self.assertRaisesRegex(publisher.PublishError, "draft targets another commit"):
            self.publish()
        self.assertEqual(self.fake.mutations(), [])

    def test_draft_lookup_uses_all_pages_then_refreshes_by_id(self):
        for number in range(100):
            self.fake.releases[f"old-{number}"] = {"id": 10000 + number, "tag_name": f"old-{number}", "draft": False}
        release = self.fake.add_release(self.directory, draft=True)
        self.assertEqual(self.publish()["status"], "published")
        self.assertTrue(any(c[2].endswith("releases?per_page=100&page=2") for c in self.fake.calls))
        self.assertTrue(any(c[2].endswith(f"releases/{release['id']}") for c in self.fake.calls))

    def test_publish_failure_leaves_complete_draft_for_retry(self):
        self.fake.patch_status = 503
        with self.assertRaisesRegex(publisher.PublishError, "HTTP 503"):
            self.publish()
        release = self.fake.releases[self.build["tag"]]
        self.assertTrue(release["draft"])
        self.assertEqual(len(release["assets"]), 3)
        self.assertIsNone(self.fake.latest)
        self.fake.patch_status = None
        self.assertEqual(self.publish()["status"], "published")

    def test_existing_tag_with_wrong_commit_is_never_moved(self):
        self.fake.tags[self.build["tag"]] = {"type": "commit", "sha": OTHER_COMMIT}
        with self.assertRaisesRegex(publisher.PublishError, "refusing to move"):
            self.publish()
        self.assertEqual(self.fake.mutations(), [])

    def test_incomplete_published_release_fails_without_uploading(self):
        release = self.fake.add_release(self.directory)
        release["assets"].pop()
        with self.assertRaisesRegex(publisher.PublishError, "incomplete"):
            self.publish()
        self.assertEqual(self.fake.mutations(), [])

    def test_published_digest_mismatch_fails_closed(self):
        release = self.fake.add_release(self.directory)
        release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(publisher.PublishError, "APK checksum mismatch"):
            self.publish()
        self.assertEqual(self.fake.mutations(), [])

    def test_missing_server_digest_downloads_and_checks_original_apk(self):
        release = self.fake.add_release(self.directory)
        apk = release["assets"][0]
        apk.pop("digest")
        self.assertEqual(self.publish()["status"], "already-published")
        self.assertTrue(any(c[2].endswith(f"releases/assets/{apk['id']}") for c in self.fake.calls))

    def test_published_metadata_commit_mismatch_fails_closed(self):
        old = Path(self.temporary.name) / "old"
        artifacts(old, commit=OTHER_COMMIT)
        self.fake.add_release(old)
        self.fake.tags[self.build["tag"]] = {"type": "commit", "sha": COMMIT}
        with self.assertRaisesRegex(publisher.PublishError, "Published commit differs"):
            self.publish()
        self.assertEqual(self.fake.mutations(), [])

    def test_annotated_existing_tag_is_peeled_and_verified_without_retargeting(self):
        self.fake.tags[self.build["tag"]] = {"type": "tag", "sha": "d" * 40}
        self.fake.annotated["d" * 40] = {"type": "tag", "sha": "e" * 40}
        self.fake.annotated["e" * 40] = {"type": "commit", "sha": COMMIT}
        self.assertEqual(self.publish()["status"], "published")
        self.assertEqual(self.fake.last_create["target_commitish"], COMMIT)
        self.assertEqual(self.fake.tags[self.build["tag"]]["sha"], "d" * 40)

    def test_annotated_tag_cycle_and_excessive_nesting_fail(self):
        self.fake.tags[self.build["tag"]] = {"type": "tag", "sha": "d" * 40}
        self.fake.annotated["d" * 40] = {"type": "tag", "sha": "d" * 40}
        with self.assertRaisesRegex(publisher.PublishError, "cycle"):
            self.publish()
        self.assertEqual(self.fake.mutations(), [])
        self.fake.tags[self.build["tag"]] = {"type": "tag", "sha": f"{1:040x}"}
        self.fake.annotated = {f"{n:040x}": {"type": "tag", "sha": f"{n+1:040x}"} for n in range(1, 10)}
        with self.assertRaisesRegex(publisher.PublishError, "nesting"):
            self.publish()

    def test_auth_failure_is_not_mistaken_for_missing_tag(self):
        self.fake.api_status["git/ref/tags/" + self.build["tag"]] = 401
        with self.assertRaisesRegex(publisher.PublishError, "HTTP 401"):
            self.publish()
        self.assertEqual(self.fake.mutations(), [])

    def test_invalid_local_metadata_causes_no_github_calls(self):
        for key, value in [("run_number", True), ("run_attempt", "2"), ("version_code", 1),
                           ("version_name", "1.0.013"), ("commit", "main"), ("apk", "../private.apk"),
                           ("signing_certificate_sha256", "not-a-digest"), ("variant", "release")]:
            with self.subTest(key=key):
                bad = dict(self.build, **{key: value})
                write_metadata(self.directory, bad)
                with self.assertRaises(publisher.PublishError):
                    self.publish()
                self.assertEqual(self.fake.calls, [])

    def test_local_apk_tampering_and_symlinks_are_rejected(self):
        path = self.directory / self.build["apk"]
        path.write_bytes(b"tampered")
        with self.assertRaisesRegex(publisher.PublishError, "APK checksum mismatch"):
            self.publish()
        path.unlink()
        outside = Path(self.temporary.name) / "outside.apk"
        outside.write_bytes(b"APK-original")
        path.symlink_to(outside)
        with self.assertRaisesRegex(publisher.PublishError, "unsafe artifact"):
            self.publish()
        self.assertEqual(self.fake.calls, [])

    def test_checksums_require_both_assets_and_no_unexpected_paths(self):
        sums = self.directory / "SHA256SUMS"
        correct = sums.read_text()
        for content in [correct.splitlines()[0] + "\n", correct + correct.splitlines()[0] + "\n",
                        correct.replace("build.json", "../build.json")]:
            sums.write_text(content)
            with self.assertRaises(publisher.PublishError):
                self.publish()
            self.assertEqual(self.fake.calls, [])


if __name__ == "__main__":
    unittest.main()
