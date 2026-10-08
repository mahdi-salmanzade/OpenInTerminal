# Open in Terminal

A macOS installer that adds **Open in Terminal** to Finder's folder Services menu.
Select one or more folders, right-click, and choose **Services → Open in Terminal**.
Some releases also expose the workflow in Quick Actions. macOS controls menu placement;
this project does not guarantee a top-level context-menu item or an action when clicking empty space.

## Install

1. Open `dist/OpenInTerminal-1.0.0.pkg` and follow Installer's instructions.
2. Right-click a folder in Finder and choose **Services → Open in Terminal**.
3. If missing, enable **Open in Terminal** under **Keyboard → Keyboard Shortcuts → Services**
   in System Settings or System Preferences. Log out and back in if the service has not appeared.

The installer adds `/Library/Services/Open in Terminal.workflow` for all users and requires
administrator authentication. It installs no background process, login item, or compiled helper.
Each selected directory is sent to Apple's Terminal; Terminal controls window/tab behavior.

The default package is an **unsigned development build**, not a signed, notarized public release.
Downloaded unsigned installers may be blocked by Gatekeeper. See the release instructions below.

For an installation just for your account, extract `dist/OpenInTerminal-1.0.0-workflow.zip`
and open the `.workflow` file to use macOS's service installer, or copy it to `~/Library/Services/`.
Install either the system-wide package or the per-user workflow to avoid duplicate menu entries.

## Compatibility

| System | Status |
| --- | --- |
| macOS 26.6.2, Apple Silicon | Build, package inspection, and Automator execution pass; Finder installation still needs a manual check |
| OS X 10.6.8 through other macOS releases | Compatibility target; not yet verified on those systems |
| Intel Macs, including 32-bit Snow Leopard systems | Installer declares i386 and x86_64; historical hardware testing required |
| Apple Silicon | Installer declares arm64; payload needs no Rosetta |
| OS X 10.0–10.5, PowerPC, Classic Mac OS | Not supported by this package |
| Future macOS versions | Must be retested; no guarantee |

“All macOS versions ever” cannot be honestly guaranteed with one integration. Automator Services
provide a broad supported mechanism. This installer starts at **10.6.8**, the final Snow Leopard release.
The payload is XML plus a Bash 3.2-compatible script using built-in `open`; Python is used only to build and test.
No AppleScript command is constructed from a filename. Files and executable scripts are rejected.

Apple documents [script-backed contextual services](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/MakeaSystem-WideService.html)
and [current Quick Actions](https://support.apple.com/guide/automator/use-quick-action-workflows-aut73234890a/mac).
Finder Sync starts at 10.10 and Apple says it is
[not a general-purpose Finder UI modification mechanism](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html).
The package uses legacy payload compression and declares the OS floor with
[Installer's distribution schema](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/Chapters/Distribution_XML_Ref.html).

Recent macOS releases also provide Apple's own Terminal commands from Finder's path bar;
see [Apple's Terminal guide](https://support.apple.com/guide/terminal/open-new-terminal-windows-and-tabs-trmlb20c7888/mac).
This project supplies a distributable, explicitly named folder service.

## Build and verify

Use a current macOS development machine with Python 3.9+ and Apple's `pkgbuild`, `productbuild`, and `ditto`.
There are no third-party dependencies.

```sh
make verify
```

Outputs are `dist/OpenInTerminal-1.0.0.pkg`, the portable workflow ZIP, and `dist/SHA256SUMS`.
Set the release version in `VERSION`. Builds use a temporary staging directory and never install the service.
Tests exercise literal filename handling, failures, and the actual packaged payload. See `TESTING.md`
for the manual Finder and older-system test matrix.

To run the packaged action without installing it (this opens Terminal):

```sh
python3 scripts/smoke_test.py --launch-terminal
```

The script creates a test directory with spaces, quotes, and Japanese characters under `build/smoke/`.
Check `pwd` in the resulting Terminal window against the path printed by the test.

## Sign a public release

A Developer ID Installer certificate and Apple notarization credentials are required.
This project does not include signing credentials.

```sh
python3 scripts/build.py --sign 'Developer ID Installer: YOUR NAME (TEAMID)'
xcrun notarytool submit dist/OpenInTerminal-1.0.0.pkg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/OpenInTerminal-1.0.0.pkg
pkgutil --check-signature dist/OpenInTerminal-1.0.0.pkg
spctl --assess --type install --verbose dist/OpenInTerminal-1.0.0.pkg
```

Recreate `SHA256SUMS` after stapling because stapling changes the package bytes.
Test downloaded packages on each claimed supported OS; modern signatures/notarization do not
establish compatibility with historical systems.

## Uninstall

In Finder, choose **Go → Go to Folder**, enter `/Library/Services/`, and move only
`Open in Terminal.workflow` to the Trash. Authenticate if asked. For a per-user installation,
use `~/Library/Services/` instead. Log out and back in if the menu entry remains cached.
The package receipt may remain; it has no runtime behavior.
