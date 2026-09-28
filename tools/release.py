"""Builds the Keystance release zip and, with --upload, publishes it.

    python tools/release.py                         build dist/Keystance-<version>.zip
    python tools/release.py --upload CHANGELOG.md   build, upload to CurseForge as a
                                                    RELEASE_TYPE file, then tag v<version> and make a
                                                    GitHub release with the same zip
    python tools/release.py --github CHANGELOG.md   build, then only the GitHub part

Publishing is the owner's decision, and needs everything committed and pushed, so the tag
matches the zip. Uploading also needs PROJECT_ID, which the owner gets by creating the
project on CurseForge.

Runs the tests first with `luajit` (or the LUAJIT environment variable).

The zip holds one Keystance/ folder with only the files the game loads (the .toc files and
the .lua files they list) plus LICENSE and the files in EXTRA. Anything else stops the build.
The CurseForge token comes from the CURSE_API_KEY environment variable (or the Windows user
environment) and is never printed.
"""
import json
import os
import subprocess
import sys
import uuid
import zipfile
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOCS = ["Keystance.toc", "Keystance_Camelot.toc"]
EXTRA = ["LICENSE", "Bindings.xml",  # the game loads it by name: profile keybinds
         "media/icon.tga", "media/minimap.tga", "media/logo.tga",  # the logo: addon list, minimap, Options
         "media/controller.tga", "media/circle.tga"]  # the Controller layout's drawing and round buttons
ALLOWED = (".toc", ".lua")

PROJECT_ID = None  # the CurseForge project, once the owner has created it
API = "https://wow.curseforge.com/api"
GAME_VERSIONS = [17053]  # WoW Forever 1.60.1 (re-check GET /api/game/versions for newer clients)
RELEASE_TYPE = "release"  # "release", "beta" or "alpha"


def fail(msg):
    sys.exit("release: " + msg)


def run(*args):
    r = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        fail("%s failed: %s" % (" ".join(args[:3]), (r.stderr or r.stdout).strip()[:1000]))
    return r.stdout.strip()


def check_pushed():
    if run("git", "status", "--porcelain", "--untracked-files=no"):
        fail("commit your changes first; the release must match a pushed commit")
    run("git", "fetch", "-q", "origin")
    if run("git", "rev-parse", "HEAD") != run("git", "rev-parse", "@{u}"):
        fail("push first; HEAD isn't on the remote branch")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def toc_files(toc):
    files = []
    for line in read(toc).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def version():
    for line in read(TOCS[0]).splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    fail("no ## Version in " + TOCS[0])


def build():
    if read(TOCS[0]) != read(TOCS[1]):
        fail("the two .toc files differ")
    tests = subprocess.run([os.environ.get("LUAJIT", "luajit"), "tests/run.lua"], cwd=ROOT, capture_output=True, text=True)
    last = tests.stdout.strip().splitlines()[-1:] or [""]
    if tests.returncode != 0 or not last[0].endswith(" 0 failed"):
        fail("tests failed:\n" + tests.stdout[-2000:])

    files = TOCS + toc_files(TOCS[0]) + EXTRA
    for f in files:
        if f not in EXTRA and not f.endswith(ALLOWED):
            fail("refusing to ship " + f)
        if not os.path.isfile(os.path.join(ROOT, f)):
            fail("missing " + f)

    ver = version()
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    path = os.path.join(ROOT, "dist", "Keystance-%s.zip" % ver)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(os.path.join(ROOT, f), "Keystance/" + f)
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    print("built %s (%d files):" % (os.path.relpath(path, ROOT), len(names)))
    for n in names:
        print("  " + n)
    return path, ver


def token():
    key = os.environ.get("CURSE_API_KEY")
    if not key and sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
                key = winreg.QueryValueEx(k, "CURSE_API_KEY")[0]
        except OSError:
            key = None
    if not key:
        fail("CURSE_API_KEY is not set")
    return key


def upload(path, ver, changelog_path):
    if not PROJECT_ID:
        fail("no CurseForge project yet: set PROJECT_ID once the owner has created it")
    changelog = open(changelog_path, encoding="utf-8").read()
    metadata = {
        "changelog": changelog,
        "changelogType": "markdown",
        "displayName": "Keystance " + ver,
        "gameVersions": GAME_VERSIONS,
        "releaseType": RELEASE_TYPE,
    }
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        data = f.read()
    body = b"".join([
        ("--%s\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
         "Content-Type: application/json\r\n\r\n" % boundary).encode(),
        json.dumps(metadata).encode(), b"\r\n",
        ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n"
         "Content-Type: application/zip\r\n\r\n" % (boundary, os.path.basename(path))).encode(),
        data, b"\r\n",
        ("--%s--\r\n" % boundary).encode(),
    ])
    req = urllib.request.Request(
        "%s/projects/%d/upload-file" % (API, PROJECT_ID), data=body, method="POST",
        headers={"X-Api-Token": token(), "Content-Type": "multipart/form-data; boundary=" + boundary})
    try:
        with urllib.request.urlopen(req) as r:
            print("uploaded: HTTP %d %s" % (r.status, r.read().decode()))
    except urllib.error.HTTPError as e:
        fail("upload failed: HTTP %d %s" % (e.code, e.read().decode()[:1000]))


def github_release(path, ver, changelog_path):
    tag = "v" + ver
    head = run("git", "rev-parse", "HEAD")
    if run("git", "tag", "--list", tag):
        if run("git", "rev-parse", tag + "^{commit}") != head:
            fail("tag %s already exists on a different commit" % tag)
    else:
        run("git", "tag", "-a", tag, "-m", "Keystance %s" % ver)
    run("git", "push", "-q", "origin", tag)
    exists = subprocess.run(["gh", "release", "view", tag], cwd=ROOT, capture_output=True).returncode == 0
    if exists:
        fail("GitHub release %s already exists; not replacing it" % tag)
    args = ["gh", "release", "create", tag, path, "--title", "Keystance " + ver,
            "--notes-file", changelog_path, "--verify-tag"]
    if RELEASE_TYPE != "release":
        args.append("--prerelease")
    print("github release: " + run(*args))


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) >= 2 else None
    if mode in ("--upload", "--github"):
        if len(sys.argv) < 3:
            fail(mode + " needs a changelog file")
        check_pushed()
    path, ver = build()
    if mode == "--upload":
        upload(path, ver, sys.argv[2])
    if mode in ("--upload", "--github"):
        github_release(path, ver, sys.argv[2])
