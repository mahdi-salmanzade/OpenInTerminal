# Open in Terminal

A native macOS app with a Finder extension that adds two folder actions to the right-click menu:

- **Open in Terminal** opens the selected folders using Terminal's normal window/tab behavior.
- **Open in New Terminal Window** requests a new Terminal window for each selected folder.

The menu uses the supplied Terminal icons, bundled as vector PDFs and fitted into square template
images so Finder preserves their proportions. The extension handles folder
selections, folder backgrounds, and sidebar folders when Finder supplies those contexts.
Files and mixed file/folder selections do not receive the actions.

Version **2.0.0** is a development build. The app and both Finder menu entries have been observed on
macOS 26.6.2; see [the validation record](TESTING.md) for the remaining Terminal and release checks.
A public binary release has not been published.

## Install and enable

1. Build the project, then open `dist/OpenInTerminal-2.0.0.pkg`. Installer places
   **Open in Terminal.app** in `/Applications` and requires administrator authentication.
   Alternatively, extract `dist/OpenInTerminal-2.0.0-app.zip` and move the app to `/Applications`.
2. Open **Open in Terminal** from Applications.
3. Click **Enable Finder Extension…** and enable **Open in Terminal** in the macOS extension settings.
4. Right-click a folder in Finder and choose either action. Finder controls their position in the menu.

The first **Open in New Terminal Window** request may ask permission for Open in Terminal to control
Terminal. Allow it for that action. Manage permission under **Privacy & Security → Automation** in
System Settings, or **Security & Privacy → Privacy → Automation** in System Preferences on Monterey.
The ordinary **Open in Terminal** action does not use Terminal automation.

The default build has an **ad-hoc signed app and an unsigned installer**. It is not a notarized public
release and downloaded copies may be blocked by Gatekeeper. Developer ID credentials are not included.
See [signing and Homebrew distribution](docs/HOMEBREW.md).

## Compatibility and limitations

The native build targets **macOS 12 Monterey or later**, on both Intel and Apple Silicon, without
Rosetta. This is the deployment floor supported by the current Xcode 27 build. Older systems and
future macOS versions are not covered by a claim of universal compatibility.

Finder Sync exposes contextual menus for registered folder locations; Apple describes it as a
mechanism intended for synchronization apps, not a general Finder customization API.
[Apple's Finder Sync guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)
documents the folder, background, and sidebar contexts. Menu placement is controlled by Finder.
Search results, virtual locations, cloud-managed folders, and interactions with other Finder
extensions need separate testing; the actions cannot be guaranteed in every Finder view.

The extension registers local and mounted volume roots without scanning their contents. The normal
action passes folder URLs directly to Terminal through `NSWorkspace`. The new-window action uses a
fixed AppleScript with base64-encoded paths supplied as data, so Terminal receives no raw filename
control characters. The app adds no login item; macOS manages the extension.

## Build and verify

Use macOS with **Xcode 27**, its command-line tools selected, and **Python 3.9+**:

```sh
make verify
```

This builds the app and extension, runs native request validation, nine command-safety regressions,
and the retained legacy shell tests, then inspects the generated installer. The command-safety
tests use an inert AppleScript harness; they do not open Terminal. Verification does not install
the app or enable the extension.
Outputs are:

- `dist/OpenInTerminal-2.0.0.pkg`
- `dist/OpenInTerminal-2.0.0-app.zip`
- `dist/SHA256SUMS`
- `build/Open in Terminal.app` for local inspection

The Objective-C code uses ARC. The checked-in `OpenInTerminal.xcodeproj` is sufficient to build;
XcodeGen is needed only after changing `project.yml`, to regenerate the project with `make project`.
Set the release version in `VERSION`. Manual installation and Finder checks are in [TESTING.md](TESTING.md).

## Legacy Services build

The optional **1.0.0** workflow remains available for older Macs:

```sh
make build-legacy
python3 scripts/verify_package_legacy.py
```

It targets OS X **10.6.8 onward**, but historical system compatibility remains unverified. It adds
**Services → Open in Terminal**, with no separate new-window action. Its version is in `LEGACY_VERSION`
and its installer, workflow ZIP, and checksums are written to `dist/legacy/`.
The legacy installer places `Open in Terminal.workflow` in `/Library/Services`; the ZIP can instead
be installed in `~/Library/Services` for one user. It is separate from the native app and is not
automatically removed when installing 2.0.0.

## Uninstall

Disable **Open in Terminal** in Finder Extensions, quit the app, and move
`/Applications/Open in Terminal.app` to the Trash. If Finder retains its menu entries, log out and back in.
The installer receipt `io.openinterminal.app.pkg` may remain; it has no runtime behavior.

To remove a legacy installation, remove only `Open in Terminal.workflow` from `/Library/Services`
or `~/Library/Services`, depending on how it was installed. Remove the old workflow when migrating
if you do not want both the native actions and the Services entry.
