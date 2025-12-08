# Parrot

A macOS menubar app for instant audio recording and playback with global keyboard shortcuts.

## Features

- **Hold to Record** - Hold a shortcut key to record, release to play back
- **Toggle to Record** - Tap to start/stop recording with automatic playback
- **Global Shortcuts** - Works system-wide, even when the app is in the background
- **Visual Indicators** - On-screen indicators for recording and playback states
- **Configurable Audio** - Select input/output devices and adjust playback settings

## Requirements

- macOS 13.0 or later
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

1. Click the speaker icon in the menubar to access Settings
2. Configure your preferred keyboard shortcuts
3. Use the shortcuts anywhere to record and play back audio

## License

MIT
