# Contributing to CCTalk

Thank you for your interest in contributing to CCTalk!

## How to Contribute

### Reporting Bugs

1. Check [existing issues](https://github.com/wisecorner/cctalk/issues) first
2. Open a new issue with:
   - macOS version
   - CCTalk version
   - Steps to reproduce
   - Expected vs actual behavior

### Suggesting Features

Open an issue with the `enhancement` label describing:
- The problem you're trying to solve
- Your proposed solution
- Any alternatives you've considered

### Submitting Code

1. **Fork** the repository
2. **Create a branch** from `develop`:
   ```bash
   git checkout -b feature/your-feature develop
   ```
3. **Make your changes**
4. **Test** thoroughly on macOS
5. **Commit** with clear messages:
   ```bash
   git commit -m "Add: brief description of change"
   ```
6. **Push** to your fork:
   ```bash
   git push origin feature/your-feature
   ```
7. **Open a Pull Request** to `develop`

### Pull Request Guidelines

- Keep PRs focused on a single change
- Update documentation if needed
- Follow existing code style
- Test on macOS 26.0+ before submitting
- Link related issues in PR description

## Development Setup

### Requirements

- Xcode 26.0+
- macOS 26.0+
- Swift 5.9+

### Building

```bash
git clone https://github.com/wisecorner/cctalk.git
cd cctalk
open VoiceClaudePoC.xcodeproj
```

Press `Cmd+B` to build, `Cmd+R` to run.

### Project Structure

```
VoiceClaudePoC/
├── App/                    # AppState, main orchestration
├── Features/
│   ├── Recording/          # Audio recording
│   ├── Transcription/      # Speech-to-text providers
│   ├── Injection/          # Terminal detection, keystroke injection
│   ├── AI/                 # Apple Intelligence formatting
│   ├── Feedback/           # User feedback collection
│   └── Updates/            # Sparkle auto-updater
├── UI/                     # SwiftUI views
└── Utilities/              # Helpers (Keychain, Permissions, etc.)
```

## Code Style

- Use Swift's standard naming conventions
- Keep functions focused and small
- Add comments for non-obvious logic
- Use `@MainActor` for UI-related code
- Prefer `async/await` over callbacks

## Questions?

Open an issue or use the in-app feedback feature.
