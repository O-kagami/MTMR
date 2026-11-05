# Local test packaging

This is an experimental build, not a production release. It is built with an
ad-hoc signature; it is **not signed with Developer ID or notarized**. macOS may
refuse to open it on another Mac. Do not bypass macOS security to install it.
It has not been accepted by Apple's notarization service.

Prerequisites: a compatible macOS host with Xcode installed at the usual path,
the macOS SDK, and the repository's bundled universal Sparkle framework. To
create a local ARM64 + x86_64 disk image, pass a **new absolute directory**:

```sh
./scripts/package-local-test.sh /absolute/path/to/a-new-output-directory
```

The script refuses to overwrite an existing output directory, writes builds to
a temporary directory, creates an ad-hoc-signed `MTMR-UNNOTARIZED.dmg`, a clear
warning, and SHA-256 checksums, then removes its temporary files. It checks both
architectures and the app signature. Override `DEVELOPER_DIR` only to choose an
installed Xcode and `MTMR_TEST_BUNDLE_ID` to choose a unique, owned identifier;
the default is this fork's development identifier. Neither option changes the
existing app or settings. Build numbers do not increment automatically; update
the version deliberately before publishing.

For a real public release, the owner must obtain a valid Developer ID
Application certificate, sign the app and nested helper with appropriate hardened
runtime and entitlements, submit and staple the distribution to Apple's notary
service, and validate on a clean Mac. This script does not implement, pretend to
perform, or bypass those steps.

The fork does not use the original MTMR updater feed: auto-update is not
configured. The menu item opens this fork's GitHub Releases page; a separate,
securely signed update feed and release signing process are future work.
Existing users should back up `~/Library/Application Support/MTMR/` and avoid
running multiple Touch Bar managers at once. Some widgets require separate
support files and user grants; this package alone does not yet establish that
all customized widgets run on a clean Mac. No private user preset, Spotify
tokens, playlists, or API keys should be included in a distributable package.

The local test package strips debug-map paths from the main executable before ad-hoc signing; it does not modify the source tree or installed app. Both architectures are verified for the app and each bundled helper.
