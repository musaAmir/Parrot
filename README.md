# Parrot

Record your voice with a shortcut. Release to hear it back.

[Download](https://github.com/musaAmir/Parrot/releases/latest) · [Website](https://musaamir.github.io/Parrot/)

Free and open source. macOS 14+. Apple silicon and Intel.

## Install

Unzip the download, move **Parrot.app** to **Applications**, and open it. Grant microphone and Device Control and Data Access permissions (Accessibility on older macOS versions) to use global recording shortcuts.

Hold **⌘⇧Z** to record; release to play back. With recording sounds enabled, wait for the start cue and the timer before speaking: capture begins after the cue plus a 150 ms echo gap. Releasing during that lead-in cancels the take. Playback waits for the stop cue to finish. Change shortcuts, playback delay, and recording retention in Settings.

Open **Recordings…** from the menu bar to browse your latest takes, play or pause, seek, and save a permanent copy. Parrot keeps up to 10 recent takes locally when retention is enabled. The native settings window shares Hush’s unified toolbar, sidebar badges, grouped cards and compact AppKit controls. General contains startup and retention settings; Appearance contains a recording-panel preview, optional pause/stop buttons and visibility settings. Recordings also lets you start, pause, resume and stop a take without a shortcut.

Version 1.3.0 is signed with an Apple Development certificate and is not notarized by Apple; macOS may block first launch. Moving from an older ad-hoc build can require one permission approval. Versions before 1.2.0 need one manual download to gain automatic update checks.

## Build

Open `Parrot.xcodeproj` in Xcode, or run `./build.sh`. Run checks with `swift test`.

Build output lives in `build.noindex/`, with `build/` as a compatibility symlink, so intermediate apps stay out of Spotlight and Alfred. Only the copy in `/Applications` needs to appear in app search.

Local builds require a stable code-signing identity. Save a certificate fingerprint (from `security find-identity -v -p codesigning`) in the ignored `.signing-identity` file, or set `CODESIGN_IDENTITY`. The private key stays in Keychain. The build fails if no identity is configured; ad-hoc signing requires an explicit `CODESIGN_IDENTITY=-` and is intended only for CI or disposable builds.

Install updates at the same path and keep the same certificate and bundle identifier. Moving from an old ad-hoc build to a certificate-signed build can require one final permission grant. Verify continuity with `python3 scripts/check-signing-continuity.py NEW_APP PREVIOUS_APP`. This verifies the signing prerequisite; an actual macOS permission/update round trip must still be checked after the first grant. Apple Development signing supports local development; public releases still require Developer ID signing and notarization.

[Release guide](docs/updates.md) · [Website guide](docs/website.md) · [MIT license](LICENSE)
