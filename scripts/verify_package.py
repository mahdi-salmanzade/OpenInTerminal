#!/usr/bin/env python3
"""Inspect the actual native app installer without installing it."""
import hashlib
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from build import BUNDLE_ID, EXTENSION_ID, MINIMUM_OS, NAME, PACKAGE_ID, ROOT


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_plist(filename):
    with filename.open("rb") as stream:
        return plistlib.load(stream)


def main():
    version = (ROOT / "VERSION").read_text().strip()
    package = ROOT / "dist" / ("OpenInTerminal-%s.pkg" % version)
    archive = ROOT / "dist" / ("OpenInTerminal-%s-app.zip" % version)
    with tempfile.TemporaryDirectory(prefix="openinterminal-verify-") as temporary:
        expanded = Path(temporary) / "expanded"
        subprocess.run(["/usr/sbin/pkgutil", "--expand-full", str(package), str(expanded)], check=True)
        distribution = ET.parse(expanded / "Distribution").getroot()
        require(distribution.find("volume-check/allowed-os-versions/os-version").get("min") == MINIMUM_OS,
                "Incorrect minimum macOS version")
        require(set(distribution.find("options").get("hostArchitectures").split(",")) ==
                {"x86_64", "arm64"}, "Incorrect installer CPU support")
        component = expanded / "application.pkg"
        info = ET.parse(component / "PackageInfo").getroot()
        require(info.get("identifier") == PACKAGE_ID and info.get("version") == version,
                "Incorrect package identity or version")
        require(info.get("install-location") == "/", "Incorrect installation root")
        require(not (component / "Scripts").exists(), "Unexpected installer scripts")
        payload = component / "Payload"
        app = payload / "Applications" / (NAME + ".app")
        extension = app / "Contents/PlugIns/FinderExtension.appex"
        require(all(p.is_relative_to(app) for p in payload.rglob("*") if p.is_file()),
                "The package contains files outside its application")
        metadata = read_plist(app / "Contents/Info.plist")
        require(metadata["CFBundleIdentifier"] == BUNDLE_ID, "Incorrect app identity")
        require(metadata["LSMinimumSystemVersion"] == MINIMUM_OS, "Incorrect app deployment target")
        require(metadata["CFBundleShortVersionString"] == version and metadata["CFBundleVersion"] == version,
                "App version does not match package version")
        require("NSServices" not in metadata, "Native app must not register a Services menu item")
        require(metadata["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == ["openinterminal-app"],
                "Incorrect app handoff URL scheme")
        require(metadata.get("NSAppleEventsUsageDescription"), "Missing automation permission explanation")
        extension_info = read_plist(extension / "Contents/Info.plist")
        require(extension_info["CFBundleIdentifier"] == EXTENSION_ID, "Incorrect extension identity")
        require(extension_info["CFBundleVersion"] == version, "Incorrect extension version")
        require(extension_info["NSExtension"] == {
            "NSExtensionPointIdentifier": "com.apple.FinderSync", "NSExtensionPrincipalClass": "OITFinderSync"
        }, "Incorrect Finder extension registration")
        for bundle, executable in ((app, NAME), (extension, "FinderExtension")):
            arches = subprocess.check_output(["/usr/bin/lipo", "-archs", str(bundle / "Contents/MacOS" / executable)],
                                             text=True).split()
            require(set(arches) == {"arm64", "x86_64"}, "Binary is not universal: " + executable)
            for icon in ("apple.terminal.pdf", "apple.terminal.on.rectangle.pdf"):
                require((bundle / "Contents/Resources" / icon).read_bytes() ==
                        (ROOT / "native/Resources" / icon).read_bytes(), "Missing or changed icon: " + icon)
            subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(bundle)], check=True)
        script = app / "Contents/Resources/OpenNewTerminalWindow.scpt"
        require(script.is_file(), "Missing compiled Terminal window helper")
        script_source = subprocess.check_output(["/usr/bin/osadecompile", str(script)], text=True)
        require("on openFolders" in script_source and "do script" in script_source,
                "Compiled Terminal window helper could not be read")
        entitlements = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(extension)],
                                      check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        require(plistlib.loads(entitlements.stdout).get("com.apple.security.app-sandbox") is True,
                "Finder extension is not sandboxed")
        with zipfile.ZipFile(archive) as portable:
            for file in app.rglob("*"):
                if file.is_file():
                    relative = file.relative_to(app).as_posix()
                    require(portable.read(NAME + ".app/" + relative) == file.read_bytes(),
                            "ZIP and installer contents differ: " + relative)
        choices = subprocess.run(
            ["/usr/sbin/installer", "-showChoicesXML", "-pkg", str(package), "-target", "/"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        require(choices.returncode == 0, "Installer could not evaluate the package:\n" + choices.stdout)
        choices_xml = ET.fromstring(choices.stdout)
        require(any(node.text == "application" for node in choices_xml.iter("string")),
                "Installer did not expose the application choice")
    for line in (ROOT / "dist/SHA256SUMS").read_text().splitlines():
        checksum, filename = line.split("  ", 1)
        require(hashlib.sha256((ROOT / "dist" / filename).read_bytes()).hexdigest() == checksum,
                "Checksum mismatch: " + filename)
    print("Verified native installer, universal binaries, versions, Finder registration, sandbox, icons, signatures and checksums.")
    print("No installation or Finder extension activation was performed.")


if __name__ == "__main__":
    main()
