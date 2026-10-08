# Signing, releases, and Homebrew

These are publishing instructions for native **2.0.0**, not an announcement of an available release.
No release asset or installable cask has been published yet. The intended upstream repository is
`mahdi-salmanzade/OpenInTerminal`.

Use a cask named **`openinterminal-finder`**. Homebrew's existing
[`openinterminal`](https://formulae.brew.sh/cask/openinterminal) is a different project from Ji4n1ng;
using that token would confuse installations.

## 1. Sign and validate the release

The default build ad-hoc signs the app and extension, and produces an unsigned `.pkg`.
A public release needs a **Developer ID Application** certificate for the app/extension and a
**Developer ID Installer** certificate for the installer. Credentials are not part of this repository;
no usable signing identity has been confirmed in the development workspace.

After the runtime checks in [TESTING.md](../TESTING.md), build with your own certificate names:

```sh
python3 scripts/build.py \
  --sign-app 'Developer ID Application: YOUR NAME (TEAMID)' \
  --sign-installer 'Developer ID Installer: YOUR NAME (TEAMID)'
python3 scripts/verify_package.py
```

The builder signs the embedded extension before the containing app, with the required entitlements,
hardened runtime, and timestamps. Configure a notarytool Keychain profile using your Apple Developer
credentials, then submit and staple the installer:

```sh
xcrun notarytool submit dist/OpenInTerminal-2.0.0.pkg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/OpenInTerminal-2.0.0.pkg
xcrun stapler validate dist/OpenInTerminal-2.0.0.pkg
pkgutil --check-signature dist/OpenInTerminal-2.0.0.pkg
spctl --assess --type install --verbose dist/OpenInTerminal-2.0.0.pkg
```

Proceed only after notarization reports **Accepted**. If distributing the app ZIP too, notarize that
artifact separately, staple the matching app, and recreate the ZIP:

```sh
xcrun notarytool submit dist/OpenInTerminal-2.0.0-app.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple 'build/Open in Terminal.app'
xcrun stapler validate 'build/Open in Terminal.app'
codesign --verify --deep --strict 'build/Open in Terminal.app'
spctl --assess --type execute --verbose 'build/Open in Terminal.app'
ditto -c -k --keepParent --norsrc 'build/Open in Terminal.app' dist/OpenInTerminal-2.0.0-app.zip
```

Apple permits ZIP submission but cannot staple a ticket to the ZIP itself. See
[Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
and [Developer ID requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Test actual downloaded artifacts on another account or Mac, including extension enablement and
Terminal Automation permission. Signing does not prove Finder behavior or historical compatibility.

Recalculate checksums after stapling and repackaging, before upload:

```sh
cd dist
shasum -a 256 OpenInTerminal-2.0.0.pkg OpenInTerminal-2.0.0-app.zip > SHA256SUMS
cd ..
```

Do not run the default build over these final artifacts: it would replace them with a new development build.

## 2. Publish an immutable GitHub release

After the repository exists and the release commit is pushed, tag that tested commit and attach the
final artifacts. The commands below publish a release; they have not been run as part of this guide.

```sh
git tag v2.0.0
git push origin v2.0.0
gh release create v2.0.0 \
  dist/OpenInTerminal-2.0.0.pkg \
  dist/OpenInTerminal-2.0.0-app.zip \
  dist/SHA256SUMS \
  --repo mahdi-salmanzade/OpenInTerminal \
  --verify-tag --title 'Open in Terminal 2.0.0' --generate-notes
```

Do not replace a published version's files with different bytes. Release a new version and checksum
when the software changes. The cask must point to a real versioned asset, not a local file or an
unpublished download URL.

## 3. Add a cask to a tap

Start with your own tap; inclusion in Homebrew's official repository is a separate review process.
The conventional GitHub repository is **`mahdi-salmanzade/homebrew-tap`**, with casks in `Casks/`.
To prepare it beside this checkout:

```sh
mkdir -p ../homebrew-tap/Casks
git -C ../homebrew-tap init -b main
```

Save the definition below as `../homebrew-tap/Casks/openinterminal-finder.rb` and replace its checksum
with the final `.pkg` checksum.

This is a template only; the placeholder must not be published as a working cask:

```ruby
cask "openinterminal-finder" do
  version "2.0.0"
  sha256 "REPLACE_WITH_FINAL_PKG_SHA256"

  url "https://github.com/mahdi-salmanzade/OpenInTerminal/releases/download/v#{version}/OpenInTerminal-#{version}.pkg"
  name "Open in Terminal"
  desc "Finder folder actions for Terminal and new Terminal windows"
  homepage "https://github.com/mahdi-salmanzade/OpenInTerminal"

  depends_on macos: :monterey

  pkg "OpenInTerminal-#{version}.pkg"

  uninstall quit:    "io.openinterminal.app",
            pkgutil: "io.openinterminal.app.pkg"

  caveats <<~EOS
    Open the Open in Terminal app from Applications, then enable its Finder extension.
    The new-window action may request permission to control Terminal.
  EOS
end
```

After reviewing that definition, create and push the tap:

```sh
git -C ../homebrew-tap add Casks/openinterminal-finder.rb
git -C ../homebrew-tap commit -m 'Add Open in Terminal Finder cask'
gh repo create mahdi-salmanzade/homebrew-tap --public --source ../homebrew-tap --remote origin --push
```

The `.pkg` installs `/Applications/Open in Terminal.app` and records package ID
`io.openinterminal.app.pkg`. Homebrew requires an uninstall declaration for `pkg` artifacts;
`pkgutil` uses that receipt to remove the installed files. Test removal of the embedded extension
as well as the app. Do not delete unrelated Services workflows or Terminal preferences.
[Homebrew's cask cookbook](https://docs.brew.sh/Cask-Cookbook) documents these stanzas.

An alternative is to distribute the notarized app ZIP with its own checksum and
`app "Open in Terminal.app"`, letting Homebrew manage the app directly. That route does not use the
installer receipt or require a `pkgutil` uninstall stanza. Both routes still require the user to enable
the Finder extension; a cask cannot silently grant extension or Automation consent.

Once the release and conventional tap are available, users can install with:

```sh
brew install --cask mahdi-salmanzade/tap/openinterminal-finder
```

You can instead keep `Casks/openinterminal-finder.rb` in the **source repository**, avoiding a second
repository. Since its name does not start with `homebrew-`, users must supply the clone URL once:

```sh
brew tap mahdi-salmanzade/openinterminal https://github.com/mahdi-salmanzade/OpenInTerminal.git
brew install --cask mahdi-salmanzade/openinterminal/openinterminal-finder
```

These are alternative tap layouts; pick one. Fully qualified installation trusts the named cask
under current Homebrew. See [tap naming](https://docs.brew.sh/Taps) and
[tap trust](https://docs.brew.sh/Tap-Trust).

## 4. Test and maintain the cask

For the conventional tap, run:

```sh
brew style --cask mahdi-salmanzade/tap/openinterminal-finder
brew audit --cask --online mahdi-salmanzade/tap/openinterminal-finder
brew install --cask mahdi-salmanzade/tap/openinterminal-finder
brew uninstall --cask mahdi-salmanzade/tap/openinterminal-finder
```

Test the app and Finder actions between install and uninstall, including first-run permissions.
For each update, publish a new upstream release, change `version` and `sha256` in the tap, test an
upgrade, and push. Users receive tap changes through `brew update` and can upgrade the cask.
See [creating and maintaining a tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).

## Official Homebrew inclusion and older Macs

For a later submission to `homebrew/cask`, the app must work on the latest major macOS and its
assessable executables/installers must pass Homebrew's Gatekeeper checks. A new GitHub project normally
needs public interest and at least 30 days of history. For a submission by the repository owner,
the published notability threshold is **90 forks, 90 watchers, or 225 stars**; exceptions are discretionary.
Your own tap does not need to meet those official-repository thresholds.
[Cask criteria](https://docs.brew.sh/Acceptable-Casks),
[shared acceptance policy](https://docs.brew.sh/Package-Acceptance-Policy).

Homebrew is not a way to reach every historical macOS release. Current Homebrew does not run on
Catalina 10.15 or earlier, and Intel Macs are Tier 3 as of September 2026. The native app itself
requires macOS 12 or later. Keep the separate legacy workflow download for older systems and test
those systems independently. [Homebrew support tiers](https://docs.brew.sh/Support-Tiers).
