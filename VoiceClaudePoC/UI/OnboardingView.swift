import SwiftUI

/// Step-by-step onboarding wizard
struct OnboardingView: View {
    @StateObject private var permissions = PermissionsHelper()
    @StateObject private var hotkeyManager = HotkeyManager()
    @AppStorage("selectedTerminal") private var selectedTerminal: String = "Terminal"

    @State private var currentStep = 0

    var onComplete: (() -> Void)?

    private let totalSteps = 5

    private var installedTerminals: [String] {
        TerminalDetector.installedTerminals
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, 24)
                .padding(.bottom, 16)

            // Step content
            Group {
                switch currentStep {
                case 0:
                    microphoneStep
                case 1:
                    accessibilityStep
                case 2:
                    hotkeyStep
                case 3:
                    terminalStep
                case 4:
                    elevenLabsInfoStep
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)

            // Navigation
            navigationButtons
                .padding(24)
        }
        .frame(width: 440, height: 540)
        .onAppear {
            permissions.checkAllPermissions()
            // Pre-select first installed terminal
            if !installedTerminals.contains(selectedTerminal),
               let first = installedTerminals.first {
                selectedTerminal = first
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPermissions)) { _ in
            permissions.checkAllPermissions()
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ? Color.blue : (step < currentStep ? Color.green : Color.gray.opacity(0.3)))
                    .frame(width: 10, height: 10)

                if step < totalSteps - 1 {
                    Rectangle()
                        .fill(step < currentStep ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 24, height: 2)
                }
            }
        }
    }

    // MARK: - Step 1: Microphone

    private var microphoneStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(microphoneGranted ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: microphoneGranted ? "checkmark.circle.fill" : "mic.fill")
                    .font(.system(size: 44))
                    .foregroundColor(microphoneGranted ? .green : .blue)
            }

            // Text
            VStack(spacing: 8) {
                Text("Microphone Access")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Required to capture your voice commands.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Action
            if microphoneGranted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            } else {
                Button(action: {
                    Task {
                        await permissions.requestMicrophonePermission()
                    }
                }) {
                    Text("Enable Microphone")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
    }

    private var microphoneGranted: Bool {
        permissions.microphoneStatus == .granted
    }

    // MARK: - Step 2: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(accessibilityGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "accessibility")
                    .font(.system(size: 44))
                    .foregroundColor(accessibilityGranted ? .green : .orange)
            }

            // Text
            VStack(spacing: 8) {
                Text("Accessibility Access")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Required to send voice commands to your terminal.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Action
            if accessibilityGranted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            } else {
                Button(action: {
                    // Lower window level so system prompt is visible
                    NotificationCenter.default.post(name: .lowerOnboardingWindow, object: nil)
                    permissions.requestAccessibilityPermission()
                }) {
                    Text("Open System Settings")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
    }

    private var accessibilityGranted: Bool {
        permissions.accessibilityStatus == .granted
    }

    // MARK: - Step 3: Hotkey Configuration

    private var hotkeyStep: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.indigo)
            }

            // Text
            VStack(spacing: 6) {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Configure how to start voice recording")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Hotkey Configuration
            VStack(spacing: 16) {
                // Current shortcut display
                VStack(spacing: 8) {
                    Text("Press shortcut to start/stop recording:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if hotkeyManager.isRecordingShortcut {
                            Text("Press keys...")
                                .font(.system(.title3, design: .monospaced))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(8)
                        } else {
                            Text(hotkeyManager.currentKeyCombo)
                                .font(.system(.title3, design: .monospaced))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }

                    HStack(spacing: 12) {
                        if hotkeyManager.isRecordingShortcut {
                            Button("Cancel") {
                                hotkeyManager.cancelRecording()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Change Shortcut") {
                                hotkeyManager.startRecording()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reset") {
                                hotkeyManager.resetToDefault()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Divider()
                    .padding(.horizontal, 40)

                // Fn key option
                VStack(spacing: 8) {
                    Toggle(isOn: $hotkeyManager.holdFnToRecordEnabled) {
                        HStack {
                            Image(systemName: "fn")
                                .font(.caption)
                                .padding(4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold Fn to record")
                                    .font(.body)
                                Text("Hold Fn key, speak, release to send")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 40)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Step 4: Terminal Selection

    private var terminalStep: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.purple)
            }

            // Text
            VStack(spacing: 6) {
                Text("Select Your Terminal")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Where do you run Claude Code?")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Terminal list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(installedTerminals, id: \.self) { terminal in
                        Button(action: {
                            selectedTerminal = terminal
                        }) {
                            HStack {
                                Image(systemName: terminalIcon(for: terminal))
                                    .frame(width: 24)

                                Text(terminal)

                                Spacer()

                                if selectedTerminal == terminal {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selectedTerminal == terminal ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 150)
            .frame(width: 280)

            Text("\(installedTerminals.count) terminal(s) detected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 16)
    }

    private func terminalIcon(for terminal: String) -> String {
        switch terminal {
        case "Terminal": return "apple.terminal.fill"
        case "iTerm2": return "terminal"
        case "Ghostty": return "ghost"
        case "Warp": return "bolt.fill"
        case "Alacritty": return "a.square.fill"
        case "kitty": return "cat.fill"
        default: return "terminal"
        }
    }

    // MARK: - Step 5: ElevenLabs Info

    private var elevenLabsInfoStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "globe")
                    .font(.system(size: 44))
                    .foregroundColor(.cyan)
            }

            // Text
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("CCTalk uses Apple's on-device transcription by default.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // ElevenLabs info box
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                    Text("Need more languages?")
                        .font(.headline)
                }

                Text("Apple supports only a few languages. ElevenLabs Scribe supports **99 languages**.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .foregroundColor(.blue)
                    Text("Go to **Settings → Transcription** to add your ElevenLabs API key.")
                        .font(.callout)
                }

                Link(destination: URL(string: "https://elevenlabs.io")!) {
                    HStack {
                        Text("Get API key at elevenlabs.io")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.08))
            .cornerRadius(12)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            // Back button
            if currentStep > 0 {
                Button(action: {
                    withAnimation {
                        currentStep -= 1
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Next/Finish button
            if currentStep < totalSteps - 1 {
                Button(action: {
                    withAnimation {
                        currentStep += 1
                    }
                }) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            } else {
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                    onComplete?()
                }) {
                    HStack {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0:
            return microphoneGranted
        case 1:
            return accessibilityGranted
        default:
            return true
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
