import Foundation
import AVFoundation
import AppKit
import ApplicationServices
import Combine

/// Helper for checking and requesting system permissions
class PermissionsHelper: ObservableObject {

    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
        case unknown
    }

    // MARK: - Published State

    @Published private(set) var microphoneStatus: PermissionStatus = .unknown
    @Published private(set) var accessibilityStatus: PermissionStatus = .unknown

    // MARK: - Computed Properties

    var allPermissionsGranted: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }

    var needsOnboarding: Bool {
        !allPermissionsGranted
    }

    // MARK: - Check All Permissions

    func checkAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
    }

    // MARK: - Microphone Permission

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    func requestMicrophonePermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        await MainActor.run {
            microphoneStatus = granted ? .granted : .denied
        }
        return granted
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        // Check if we have accessibility permissions
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    func requestAccessibilityPermission() {
        // Open System Settings to Accessibility pane
        // This will also trigger the permission prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Recheck after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }

    // MARK: - Open System Settings

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
