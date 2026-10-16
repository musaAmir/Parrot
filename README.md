# Parrot

Record your voice with a shortcut. Release to hear it back.

[Download](https://github.com/musaAmir/Parrot/releases/latest) · [Website](https://musaamir.github.io/Parrot/)

Free and open source. macOS 14+. Apple silicon and Intel.

## Install

Unzip the download, move **Parrot.app** to **Applications**, and open it. Grant microphone and Accessibility permissions to use global recording shortcuts.

Hold **⌘⇧Z** to record; release to play back. Change shortcuts, playback delay, and recording retention in Settings.

Version 1.2.0 is not notarized by Apple; macOS may block first launch. Older versions need one manual download to gain automatic update checks.

## Build

Open `Parrot.xcodeproj` in Xcode, or run `./build.sh`. Run checks with `swift test`.

[Release guide](docs/updates.md) · [Website guide](docs/website.md) · [MIT license](LICENSE)
