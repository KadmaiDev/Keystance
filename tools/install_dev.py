"""Copies the working files into Interface\\AddOns\\KeystanceDev, a second copy of the
addon for testing in game next to the installed release.

    python tools/install_dev.py "<WoW>\\_classic_beta_"

The .toc files are renamed to match the folder and titled "Keystance (dev)". WoW names
saved data after the folder, so the dev copy keeps its own KeystanceDev.lua. Enable only
one of the two copies at a time: both use the KeystanceDB global (a second copy stays off
and says so).
Close the game first if you added a file or changed a .toc; otherwise /reload is enough.
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOCS = ["Keystance.toc", "Keystance_Camelot.toc"]
EXTRA = ["LICENSE"]


def toc_files(text):
    return [line.strip().replace("\\", "/") for line in text.splitlines()
            if line.strip() and not line.startswith("#")]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    addons = os.path.join(sys.argv[1], "Interface", "AddOns")
    if not os.path.isdir(addons):
        sys.exit("install_dev: no Interface/AddOns folder in " + sys.argv[1])
    dev = os.path.join(addons, "KeystanceDev")
    if os.path.islink(dev) or (os.path.isdir(dev) and os.path.realpath(dev) != os.path.abspath(dev)):
        sys.exit("install_dev: " + dev + " is a link; remove it first")
    os.makedirs(dev, exist_ok=True)

    with open(os.path.join(ROOT, TOCS[0]), encoding="utf-8") as f:
        toc = f.read()
    for name in TOCS:
        target = os.path.join(dev, name.replace("Keystance", "KeystanceDev", 1))
        with open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write(toc.replace("## Title: Keystance", "## Title: Keystance (dev)", 1)
                    .replace("AddOns\\Keystance\\", "AddOns\\KeystanceDev\\"))
    files = toc_files(toc) + EXTRA
    for name in files:
        target = os.path.join(dev, name)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, name), target)
    print("copied %d files to %s" % (len(files) + len(TOCS), dev))


if __name__ == "__main__":
    main()
