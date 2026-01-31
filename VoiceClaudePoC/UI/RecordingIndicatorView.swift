import SwiftUI
import AppKit

/// Floating recording indicator window
struct RecordingIndicatorView: View {
    @ObservedObject var appState: AppState
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0.7 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                    value: isPulsing
                )

            // Recording label and timer
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                Text(formatDuration(appState.recordingDuration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
            }

            Spacer()

            // Stop button
            Button(action: {
                appState.stopRecording()
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 180)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 12)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        .onAppear {
            isPulsing = true
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration) % 60
        let minutes = Int(duration) / 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Visual Effect View for macOS

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat = 12

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}

// MARK: - Recording Indicator Window Controller

class RecordingIndicatorWindowController {
    private var window: NSWindow?
    private var appState: AppState?

    static let shared = RecordingIndicatorWindowController()

    private init() {}

    func show(appState: AppState) {
        // If window already exists, just show it
        if let window = window {
            window.orderFront(nil)
            return
        }

        self.appState = appState

        let contentView = RecordingIndicatorView(appState: appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false  // Let SwiftUI handle shadow
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false

        // Position in top-right corner
        positionWindow(window)

        window.orderFront(nil)
        self.window = window
    }

    func hide() {
        window?.close()
        window = nil
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        // Position in top-right corner with padding
        let x = screenFrame.maxX - windowFrame.width - 20
        let y = screenFrame.maxY - windowFrame.height - 20

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

#Preview {
    RecordingIndicatorView(appState: AppState())
        .frame(width: 200, height: 80)
}
