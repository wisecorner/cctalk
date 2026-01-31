import SwiftUI

/// Menu bar dropdown content
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var historyService: PromptHistoryService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status Section
            statusSection

            Divider()
                .padding(.vertical, 4)

            // Recording Section
            recordingSection

            Divider()
                .padding(.vertical, 4)

            // Last Transcription
            if !appState.lastTranscription.isEmpty {
                lastTranscriptionSection

                Divider()
                    .padding(.vertical, 4)
            }

            // Prompt History
            if !historyService.recentPrompts.isEmpty {
                historySection

                Divider()
                    .padding(.vertical, 4)
            }

            // Configuration Section
            configurationSection

            Divider()
                .padding(.vertical, 4)

            // App Controls
            appControlsSection
        }
        .padding(8)
        .frame(width: 280)
        .onAppear {
            // Refresh Claude status when menu opens
            appState.checkClaudeStatus()
            historyService.fetchRecentPrompts()
            // Fetch ElevenLabs usage if enabled
            if appState.transcriptionEngine == .elevenLabs {
                Task {
                    await appState.elevenLabsTranscriptionProvider.fetchSubscription()
                }
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.status.displayText)
                    .font(.headline)

                Spacer()

                // Transcription engine badge
                HStack(spacing: 4) {
                    Image(systemName: appState.transcriptionEngine == .elevenLabs ? "cloud.fill" : "apple.logo")
                        .font(.caption2)
                    Text(appState.transcriptionEngine == .elevenLabs ? "ElevenLabs" : "Apple")
                        .font(.caption2)
                    if appState.transcriptionEngine == .elevenLabs,
                       let usage = appState.elevenLabsTranscriptionProvider.usageText {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(usage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(appState.transcriptionEngine == .elevenLabs ? Color.purple.opacity(0.2) : Color.gray.opacity(0.2))
                .cornerRadius(4)
            }

            if appState.claudeSessions.isEmpty {
                Text("Claude not detected - run claude in terminal")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text("\(appState.claudeSessions.count) Claude session(s) active")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Recording Section

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                appState.toggleRecording()
            }) {
                HStack {
                    Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundColor(appState.isRecording ? .red : .blue)

                    VStack(alignment: .leading) {
                        Text(appState.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.body)

                        if appState.isRecording {
                            Text(formatDuration(appState.recordingDuration))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.red)
                        } else {
                            Text("⌘⇧V")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.canRecord && !appState.isRecording)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Last Transcription Section

    private var lastTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last transcription:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(appState.lastTranscription)
                .font(.callout)
                .lineLimit(3)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)

            Button("Resend") {
                appState.resendLastTranscription()
            }
            .disabled(!appState.canInject)
            .font(.caption)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent Prompts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    historyService.clearAllHistory()
                }) {
                    Text("Clear")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            ForEach(historyService.recentPrompts.prefix(5)) { prompt in
                Button(action: {
                    appState.sendPrompt(prompt.text)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.truncatedText)
                                .font(.callout)
                                .lineLimit(1)
                            Text(prompt.formattedDate)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Configuration Section

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Terminal picker
            HStack {
                Text("Terminal:")
                    .font(.caption)
                Spacer()
                Picker("", selection: $appState.selectedTerminal) {
                    ForEach(TerminalDetector.availableTerminals, id: \.self) { terminal in
                        Text(terminal).tag(terminal)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - App Controls Section

    private var appControlsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                appState.checkClaudeStatus()
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Claude Status")
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                openSettingsWindow()
            }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings...")
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                FeedbackWindowController.shared.show(feedbackService: appState.feedbackService)
            }) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Send Feedback")
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                UpdaterManager.shared.checkForUpdates()
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Check for Updates...")
                }
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.vertical, 4)

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit CCTalk")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.status {
        case .ready:
            return .green
        case .recording:
            return .red
        case .transcribing, .formatting, .sending:
            return .orange
        case .error:
            return .red
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration) % 60
        let minutes = Int(duration) / 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
        .environmentObject(PromptHistoryService.shared)
}
