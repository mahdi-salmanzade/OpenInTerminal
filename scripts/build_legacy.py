#!/usr/bin/env python3
"""Build a text-only Finder Service and an Installer package on macOS."""

import argparse
import hashlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
NAME = "Open in Terminal"
BUNDLE_ID = "io.openinterminal.finder-service"
PACKAGE_ID = "io.openinterminal.finder-service.pkg"
MINIMUM_OS = "10.6.8"


def write_plist(destination, value):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output:
        plistlib.dump(value, output, fmt=plistlib.FMT_XML, sort_keys=True)


def create_workflow(destination, version):
    script = (ROOT / "src/open-in-terminal.sh").read_text(encoding="utf-8")
    write_plist(destination / "Contents/Info.plist", {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": NAME,
        "CFBundleVersion": version,
        "CFBundleShortVersionString": version,
        "NSServices": [{
            "NSMenuItem": {"default": NAME},
            "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
            "NSSendFileTypes": ["public.folder"],
        }],
    })
    action = {
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {
            "CheckedForUserDefaultShell": True,
            "COMMAND_STRING": script,
            "inputMethod": 1,
            "shell": "/bin/bash",
            "source": "",
        },
        "AMAccepts": {"Container": "List", "Optional": True,
                      "Types": ["com.apple.cocoa.string"]},
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3",
        "AMParameterProperties": {key: {} for key in
                                  ("COMMAND_STRING", "inputMethod", "shell", "source")},
        "AMRequiredResources": [],
        "Application": ["Automator"],
        "BundleIdentifier": "com.apple.RunShellScript",
        "CFBundleVersion": "2.0.3",
        "CanShowSelectedItemsWhenRun": False,
        "CanShowWhenRun": True,
        "Category": ["AMCategoryUtilities"],
        "Class Name": "RunShellScriptAction",
        "InputUUID": "996BAF0E-8B03-42CF-A03E-D57B01854964",
        "OutputUUID": "5B105333-32AB-414F-8D91-972E49791E7C",
        "UUID": "5B6D2F40-24BB-4F64-810F-761BFA9B098C",
        "ShowWhenRun": False,
        "isViewVisible": True,
    }
    write_plist(destination / "Contents/Resources/document.wflow", {
        "AMDocumentVersion": "2",
        "actions": [{"action": action, "isViewVisible": True}],
        "connectors": {},
        "workflowMetaData": {
            "serviceApplicationBundleID": "com.apple.finder",
            "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
            "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject.folder",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": 0,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    })


def distribution(version):
    return '''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Open in Terminal</title>
  <options customize="never" require-scripts="false" hostArchitectures="i386,x86_64,arm64"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <volume-check><allowed-os-versions><os-version min="%s"/></allowed-os-versions></volume-check>
  <welcome file="welcome.txt" mime-type="text/plain"/>
  <conclusion file="conclusion.txt" mime-type="text/plain"/>
  <choices-outline><line choice="service"/></choices-outline>
  <choice id="service" title="Open in Terminal" description="Finder folder service" visible="false">
    <pkg-ref id="%s"/>
  </choice>
  <pkg-ref id="%s" version="%s" onConclusion="None">service.pkg</pkg-ref>
</installer-gui-script>
''' % (MINIMUM_OS, PACKAGE_ID, PACKAGE_ID, escape(version))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sign", help="Developer ID Installer identity for the final package")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Package creation requires macOS and Apple's pkgbuild/productbuild tools.")
    version = (ROOT / "LEGACY_VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        parser.error("VERSION must contain a numeric major.minor.patch version.")
    for command in ("pkgbuild", "productbuild", "ditto"):
        if not shutil.which(command):
            parser.error("Missing macOS tool: " + command)
    output = ROOT / "dist/legacy"
    output.mkdir(parents=True, exist_ok=True)
    package = output / ("OpenInTerminal-%s.pkg" % version)
    archive = output / ("OpenInTerminal-%s-workflow.zip" % version)
    with tempfile.TemporaryDirectory(prefix="openinterminal-build-") as temporary:
        stage = Path(temporary)
        payload = stage / "payload"
        workflow = payload / "Library/Services" / (NAME + ".workflow")
        create_workflow(workflow, version)
        components = stage / "components.plist"
        write_plist(components, [{
            "RootRelativeBundlePath": "Library/Services/" + NAME + ".workflow",
            "BundleIsRelocatable": False,
            "BundleIsVersionChecked": True,
            "BundleHasStrictIdentifier": True,
            "BundleOverwriteAction": "upgrade",
        }])
        subprocess.run([
            "/usr/bin/pkgbuild", "--root", str(payload),
            "--identifier", PACKAGE_ID, "--version", version,
            "--install-location", "/", "--ownership", "recommended",
            "--component-plist", str(components), "--compression", "legacy",
            str(stage / "service.pkg"),
        ], check=True)
        definition = stage / "Distribution.xml"
        definition.write_text(distribution(version), encoding="utf-8")
        command = ["/usr/bin/productbuild", "--distribution", str(definition),
                   "--package-path", str(stage), "--resources", str(ROOT / "packaging/resources")]
        if args.sign:
            command.extend(["--sign", args.sign])
        command.append(str(stage / package.name))
        subprocess.run(command, check=True)
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc",
                        str(workflow), str(stage / archive.name)], check=True)
        shutil.copyfile(stage / package.name, package)
        shutil.copyfile(stage / archive.name, archive)
    (output / "SHA256SUMS").write_text("".join(
        hashlib.sha256(artifact.read_bytes()).hexdigest() + "  " + artifact.name + "\n"
        for artifact in (package, archive)), encoding="utf-8")
    print("Built: " + str(package))
    print("Workflow: " + str(archive))
    print("Signing: " + (args.sign or "unsigned development build"))


if __name__ == "__main__":
    main()
