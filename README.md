# Parrot

A macOS menubar app for instant audio recording and playback with global keyboard shortcuts.

## Features

- **Hold to Record** - Hold a shortcut key to record, release to play back
- **Toggle to Record** - Tap to start/stop recording with automatic playback
- **Global Shortcuts** - Works system-wide, even when the app is in the background
- **Live Level Meter** - The recording indicator shows your actual microphone input
- **Auto-Stop** - Recordings end at a configurable limit so a stuck key can't run away
- **Save Your Takes** - The 10 most recent recordings stay in the menu bar, ready to replay or save
- **Configurable Audio** - Pick input and output devices; Parrot restores your system defaults afterwards

## Requirements

- macOS 14.0 or later
- Microphone permission
- Accessibility permission (for global keyboard shortcuts)

## Install

1. Download the latest release from [Releases](../../releases)
2. Move `Parrot.app` to your Applications folder
3. Launch Parrot and grant the required permissions

### Build from Source

```bash
git clone https://github.com/yourusername/Parrot.git
cd Parrot
open Parrot.xcodeproj
```

Build and run with Xcode (Cmd+R).

## Usage

1. Click the Parrot icon in the menubar to access Settings
2. Configure your preferred keyboard shortcuts
3. Use the shortcuts anywhere to record and play back audio

Recordings are stored in `~/Library/Application Support/Parrot/Recordings` and
pruned to the 10 most recent. Turn off **Keep Recent Recordings** in Settings to
have each take deleted as soon as the next one starts.

## License

MIT
