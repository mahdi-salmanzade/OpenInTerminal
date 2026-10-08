#!/usr/bin/env python3
"""Inspect the actual installer payload without installing it."""

import hashlib
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from build import BUNDLE_ID, MINIMUM_OS, NAME, PACKAGE_ID, ROOT


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    version = (ROOT / "VERSION").read_text().strip()
    package = ROOT / "dist" / ("OpenInTerminal-%s.pkg" % version)
    archive = ROOT / "dist" / ("OpenInTerminal-%s-workflow.zip" % version)
    source = (ROOT / "src/open-in-terminal.sh").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="openinterminal-verify-") as temporary:
        expanded = Path(temporary) / "expanded"
        subprocess.run(["/usr/sbin/pkgutil", "--expand-full", str(package), str(expanded)], check=True)
        distribution = ET.parse(expanded / "Distribution").getroot()
        require(distribution.find("volume-check/allowed-os-versions/os-version").get("min") == MINIMUM_OS,
                "Incorrect minimum macOS version")
        require(set(distribution.find("options").get("hostArchitectures").split(",")) ==
                {"i386", "x86_64", "arm64"}, "Installer architecture support changed")
        component = expanded / "service.pkg"
        info = ET.parse(component / "PackageInfo").getroot()
        require(info.get("identifier") == PACKAGE_ID and info.get("version") == version,
                "Incorrect package identity or version")
        require(info.get("install-location") == "/", "Incorrect install root")
        require(not (component / "Scripts").exists(), "Unexpected installer scripts")
        payload = component / "Payload"
        files = {p.relative_to(payload).as_posix() for p in payload.rglob("*") if p.is_file()}
        prefix = "Library/Services/" + NAME + ".workflow/Contents/"
        require(files == {prefix + "Info.plist", prefix + "Resources/document.wflow"},
                "Unexpected files in installer payload: " + repr(files))
        workflow = payload / "Library/Services" / (NAME + ".workflow")
        with (workflow / "Contents/Info.plist").open("rb") as stream:
            metadata = plistlib.load(stream)
        require(metadata["CFBundleIdentifier"] == BUNDLE_ID, "Incorrect service identity")
        service = metadata["NSServices"][0]
        require(service["NSMenuItem"]["default"] == NAME, "Incorrect menu title")
        require(service["NSSendFileTypes"] == ["public.folder"], "Service must only accept folders")
        require(service["NSRequiredContext"]["NSApplicationIdentifier"] == "com.apple.finder",
                "Service must be scoped to Finder")
        with (workflow / "Contents/Resources/document.wflow").open("rb") as stream:
            document = plistlib.load(stream)
        parameters = document["actions"][0]["action"]["ActionParameters"]
        require(parameters["COMMAND_STRING"] == source, "Packaged script differs from source")
        require(parameters["inputMethod"] == 1, "Folder inputs must be passed as arguments")
        require(parameters["shell"] == "/bin/bash", "Unexpected shell dependency")
        with zipfile.ZipFile(archive) as portable:
            for suffix in ("Contents/Info.plist", "Contents/Resources/document.wflow"):
                require(portable.read(NAME + ".workflow/" + suffix) == (workflow / suffix).read_bytes(),
                        "Portable workflow differs from the installer")
        choices = subprocess.run(
            ["/usr/sbin/installer", "-showChoicesXML", "-pkg", str(package), "-target", "/"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        require(choices.returncode == 0, "Installer could not evaluate the package:\n" + choices.stdout)
        choices_xml = ET.fromstring(choices.stdout)
        require(any(node.text == "service" for node in choices_xml.iter("string")),
                "Installer did not expose the service choice:\n" + choices.stdout)
    for line in (ROOT / "dist/SHA256SUMS").read_text().splitlines():
        checksum, filename = line.split("  ", 1)
        require(hashlib.sha256((ROOT / "dist" / filename).read_bytes()).hexdigest() == checksum,
                "Checksum mismatch: " + filename)
    print("Verified installer choices, OS/CPU requirements, exact payload, workflow metadata, script and checksums.")
    print("No installation or Finder registration was performed.")


if __name__ == "__main__":
    main()
