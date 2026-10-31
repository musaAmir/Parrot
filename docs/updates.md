# Parrot updates and releases

Sparkle 2.10.0 is pinned through Xcode’s Swift Package dependency. The bundled public key verifies updates from:

https://github.com/musaAmir/Parrot/releases/latest/download/appcast.xml

Parrot checks daily, with a manual check in the menu bar and Settings. Checks can be disabled. Automatic downloads and installation are off by default. Existing copies before 1.2.0 require one manual download. Audio stays local; update requests contact GitHub and its download hosts.

## Local build identity and permission continuity

`build.sh` uses `CODESIGN_IDENTITY` or the public fingerprint in the local, ignored `.signing-identity` file. It never silently falls back to ad-hoc signing. On the development Mac, use the same identity on every rebuild. Keep `com.parrot.app` and `/Applications/Parrot.app` stable. Do not reset TCC permissions as part of building or installing.

Switching from the old ad-hoc identity requires one new grant under **Device Control and Data Access** on macOS 27 (Accessibility on older versions). Check identity continuity with `python3 scripts/check-signing-continuity.py NEW_APP PREVIOUS_APP`. The command verifies signatures and matching certificate-based designated requirements, not the OS permission database. Permission retention still needs an installation/update round trip after approval.

An Apple Development certificate is suitable for local development, not a substitute for Developer ID distribution and notarization. Changing signing class or certificate identity can prompt again. The CI build explicitly opts into ad-hoc signing and must not replace the local installed copy.

## Signing key

The private Ed25519 key stays in the Mac’s login Keychain under account `com.parrot.app.sparkle`. Only its public key belongs in `Parrot/Info.plist`. Run `./scripts/setup-updates.sh` to verify the local key matches the app. Keep a secure backup using Sparkle’s `generate_keys` tool and a trusted password manager. Never commit the private key, paste it into chat, or put it in a public CI log. Do not generate a replacement for an already published app; restore its existing key.

## Next release

1. Update the marketing version and integer build number in `Parrot.xcodeproj/project.pbxproj`. Increase the build number for every release. Add release notes and update website download links and signing-status text.
2. Run `swift test`, `python3 -m unittest discover -s Tests/ReleaseScripts`, `./build.sh release universal`, and `Tests/ReleaseScripts/smoke-sparkle.sh`. Test recording, both shortcut modes, changing modifier order, quick repeated takes, sleep/wake, permissions, saving, audio devices, and updating on supported Mac hardware.
3. Commit the release source and notes before preparing the final archive.
4. With a Developer ID Application certificate and a `notarytool` Keychain profile configured, run:

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='parrot-notary' \
./scripts/prepare-release.sh 1.3.0 7 ReleaseNotes/1.3.0.md
```

The script builds a universal app, signs inside-out, submits for notarization, staples the accepted ticket, verifies Gatekeeper acceptance, then signs the final ZIP and appcast. The previous feed is verified and retained for older supported releases. Assets go in `build/releases/vVERSION/` with checksums and a source-commit manifest.

For a certificate-signed development release that preserves the local build identity, explicitly select `--development`. This uses `CODESIGN_IDENTITY` or `.signing-identity`, verifies that it is an Apple Development certificate, and signs the archive/feed using the existing Sparkle key. It is not notarized and Gatekeeper may block first launch:

```sh
./scripts/prepare-release.sh --development 1.3.0 7 ReleaseNotes/1.3.0.md
```

A disposable ad-hoc release can still be prepared with `--adhoc`. This changes the app identity and can invalidate existing permission approvals:

```sh
./scripts/prepare-release.sh --adhoc 1.3.0 7 ReleaseNotes/1.3.0.md
```

5. Review the exact packaged app and run `./scripts/publish-release.sh v1.3.0` to upload a draft. Inspect and publish it as the latest release in GitHub. Never replace an already published ZIP, reuse a build number, or edit signed artifacts. Make another release instead.

The release key remains local; routine app releases are prepared on the signing Mac. GitHub Actions independently tests code, universal builds, metadata, and signing/tamper rejection using a disposable key. It does not hold the production key or automatically publish application binaries.

## Current release limits

1.3.0 is Apple Development signed, not Apple-notarized. Migrating from 1.2.0’s ad-hoc identity can require one permission grant; the local signed build retained microphone and Device Control and Data Access approval across a rebuild and replacement. Unit tests and a Sparkle startup probe do not replace physical microphone, device-routing, Accessibility, or Intel hardware checks. A real installation-and-update round trip requires a later higher build and user approval to run its installer. Clearly distinguish these checks from signature verification.
