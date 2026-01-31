# CCTalk

Voice-to-text input for [Claude Code](https://claude.ai/code) CLI on macOS.

Record your voice, get it transcribed, and send directly to Claude Code in your terminal.

## Features

- **Voice Recording** - Press hotkey to record, release to transcribe and send
- **Multiple Transcription Engines**
  - Apple Speech (on-device, free)
  - ElevenLabs (cloud, 99 languages)
- **AI Formatting** - Apple Intelligence cleans up punctuation and capitalization
- **Preview Mode** - Review and edit transcription before sending
- **Multi-Terminal Support** - Ghostty, Terminal.app, iTerm2, Warp, Alacritty, kitty
- **Auto-Updates** - Built-in Sparkle updater

## Requirements

- macOS 26.0+ (Tahoe)
- [Claude Code CLI](https://claude.ai/code) running in a supported terminal

## Installation

Download the latest `CCTalk.dmg` from [Releases](https://github.com/wisecorner/cctalk/releases).

## Usage

1. Start Claude Code in your terminal: `claude`
2. Click CCTalk in menu bar
3. Press `Cmd+Shift+V` (or hold `Fn`) to record
4. Release to transcribe and send to Claude

## Permissions

CCTalk requires:
- **Microphone** - For voice recording
- **Accessibility** - For keystroke injection
- **Automation** - For terminal control

Grant these in System Settings → Privacy & Security.

## Configuration

Access settings via menu bar → Settings:
- **Hotkey** - Customize recording shortcut
- **Terminal** - Select your terminal app
- **Transcription** - Choose engine and language
- **AI Formatting** - Enable/disable, customize prompt
- **Preview** - Enable review before sending

## Building from Source

```bash
git clone https://github.com/wisecorner/cctalk.git
cd cctalk
open VoiceClaudePoC.xcodeproj
```

Build with Xcode 26.0+.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[Noncommercial License](LICENSE) - Free to use and modify, not for sale.

## Links

- [wisecorner.com](https://wisecorner.com)
- [Claude Code](https://claude.ai/code)
