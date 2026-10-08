# Validation record

Build host: macOS 26.6.2 (25G83), Apple Silicon.

- Nine shell-action tests pass: literal names (including spaces, quotes, Unicode, newlines,
  command substitution text, and leading dashes), multiple inputs, invalid inputs, symlinks,
  and launch failures. The `open` command is mocked; these do not claim actual Terminal execution.
- The package is built with Apple's `pkgbuild` and `productbuild`.
- `scripts/verify_package.py` expands the actual package and verifies its payload,
  Finder-only folder filter, embedded action, installer choices, OS floor, CPU declarations,
  portable workflow equivalence, and SHA-256 checksums.
- The development package is unsigned and has not been notarized.
- The unmodified packaged workflow was run using `/usr/bin/automator` with a folder containing
  spaces, single quotes, and Japanese characters. Automator reported successful completion
  and the native `open` command returned success. The test did not install or register the service.
- Terminal UI inspection was blocked by the computer-use tool's app-access policy, so the
  resulting shell's `pwd` was not independently checked. Finder menu visibility and actual
  installation/upgrade/uninstallation have not been verified in this session.

## Manual release checks

On each claimed supported OS, test a clean installation, upgrade, and uninstall:

1. Install the package. Confirm that Finder exposes **Services → Open in Terminal** for folders.
2. Confirm that ordinary files do not expose the action and that the menu is restricted to Finder.
3. Open a folder on the startup disk. Run `pwd` in the resulting Terminal session and compare it
   with the selected folder. Repeat with multiple folders and a mounted external/network volume.
4. Repeat with spaces, quotes, non-ASCII characters, and shell metacharacters in folder names.
5. Test with Terminal already running and with Terminal initially closed.
6. Log out/back in and confirm the service is still available. Verify a second user account.
7. Reinstall a newer build and confirm that the service is updated in place without duplicate entries.
8. Uninstall the workflow and confirm its menu entry disappears after Services refreshes.
9. For public distribution, test the signed/notarized package after an actual browser download.

Suggested historical matrix: 10.6.8 (32-bit and 64-bit Intel), 10.11, 10.13, 10.15,
11 (Intel and Apple Silicon), 12, 13, 14, 15, and 26. Add newer releases before claiming support.
These environments are not available in this workspace and have not been tested.
