#!/usr/bin/env python3
"""Build a universal Finder extension app and macOS installer."""

import argparse
import hashlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAME = "Open in Terminal"
BUNDLE_ID = "io.openinterminal.app"
EXTENSION_ID = BUNDLE_ID + ".FinderExtension"
PACKAGE_ID = BUNDLE_ID + ".pkg"
MINIMUM_OS = "12.0"


def write_plist(destination, value):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output:
        plistlib.dump(value, output, fmt=plistlib.FMT_XML, sort_keys=True)


def distribution(version):
    return '''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Open in Terminal</title>
  <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <volume-check><allowed-os-versions><os-version min="%s"/></allowed-os-versions></volume-check>
  <welcome file="welcome.txt" mime-type="text/plain"/>
  <conclusion file="conclusion.txt" mime-type="text/plain"/>
  <choices-outline><line choice="application"/></choices-outline>
  <choice id="application" title="Open in Terminal" description="Finder menu extension" visible="false">
    <pkg-ref id="%s"/>
  </choice>
  <pkg-ref id="%s" version="%s" onConclusion="None">application.pkg</pkg-ref>
</installer-gui-script>
''' % (MINIMUM_OS, PACKAGE_ID, PACKAGE_ID, version)


def sign_bundle(bundle, entitlements, identity):
    subprocess.run([
        "/usr/bin/codesign", "--force", "--sign", identity,
        "--options", "runtime", "--timestamp=none" if identity == "-" else "--timestamp",
        "--entitlements", str(entitlements), str(bundle),
    ], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sign-app", default="-", help="Developer ID Application identity (default: ad hoc)")
    parser.add_argument("--sign-installer", help="Developer ID Installer identity")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Building requires macOS and Xcode.")
    if args.sign_installer and args.sign_app == "-":
        parser.error("Use --sign-app with --sign-installer for a distributable signed build.")
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        parser.error("VERSION must be numeric major.minor.patch.")
    for command in ("xcodebuild", "pkgbuild", "productbuild", "ditto", "codesign"):
        if not shutil.which(command):
            parser.error("Missing macOS developer tool: " + command)
    if not (ROOT / "OpenInTerminal.xcodeproj").exists():
        parser.error("Missing Xcode project. Run xcodegen generate using project.yml.")

    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    log = build / "xcodebuild.log"
    print("Building Intel and Apple Silicon app + Finder extension…", flush=True)
    with log.open("w") as stream:
        result = subprocess.run([
            "xcodebuild", "-project", str(ROOT / "OpenInTerminal.xcodeproj"),
            "-scheme", "OpenInTerminal", "-configuration", "Release", "-destination", "generic/platform=macOS",
            "-derivedDataPath", str(build / "xcode"), "CODE_SIGNING_ALLOWED=NO",
            "MARKETING_VERSION=" + version, "CURRENT_PROJECT_VERSION=" + version,
            "CLANG_MODULE_CACHE_PATH=" + str(build / "ModuleCache"), "build",
        ], stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text().splitlines()[-90:]), file=sys.stderr)
        raise SystemExit("Build failed; full log: " + str(log))

    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    package = output / ("OpenInTerminal-%s.pkg" % version)
    archive = output / ("OpenInTerminal-%s-app.zip" % version)
    with tempfile.TemporaryDirectory(prefix="openinterminal-native-") as temporary:
        stage = Path(temporary)
        payload = stage / "payload"
        app = payload / "Applications" / (NAME + ".app")
        subprocess.run(["/usr/bin/ditto", str(build / "xcode/Build/Products/Release" / (NAME + ".app")),
                        str(app)], check=True)
        extension = app / "Contents/PlugIns/FinderExtension.appex"
        sign_bundle(extension, ROOT / "native/FinderExtension/Extension.entitlements", args.sign_app)
        sign_bundle(app, ROOT / "native/App/App.entitlements", args.sign_app)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        component_plist = stage / "components.plist"
        write_plist(component_plist, [{
            "RootRelativeBundlePath": "Applications/" + NAME + ".app",
            "BundleIsRelocatable": False,
            "BundleIsVersionChecked": True,
            "BundleHasStrictIdentifier": True,
            "BundleOverwriteAction": "upgrade",
        }])
        subprocess.run([
            "/usr/bin/pkgbuild", "--root", str(payload), "--identifier", PACKAGE_ID,
            "--version", version, "--install-location", "/", "--ownership", "recommended",
            "--component-plist", str(component_plist), "--compression", "legacy",
            str(stage / "application.pkg"),
        ], check=True)
        definition = stage / "Distribution.xml"
        definition.write_text(distribution(version), encoding="utf-8")
        command = ["/usr/bin/productbuild", "--distribution", str(definition),
                   "--package-path", str(stage), "--resources", str(ROOT / "packaging/native-resources")]
        if args.sign_installer:
            command.extend(["--sign", args.sign_installer])
        subprocess.run(command + [str(stage / package.name)], check=True)
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc",
                        str(app), str(stage / archive.name)], check=True)
        shutil.copyfile(stage / package.name, package)
        shutil.copyfile(stage / archive.name, archive)
        subprocess.run(["/usr/bin/ditto", str(app), str(build / (NAME + ".app"))], check=True)
    (output / "SHA256SUMS").write_text("".join(
        hashlib.sha256(artifact.read_bytes()).hexdigest() + "  " + artifact.name + "\n"
        for artifact in (package, archive)), encoding="utf-8")
    print("Built: " + str(package))
    print("Application archive: " + str(archive))
    print("Signing: " + (args.sign_installer or "ad-hoc app; unsigned development installer"))


if __name__ == "__main__":
    main()
