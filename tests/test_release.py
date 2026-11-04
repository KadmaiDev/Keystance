"""Tests for tools/release.py: nothing is published unless every check passes first, and the
zip only holds files that are in the commit. Publishing (CurseForge, git tags, GitHub) is
faked; nothing here touches the network. Run from the addon folder:

    python tests/test_release.py
"""
import os
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True  # no __pycache__ left in tools/
sys.path.insert(0, os.path.join(ROOT, "tools"))
import release  # noqa: E402

VER = "9.9.9"


class Publishing(unittest.TestCase):
    """Runs release.main with git, gh, the build and the uploads faked. `tag_on` is the
    commit tag v9.9.9 is on (None: no such tag); `gh_release` whether a GitHub release of it
    exists."""

    def setUp(self):
        self.calls = []
        self.tag_on = None
        self.gh_release = False
        self.gh_signed_in = True
        self.dir = tempfile.TemporaryDirectory()
        self.changelog = os.path.join(self.dir.name, "CHANGELOG.md")
        self.write_changelog("## Keystance " + VER)
        self.marker = os.path.join(self.dir.name, "uploaded-" + VER)

    def tearDown(self):
        self.dir.cleanup()

    def write_changelog(self, heading):
        with open(self.changelog, "w", encoding="utf-8") as f:
            f.write(heading + "\n\n- A change.\n")

    def fake_run(self, *args):
        if args[:3] == ("git", "tag", "--list"):
            return args[3] if self.tag_on else ""
        if args[:2] == ("git", "rev-parse"):
            return {"HEAD": "head"}.get(args[2], self.tag_on)
        raise AssertionError("unexpected command %r" % (args,))

    def fake_subprocess(self, args, **kwargs):
        if args[:3] == ["gh", "release", "view"]:
            return SimpleNamespace(returncode=0 if self.gh_release else 1)
        if args[:3] == ["gh", "auth", "status"]:
            return SimpleNamespace(returncode=0 if self.gh_signed_in else 1)
        raise AssertionError("unexpected command %r" % (args,))

    def main(self, mode, token=True):
        def fake_token():
            if not token:
                release.fail("CURSE_API_KEY is not set")
            return "secret"
        with mock.patch.object(release, "run", self.fake_run), \
                mock.patch.object(release.subprocess, "run", self.fake_subprocess), \
                mock.patch.object(release, "check_pushed", lambda: self.calls.append("check_pushed")), \
                mock.patch.object(release, "version", lambda: VER), \
                mock.patch.object(release, "uploaded_marker", lambda ver: self.marker), \
                mock.patch.object(release, "token", fake_token), \
                mock.patch.object(release, "build", lambda publishing: self.calls.append("build") or ("zip", VER)), \
                mock.patch.object(release, "upload", lambda *a: self.calls.append("upload")), \
                mock.patch.object(release, "github_release", lambda *a: self.calls.append("github")):
            release.main(["release.py", mode, self.changelog])

    def refused(self, mode="--upload", **kw):
        with self.assertRaises(SystemExit):
            self.main(mode, **kw)
        self.assertNotIn("upload", self.calls)
        self.assertNotIn("github", self.calls)

    def test_everything_fine_goes_in_order(self):
        self.main("--upload")
        self.assertEqual(self.calls, ["check_pushed", "build", "upload", "github"])

    def test_tag_on_another_commit_stops_before_the_upload(self):
        self.tag_on = "older"  # the review's case: v0.1.0 on an older commit, .toc still 0.1.0
        self.refused()
        self.refused("--github")

    def test_existing_tag_stops_an_upload_but_lets_github_finish(self):
        self.tag_on = "head"
        self.refused()
        self.calls = []
        self.main("--github")
        self.assertEqual(self.calls, ["check_pushed", "build", "github"])

    def test_existing_github_release_stops_before_the_upload(self):
        self.gh_release = True
        self.refused()

    def test_github_not_signed_in_stops_before_the_upload(self):
        self.gh_signed_in = False
        self.refused()

    def test_wrong_changelog_heading_stops_before_the_upload(self):
        self.write_changelog("## Keystance 1.0.0 (not yet released)")
        self.refused()

    def test_an_upload_already_done_stops_a_second_one(self):
        open(self.marker, "w").close()
        self.refused()

    def test_no_token_stops_before_anything(self):
        self.refused(token=False)
        self.assertNotIn("build", self.calls)


class Tracked(unittest.TestCase):
    """The zip's files must all be in the commit (this repository's own git)."""

    def test_committed_files_pass(self):
        release.check_tracked(["Keystance.toc", "Core.lua"])

    def test_a_listed_file_git_doesnt_have_stops_the_release(self):
        with self.assertRaises(SystemExit):
            release.check_tracked(["Keystance.toc", "NotCommitted.lua"])

    def test_build_checks_them_when_publishing(self):
        seen = []
        # The zip is never written here (dist/ holds the real releases).
        with mock.patch.object(release, "check_tracked", lambda files: seen.extend(files) or release.fail("x")), \
                mock.patch.object(release.zipfile, "ZipFile", mock.MagicMock()), \
                mock.patch.object(release.subprocess, "run",
                                  lambda *a, **k: SimpleNamespace(returncode=0, stdout="1 passed, 0 failed\n")):
            with self.assertRaises(SystemExit):
                release.build(publishing=True)
        self.assertIn("Core.lua", seen)
        self.assertIn("Keystance.toc", seen)


if __name__ == "__main__":
    unittest.main(verbosity=1)
