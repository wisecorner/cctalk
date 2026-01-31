import Foundation
import AppKit
import HotKey
import Carbon
import Combine

/// Manages global keyboard shortcuts for the app
class HotkeyManager: ObservableObject {

    // MARK: - Properties

    private var recordingHotKey: HotKey?
    private var keyMonitor: Any?
    private var fnMonitor: Any?

    @Published var isHotkeyRegistered = false
    @Published var currentKeyCombo: String = "⌘⇧V"
    @Published var isRecordingShortcut = false
    @Published var holdFnToRecordEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(holdFnToRecordEnabled, forKey: Self.holdFnToRecordKey)
            if holdFnToRecordEnabled {
                startFnMonitor()
            } else {
                stopFnMonitor()
            }
        }
    }

    var onHotkeyPressed: (() -> Void)?
    var onFnReleased: (() -> Void)?
    private var isFnHeld = false

    private static let holdFnToRecordKey = "holdFnToRecordEnabled"

    // MARK: - UserDefaults Keys

    private static let savedKeyCodeKey = "hotkeyKeyCode"
    private static let savedModifiersKey = "hotkeyModifiers"

    // MARK: - Default Key Combo

    static let defaultKey: Key = .v
    static let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    // MARK: - Initialization

    init() {
        // Load saved settings
        holdFnToRecordEnabled = UserDefaults.standard.bool(forKey: Self.holdFnToRecordKey)
        loadSavedHotkey()

        // Start Fn monitor if enabled
        if holdFnToRecordEnabled {
            startFnMonitor()
        }
    }

    // MARK: - Registration

    /// Register the default hotkey (⌘⇧V)
    func registerDefaultHotkey() {
        register(key: Self.defaultKey, modifiers: Self.defaultModifiers)
    }

    /// Load and register saved hotkey from UserDefaults
    func loadSavedHotkey() {
        let keyCode = UserDefaults.standard.integer(forKey: Self.savedKeyCodeKey)
        let modifiersRaw = UserDefaults.standard.integer(forKey: Self.savedModifiersKey)

        if keyCode != 0, let key = Key(carbonKeyCode: UInt32(keyCode)) {
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw))
            register(key: key, modifiers: modifiers)
        } else {
            registerDefaultHotkey()
        }
    }

    /// Save hotkey to UserDefaults
    private func saveHotkey(key: Key, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(key.carbonKeyCode), forKey: Self.savedKeyCodeKey)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: Self.savedModifiersKey)
    }

    /// Register a custom hotkey
    /// - Parameters:
    ///   - key: The key to use
    ///   - modifiers: The modifier keys (command, shift, option, control)
    ///   - save: Whether to save to UserDefaults (default: true)
    func register(key: Key, modifiers: NSEvent.ModifierFlags, save: Bool = true) {
        // Unregister existing hotkey first
        unregister()

        recordingHotKey = HotKey(key: key, modifiers: modifiers)
        recordingHotKey?.keyDownHandler = { [weak self] in
            self?.onHotkeyPressed?()
        }

        isHotkeyRegistered = true
        currentKeyCombo = formatKeyCombo(key: key, modifiers: modifiers)

        if save {
            saveHotkey(key: key, modifiers: modifiers)
        }

        print("HotkeyManager: Registered hotkey \(currentKeyCombo)")
    }

    /// Unregister the current hotkey
    func unregister() {
        recordingHotKey = nil
        isHotkeyRegistered = false
        print("HotkeyManager: Unregistered hotkey")
    }

    // MARK: - Shortcut Recording

    /// Start recording a new keyboard shortcut
    func startRecording() {
        isRecordingShortcut = true
        unregister()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordedKey(event: event)
            return nil // Consume the event
        }
    }

    /// Stop recording without changing the shortcut
    func cancelRecording() {
        stopRecordingMonitor()
        loadSavedHotkey()
    }

    /// Reset to default shortcut
    func resetToDefault() {
        stopRecordingMonitor()
        register(key: Self.defaultKey, modifiers: Self.defaultModifiers)
    }

    private func stopRecordingMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        isRecordingShortcut = false
    }

    private func handleRecordedKey(event: NSEvent) {
        // Require at least one modifier key
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !modifiers.isEmpty else { return }

        // Get the key
        guard let key = Key(carbonKeyCode: UInt32(event.keyCode)) else { return }

        // Ignore modifier-only keys
        let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Modifier key codes
        guard !modifierOnlyKeyCodes.contains(event.keyCode) else { return }

        stopRecordingMonitor()
        register(key: key, modifiers: modifiers)
    }

    // MARK: - Key Combo Formatting

    private func formatKeyCombo(key: Key, modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""

        if modifiers.contains(.control) {
            result += "⌃"
        }
        if modifiers.contains(.option) {
            result += "⌥"
        }
        if modifiers.contains(.shift) {
            result += "⇧"
        }
        if modifiers.contains(.command) {
            result += "⌘"
        }

        result += key.description.uppercased()

        return result
    }

    // MARK: - Available Keys for UI

    static let availableKeys: [(Key, String)] = [
        (.v, "V"),
        (.r, "R"),
        (.space, "Space"),
        (.m, "M"),
        (.n, "N"),
        (.b, "B")
    ]

    // MARK: - Double-Tap Fn Key

    private func startFnMonitor() {
        stopFnMonitor()

        fnMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFnFlagsChanged(event: event)
        }

        // Also monitor local events (when app is focused)
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFnFlagsChanged(event: event)
            return event
        }

        // Store reference (we'll just use fnMonitor for the global one)
        print("HotkeyManager: Started Fn double-tap monitor")
    }

    private func stopFnMonitor() {
        if let monitor = fnMonitor {
            NSEvent.removeMonitor(monitor)
            fnMonitor = nil
            print("HotkeyManager: Stopped Fn double-tap monitor")
        }
    }

    private func handleFnFlagsChanged(event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)

        // Check if ONLY Fn is pressed (no other modifiers)
        let onlyFn = event.modifierFlags.intersection([.command, .shift, .option, .control]) == []

        if fnPressed && onlyFn && !isFnHeld {
            // Fn pressed - start recording
            isFnHeld = true
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyPressed?()
            }
        } else if !fnPressed && isFnHeld {
            // Fn released - stop recording and send
            isFnHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onFnReleased?()
            }
        }
    }

    deinit {
        unregister()
        stopFnMonitor()
    }
}
