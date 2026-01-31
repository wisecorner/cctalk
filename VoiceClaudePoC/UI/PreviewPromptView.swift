import SwiftUI
import AppKit

/// Preview window for editing transcription before sending
struct PreviewPromptView: View {
    @State var transcribedText: String
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "text.bubble")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Review Transcription")
                    .font(.headline)

                Spacer()
            }

            // Text editor
            TextEditor(text: $transcribedText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 200)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .focused($isTextFieldFocused)

            // Character count
            HStack {
                Text("\(transcribedText.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    onCancel()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: {
                    onSend(transcribedText)
                }) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send to Claude")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Hint
            Text("Press Enter to send, Escape to cancel")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - Preview Window Controller

class PreviewPromptWindowController {
    private var window: NSWindow?

    static let shared = PreviewPromptWindowController()

    private init() {}

    func show(
        transcribedText: String,
        onSend: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // Close existing window if any
        hide()

        let contentView = PreviewPromptView(
            transcribedText: transcribedText,
            onSend: { [weak self] editedText in
                self?.hide()
                onSend(editedText)
            },
            onCancel: { [weak self] in
                self?.hide()
                onCancel()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Review Prompt"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Handle window close button
        window.delegate = WindowCloseDelegate { [weak self] in
            self?.window = nil
            onCancel()
        }

        self.window = window
    }

    func hide() {
        window?.close()
        window = nil
    }
}

// MARK: - Window Close Delegate

private class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

#Preview {
    PreviewPromptView(
        transcribedText: "This is a sample transcription that you can edit before sending.",
        onSend: { _ in },
        onCancel: { }
    )
}
