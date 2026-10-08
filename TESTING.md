# Validation record

Development host: **macOS 26.6.2 (25G83), Apple Silicon**, with Xcode 27.

## Native 2.0.0

- **Passed:** 33 native request checks. They cover both action modes, literal folder names with
  spaces, quotes, Unicode, newlines, and shell metacharacters; duplicate folders; invalid requests;
  non-folder inputs; size limits; and folders deleted before execution. These checks do not launch Terminal.
- **Passed:** universal Intel/Apple Silicon app and extension build, with a macOS 12 deployment floor.
  Package inspection verifies versions, payload scope, icon resources, compiled AppleScript, signatures,
  sandbox entitlement, URL registration, architecture slices, installer choices, ZIP contents, and checksums.
- **Passed:** nine command-safety regressions exercise the actual AppleScript command construction
  through an inert harness. Generated Terminal commands contain only printable ASCII. A recording
  login-shell fixture confirms correct directories with Ctrl-U, Ctrl-C, carriage return, line feed,
  trailing newlines, Escape, tabs, quotes, and Unicode. No Terminal window is opened by these tests.
- **Observed:** the development setup app opens, the extension registers and reports enabled,
  and Finder shows both actions directly in a folder's main context menu on macOS 26.6.2.
  Both user-supplied icons appeared. The initial stretched rendering was corrected by placing
  aspect-fitted artwork in square 18-point images with 36-pixel bitmap representations; the updated
  build was reloaded, but a final screenshot was not captured while the user's Finder was in use.
- **Pending:** end-to-end Terminal directory/window behavior, Automation consent, installer execution,
  upgrade, removal, folder-background/sidebar behavior, and files/mixed selections in Finder.
- **Pending:** Intel and other macOS releases. Deployment settings alone do not demonstrate compatibility.
- **Not release-signed:** the default app uses ad-hoc signing, the installer is unsigned, and neither
  has completed notarization. No usable Developer ID signing identity has been confirmed in this workspace.

`make verify` builds the native distribution, runs `tests/test_action.py` for the legacy shell action
and `scripts/test_native.py` for native request handling, plus `scripts/test_command_safety.py`,
then runs `scripts/verify_package.py`.
Package inspection is separate from installation and Finder testing.

## Manual native release checks

Run these on a clean user account or test Mac, then record the OS, architecture, artifact checksum,
signing identity, and result. Test macOS 12, 13, 14, 15, 26, and the latest available release on the
architectures each supports before expanding compatibility claims.

1. Install the `.pkg`; confirm `/Applications/Open in Terminal.app` and its embedded Finder extension.
   Open the setup app, enable the extension, and verify that the setup status reflects the change.
2. Right-click a folder and confirm both labels and their icons. Repeat on a folder background and
   sidebar folder. Record actual menu placement; no exact position is promised.
3. Test one folder and several folders. Confirm ordinary files and mixed file/folder selections do
   not expose the folder actions. Change Finder's selection while a context menu is open and confirm
   the action uses that menu's original folders.
4. Use **Open in Terminal** with Terminal initially closed and already running. Run `pwd` in each
   resulting session and compare it with the selected folder. Check Terminal's normal window/tab behavior.
5. Use **Open in New Terminal Window** with existing Terminal windows. Grant Automation permission
   and verify a new window per folder, with the correct `pwd`. Repeat after denying permission:
   the app should show a useful error and the ordinary action should remain usable.
6. Test spaces, quotes, Unicode, newlines, leading dashes, and shell metacharacters in folder names.
   Confirm that names remain literal and no injected command runs.
7. Test local, external, and mounted network folders; mount and unmount a volume while Finder is open.
   Try an inaccessible or deleted folder and confirm that failure is reported.
8. Check search results, Recents, cloud-managed folders, and other virtual locations. Record unsupported
   contexts. Repeat with other Finder extensions enabled and disabled to identify coexistence problems.
9. Log out and back in. Test another account, enablement persistence, app relaunch, and repeated actions.
10. Upgrade in place, confirm the new version and absence of duplicate native entries, then disable
    and uninstall. Check that the menu entries disappear. Test migration from the separate legacy workflow.
11. Repeat installation and first launch after a real download of the signed/notarized artifacts.
    Test both `.pkg` and app ZIP, and the proposed Homebrew cask's install, upgrade, and uninstall.

## Legacy 1.0.0 record

The earlier Services implementation was built and inspected on this host. Nine shell-action tests
passed using a mocked `open` command. Package verification checked its workflow metadata, script,
OS/CPU declarations, portable archive, and checksums. The packaged workflow also completed a run
through `/usr/bin/automator` with a folder containing spaces, quotes, and Japanese characters.

That run did not install or register the service. Terminal's resulting `pwd`, Finder menu visibility,
and historical system compatibility were not independently verified. These results do not validate
the native 2.0.0 app.

To reproduce the legacy checks:

```sh
make build-legacy
python3 scripts/verify_package_legacy.py
python3 -m unittest discover -s tests -v
```

The optional `python3 scripts/smoke_test_legacy.py --launch-terminal` opens Terminal through the
workflow without registering it. Verify the printed path with `pwd`. Legacy artifacts are under
`dist/legacy/` and use `LEGACY_VERSION`; test historical Macs separately before claiming support.
