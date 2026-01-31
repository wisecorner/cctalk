//
//  FeedbackView.swift
//  VoiceClaudePoC
//
//  UI for collecting and submitting user feedback.
//

import SwiftUI
import AppKit

/// View states for feedback submission
enum FeedbackViewState {
    case editing
    case sending
    case success(issueNumber: Int)
    case error(message: String)
}

/// Feedback submission view
struct FeedbackView: View {
    @ObservedObject var feedbackService: FeedbackService
    @State private var feedbackText: String = ""
    @State private var viewState: FeedbackViewState = .editing
    @FocusState private var isTextFieldFocused: Bool

    let isAutoPopup: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch viewState {
            case .editing, .sending:
                editingView
            case .success(let issueNumber):
                successView(issueNumber: issueNumber)
            case .error(let message):
                errorView(message: message)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Send Feedback")
                    .font(.headline)

                Spacer()
            }

            // Description
            Text("Help us improve CCTalk! Share your thoughts, suggestions, or report issues.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Text editor
            TextEditor(text: $feedbackText)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .focused($isTextFieldFocused)
                .disabled(isSending)

            // Character count
            HStack {
                Text("\(feedbackText.count)/\(FeedbackService.maxFeedbackLength) characters")
                    .font(.caption)
                    .foregroundColor(characterCountColor)

                Spacer()

                if feedbackText.count < FeedbackService.minFeedbackLength {
                    Text("Min \(FeedbackService.minFeedbackLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    if isAutoPopup {
                        feedbackService.recordPopupDismissed()
                    }
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text(isAutoPopup ? "Not Now" : "Cancel")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(isSending)

                Button(action: submitFeedback) {
                    HStack {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Send Feedback")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSubmit)
            }

            // Hint
            Text("Press \u{2318}Return to send")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Success View

    private func successView(issueNumber: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Thank You!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your feedback has been received and will help us improve CCTalk.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if issueNumber > 0 {
                Text("Reference: #\(issueNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onDismiss) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.vertical, 20)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)

                Text("Submission Failed")
                    .font(.headline)

                Spacer()
            }

            // Error message
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)

            // The feedback text is preserved
            Text("Your feedback text has been preserved. You can try again.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Buttons
            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: {
                    viewState = .editing
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Try Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    private var isSending: Bool {
        if case .sending = viewState {
            return true
        }
        return false
    }

    private var canSubmit: Bool {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= FeedbackService.minFeedbackLength
            && trimmed.count <= FeedbackService.maxFeedbackLength
            && !isSending
    }

    private var characterCountColor: Color {
        if feedbackText.count > FeedbackService.maxFeedbackLength {
            return .red
        } else if feedbackText.count < FeedbackService.minFeedbackLength {
            return .secondary
        } else {
            return .green
        }
    }

    private func submitFeedback() {
        guard canSubmit else { return }

        viewState = .sending

        Task {
            let result = await feedbackService.submitFeedback(feedbackText)

            await MainActor.run {
                switch result {
                case .success(let issueNumber):
                    viewState = .success(issueNumber: issueNumber)
                case .error(let message):
                    viewState = .error(message: message)
                }
            }
        }
    }
}

// MARK: - Feedback Window Controller

class FeedbackWindowController {
    private var window: NSWindow?
    private var closeDelegate: FeedbackWindowCloseDelegate?

    static let shared = FeedbackWindowController()

    private init() {}

    /// Show feedback window
    func show(feedbackService: FeedbackService, isAutoPopup: Bool = false) {
        // Close existing window if any
        hide()

        let contentView = FeedbackView(
            feedbackService: feedbackService,
            isAutoPopup: isAutoPopup,
            onDismiss: { [weak self] in
                self?.hide()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Send Feedback - CCTalk"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Handle window close button
        let delegate = FeedbackWindowCloseDelegate(
            feedbackService: feedbackService,
            isAutoPopup: isAutoPopup
        ) { [weak self] in
            self?.window = nil
            self?.closeDelegate = nil
        }
        window.delegate = delegate
        self.closeDelegate = delegate

        self.window = window
    }

    /// Hide feedback window
    func hide() {
        window?.close()
        window = nil
        closeDelegate = nil
    }
}

// MARK: - Window Close Delegate

private class FeedbackWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let feedbackService: FeedbackService
    private let isAutoPopup: Bool
    private let onClose: () -> Void

    init(feedbackService: FeedbackService, isAutoPopup: Bool, onClose: @escaping () -> Void) {
        self.feedbackService = feedbackService
        self.isAutoPopup = isAutoPopup
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        // If closed via X button during auto popup, record dismissal
        if isAutoPopup {
            Task { @MainActor in
                feedbackService.recordPopupDismissed()
            }
        }
        onClose()
    }
}

// MARK: - Preview

#Preview("Editing") {
    FeedbackView(
        feedbackService: FeedbackService(),
        isAutoPopup: false,
        onDismiss: {}
    )
}
