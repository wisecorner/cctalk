import SwiftUI
import AppKit

/// Alert view shown when Claude Code is not in the active terminal tab
/// Also used as session picker when multiple sessions exist
struct ClaudeNotInTabAlertView: View {
    let message: String
    let sessions: [ClaudeSession]
    let onSelectSession: ((ClaudeSession) -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: sessions.count > 1 ? "list.bullet" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(sessions.count > 1 ? .blue : .orange)

                Text(sessions.count > 1 ? "Select Claude Session" : "Claude Code Not Active")
                    .font(.headline)

                Spacer()
            }

            // Message
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Sessions list
            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if onSelectSession != nil {
                        Text("Click to select:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text("Available sessions:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            isSelectable: onSelectSession != nil,
                            onSelect: {
                                onSelectSession?(session)
                            }
                        )
                    }
                }
            }

            // Instructions or Cancel button
            if onSelectSession == nil {
                Text("Switch to the terminal tab with Claude Code and try again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Dismiss/Cancel button
            if onSelectSession != nil {
                Button(action: {
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button(action: {
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("OK")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// Row view for a single session
struct SessionRowView: View {
    let session: ClaudeSession
    let isSelectable: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            if isSelectable {
                onSelect()
            }
        }) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if let cwd = session.workingDirectory {
                        Text(cwd)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                if isSelectable {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(10)
            .background(isSelectable ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }
}

// MARK: - Alert Window Controller

class ClaudeNotInTabAlertController {
    private var window: NSWindow?

    static let shared = ClaudeNotInTabAlertController()

    private init() {}

    /// Show alert (no session selection)
    func show(
        message: String,
        sessions: [ClaudeSession],
        onDismiss: @escaping () -> Void
    ) {
        showWithSelection(
            message: message,
            sessions: sessions,
            onSelectSession: nil,
            onDismiss: onDismiss
        )
    }

    /// Show session picker (with selection callback)
    func showSessionPicker(
        message: String,
        sessions: [ClaudeSession],
        onSelectSession: @escaping (ClaudeSession) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        showWithSelection(
            message: message,
            sessions: sessions,
            onSelectSession: onSelectSession,
            onDismiss: onDismiss
        )
    }

    private func showWithSelection(
        message: String,
        sessions: [ClaudeSession],
        onSelectSession: ((ClaudeSession) -> Void)?,
        onDismiss: @escaping () -> Void
    ) {
        // Close existing window if any
        hide()

        // Create wrapped callback that hides window first
        let wrappedSelectCallback: ((ClaudeSession) -> Void)?
        if let callback = onSelectSession {
            wrappedSelectCallback = { [weak self] session in
                self?.hide()
                callback(session)
            }
        } else {
            wrappedSelectCallback = nil
        }

        let contentView = ClaudeNotInTabAlertView(
            message: message,
            sessions: sessions,
            onSelectSession: wrappedSelectCallback,
            onDismiss: { [weak self] in
                self?.hide()
                onDismiss()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        let title = onSelectSession != nil ? "Select Claude Session" : "Claude Code Alert"
        window.title = title
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Handle window close button
        window.delegate = AlertWindowCloseDelegate { [weak self] in
            self?.window = nil
            onDismiss()
        }

        self.window = window
    }

    func hide() {
        window?.close()
        window = nil
    }
}

// MARK: - Window Close Delegate

private class AlertWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

#Preview("Session Picker") {
    ClaudeNotInTabAlertView(
        message: "Found 2 Claude Code sessions. Select which one to send to:",
        sessions: [
            ClaudeSession(pid: 1234, tty: "ttys001", ttyDevice: "/dev/ttys001", terminalApp: "iTerm2", workingDirectory: "~/projects/ios/my-ios-app"),
            ClaudeSession(pid: 5678, tty: "ttys002", ttyDevice: "/dev/ttys002", terminalApp: "Terminal", workingDirectory: "~/projects/web/my-web-app")
        ],
        onSelectSession: { _ in },
        onDismiss: { }
    )
}

#Preview("Alert") {
    ClaudeNotInTabAlertView(
        message: "Claude Code is not in the active tab.",
        sessions: [
            ClaudeSession(pid: 1234, tty: "ttys001", ttyDevice: "/dev/ttys001", terminalApp: nil, workingDirectory: "~/projects/my-project")
        ],
        onSelectSession: nil,
        onDismiss: { }
    )
}
