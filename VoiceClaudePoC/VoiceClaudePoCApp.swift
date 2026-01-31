import SwiftUI
import AppKit
import SwiftData
import Combine

@main
struct VoiceClaudePoCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var permissions = PermissionsHelper()
    @StateObject private var historyService = PromptHistoryService.shared

    let modelContainer: ModelContainer

    init() {
        do {
            let container = try ModelContainer(for: PromptHistory.self)
            modelContainer = container
            // Set up history service with model context on main actor
            Task { @MainActor in
                PromptHistoryService.shared.setModelContext(container.mainContext)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        // Menu Bar App
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(permissions)
                .environmentObject(historyService)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarIcon)
                if appState.isRecording {
                    Text(formatDuration(appState.recordingDuration))
                        .monospacedDigit()
                        .font(.caption)
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Settings Window
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(permissions)
                .onReceive(appState.feedbackService.$shouldShowPopup) { shouldShow in
                    if shouldShow {
                        FeedbackWindowController.shared.show(
                            feedbackService: appState.feedbackService,
                            isAutoPopup: true
                        )
                    }
                }
        }
    }

    // MARK: - Menu Bar Icon

    private var menuBarIcon: String {
        switch appState.status {
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        case .formatting:
            return "sparkles"
        case .sending:
            return "paperplane.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        default:
            return "mic"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration) % 60
        let minutes = Int(duration) / 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionsHelper()
    private var onboardingWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var lowerObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure Sparkle updater
        UpdaterManager.shared.configure()

        // Check permissions and show onboarding if needed
        permissions.checkAllPermissions()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            // Show onboarding if not completed or permissions not granted
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
            if !onboardingCompleted || !self.permissions.allPermissionsGranted {
                self.showOnboardingWindow()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Notify to refresh permission status
        NotificationCenter.default.post(name: .refreshPermissions, object: nil)
    }

    func showOnboardingWindow() {
        // If window already exists, just show it
        if let window = onboardingWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window with OnboardingView
        let contentView = OnboardingView {
            // Post notification to close window safely
            NotificationCenter.default.post(name: .closeOnboarding, object: nil)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CCTalk Setup"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating  // Keep window on top
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window

        // Listen for close notification (remove existing observer first)
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: .closeOnboarding,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeOnboardingWindow()
        }

        // Listen for lower window notification (for system prompts)
        if let observer = lowerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        lowerObserver = NotificationCenter.default.addObserver(
            forName: .lowerOnboardingWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onboardingWindow?.level = .normal
        }
    }

    private func closeOnboardingWindow() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        onboardingWindow?.close()
        onboardingWindow = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let refreshPermissions = Notification.Name("refreshPermissions")
    static let closeOnboarding = Notification.Name("closeOnboarding")
    static let lowerOnboardingWindow = Notification.Name("lowerOnboardingWindow")
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissions: PermissionsHelper
    @StateObject private var errorLogger = ErrorLoggingService.shared

    /// Show badge when ElevenLabs is used (has language compatibility info)
    private var showAIFormattingBadge: Bool {
        appState.transcriptionEngine == .elevenLabs
    }

    var body: some View {
        TabView {
            // General Tab
            GeneralSettingsTab(hotkeyManager: appState.hotkeyManager)
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            // Transcription Tab
            TranscriptionSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }

            // AI Formatting Tab
            AIFormattingSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label(showAIFormattingBadge ? "AI Formatting ⚠" : "AI Formatting", systemImage: "sparkles")
                }

            // Permissions Tab
            PermissionsSettingsTab()
                .environmentObject(permissions)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            // Error Log Tab
            ErrorLogSettingsTab()
                .environmentObject(errorLogger)
                .tabItem {
                    Label("Error Log", systemImage: "exclamationmark.triangle")
                }

            // Feedback Tab
            FeedbackSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Feedback", systemImage: "bubble.left.and.bubble.right")
                }
        }
        .frame(width: 450, height: 400)
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var hotkeyManager: HotkeyManager

    var body: some View {
        ScrollView {
            Form {
                Section("Keyboard Shortcut") {
                    HStack {
                        Text("Hotkey:")
                        Spacer()

                        if hotkeyManager.isRecordingShortcut {
                            Text("Press shortcut...")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        } else {
                            Text(hotkeyManager.currentKeyCombo)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                    HStack {
                        if hotkeyManager.isRecordingShortcut {
                            Button("Cancel") {
                                hotkeyManager.cancelRecording()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Record Shortcut") {
                                hotkeyManager.startRecording()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reset to Default") {
                                hotkeyManager.resetToDefault()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text("Default: ⌘⇧V. Click Record and press your desired key combination.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle(isOn: $hotkeyManager.holdFnToRecordEnabled) {
                        VStack(alignment: .leading) {
                            Text("Hold Fn to record")
                            Text("Hold Fn key to record, release to send")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Terminal") {
                    Picker("Terminal:", selection: $appState.selectedTerminal) {
                        ForEach(TerminalDetector.availableTerminals, id: \.self) { terminal in
                            Text(terminal).tag(terminal)
                        }
                    }
                }

                Section("Options") {
                    Toggle("Preview before sending", isOn: $appState.previewBeforeSend)

                    Text("When enabled, you can review and edit the transcription before sending to Claude.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }
}

// MARK: - Transcription Settings Tab

struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isValidating: Bool = false
    @State private var validationMessage: String?
    @State private var availableLanguages: [TranscriptionLanguage] = []

    var body: some View {
        ScrollView {
            Form {
                // Engine Selection
                Section("Transcription Engine") {
                    Picker("Engine", selection: $appState.transcriptionEngine) {
                        ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                            VStack(alignment: .leading) {
                                Text(engine.displayName)
                                Text(engine.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(engine)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: appState.transcriptionEngine) { _, _ in
                        loadLanguages()
                    }
                }

                // Language Selection
                Section("Language") {
                    Picker("Transcription Language", selection: currentLanguageBinding) {
                        ForEach(availableLanguages) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }

                    // Warning about AI Formatting support
                    if !isLanguageSupportedByAI {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                            Text("AI Formatting is not available for this language. Text will be sent without formatting.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ElevenLabs API Key (only if ElevenLabs selected)
                if appState.transcriptionEngine == .elevenLabs {
                    Section("ElevenLabs API") {
                        HStack {
                            if showAPIKey {
                                TextField("API Key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("API Key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showAPIKey.toggle() }) {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack {
                            // Status indicator
                            apiKeyStatusView

                            Spacer()

                            // Save button
                            Button(action: saveAPIKey) {
                                if isValidating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Save Key")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKey.isEmpty || isValidating)

                            // Delete button
                            if appState.elevenLabsTranscriptionProvider.hasAPIKey {
                                Button(action: deleteAPIKey) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }

                        if let message = validationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Get your API key from [elevenlabs.io](https://elevenlabs.io)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                }

                // Info Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Formatting Languages", systemImage: "sparkles")
                            .font(.headline)

                        Text("Apple Intelligence supports: English, German, Spanish, French, Italian, Japanese, Korean, Portuguese, Chinese, Vietnamese")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("For other languages, transcription will be sent directly without AI formatting.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .onAppear {
            loadAPIKey()
            loadLanguages()
        }
    }

    // MARK: - Computed Properties

    private var currentLanguageBinding: Binding<String> {
        Binding(
            get: {
                switch appState.transcriptionEngine {
                case .apple:
                    return appState.appleTranscriptionLanguage
                case .elevenLabs:
                    return appState.elevenLabsTranscriptionLanguage
                }
            },
            set: { newValue in
                switch appState.transcriptionEngine {
                case .apple:
                    appState.appleTranscriptionLanguage = newValue
                case .elevenLabs:
                    appState.elevenLabsTranscriptionLanguage = newValue
                }
            }
        )
    }

    private var isLanguageSupportedByAI: Bool {
        let langCode = String(appState.transcriptionLanguage.prefix(2)).lowercased()
        return AppState.foundationModelsLanguages.contains(langCode)
    }

    @ViewBuilder
    private var apiKeyStatusView: some View {
        switch appState.elevenLabsTranscriptionProvider.apiKeyStatus {
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .invalid:
            Label("Invalid key", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        case .checking:
            Label("Saving...", systemImage: "hourglass")
                .foregroundColor(.orange)
                .font(.caption)
        case .unknown:
            Label("Not configured", systemImage: "key")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Methods

    private func loadAPIKey() {
        if let key = appState.elevenLabsTranscriptionProvider.apiKey {
            apiKey = key
        }
    }

    private func loadLanguages() {
        Task {
            switch appState.transcriptionEngine {
            case .apple:
                availableLanguages = await appState.appleTranscriptionProvider.supportedLanguages()
            case .elevenLabs:
                availableLanguages = await appState.elevenLabsTranscriptionProvider.supportedLanguages()
            }

            // Ensure current language is in the list, or reset to English
            if !availableLanguages.contains(where: { $0.code == appState.transcriptionLanguage }) {
                if let english = availableLanguages.first(where: { $0.code.hasPrefix("en") }) {
                    appState.transcriptionLanguage = english.code
                } else if let first = availableLanguages.first {
                    appState.transcriptionLanguage = first.code
                }
            }
        }
    }

    private func saveAPIKey() {
        appState.elevenLabsTranscriptionProvider.saveAPIKey(apiKey)
        validationMessage = "API key saved. It will be validated on first transcription."
    }

    private func deleteAPIKey() {
        appState.elevenLabsTranscriptionProvider.deleteAPIKey()
        apiKey = ""
        validationMessage = nil
    }
}

// MARK: - AI Formatting Settings Tab

struct AIFormattingSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            Form {
                Section {
                    Toggle("Format transcription with AI", isOn: $appState.useAIFormatting)

                    Text("Uses on-device Apple Intelligence to add punctuation, capitalization, and improve readability.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Status:")
                        Spacer()
                        if appState.foundationModelsService.isAvailable {
                            Label("Available", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label(appState.foundationModelsService.availabilityMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }

                // Language support info for ElevenLabs users
                if appState.transcriptionEngine == .elevenLabs {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Supported Languages")
                                    .font(.headline)

                                Text("AI Formatting works only with these transcription languages:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("English, German, Spanish, French, Italian, Japanese, Korean, Portuguese, Chinese, Vietnamese")
                                    .font(.caption)
                                    .fontWeight(.medium)

                                Text("For other languages, transcription will be sent without AI formatting.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if appState.useAIFormatting {
                    Section("Custom Prompt") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Edit the prompt used to format transcriptions:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Reset") {
                                    appState.aiFormattingPrompt = AppState.defaultAIPrompt
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            TextEditor(text: $appState.aiFormattingPrompt)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 100)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )

                            Text("Use {TEXT} as placeholder for the transcribed text, or the text will be appended at the end.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }
}

// MARK: - Permissions Settings Tab

struct PermissionsSettingsTab: View {
    @EnvironmentObject var permissions: PermissionsHelper

    var body: some View {
        Form {
            Section {
                // Microphone
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    permissionBadge(for: permissions.microphoneStatus)
                    if permissions.microphoneStatus != .granted {
                        Button("Fix") {
                            permissions.openMicrophoneSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Accessibility
                HStack {
                    Label("Accessibility", systemImage: "accessibility")
                    Spacer()
                    permissionBadge(for: permissions.accessibilityStatus)
                    if permissions.accessibilityStatus != .granted {
                        Button("Fix") {
                            permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section {
                Button(action: {
                    permissions.checkAllPermissions()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Permissions")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            permissions.checkAllPermissions()
        }
    }

    @ViewBuilder
    private func permissionBadge(for status: PermissionsHelper.PermissionStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .notDetermined:
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.orange)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Error Log Settings Tab

struct ErrorLogSettingsTab: View {
    @EnvironmentObject var errorLogger: ErrorLoggingService

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                Text("\(errorLogger.errors.count) error(s) logged")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    errorLogger.clearErrors()
                }) {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(errorLogger.errors.isEmpty)
            }
            .padding()

            Divider()

            // Error list
            if errorLogger.errors.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("No errors logged")
                        .font(.headline)
                    Text("Errors will appear here when they occur")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(errorLogger.errors) { error in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(error.formattedTimestamp)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let context = error.context {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(context)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Text(error.message)
                            .font(.callout)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Feedback Settings Tab

struct FeedbackSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            Form {
                Section("Usage Statistics") {
                    HStack {
                        Text("Dictations since last feedback:")
                        Spacer()
                        Text("\(appState.feedbackService.usageCount)")
                            .fontWeight(.medium)
                    }

                    Text("After 10 dictations, you'll be prompted to share feedback to help improve CCTalk.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Send Feedback") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your feedback helps us make CCTalk better! Share your thoughts, suggestions, or report any issues you've encountered.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button(action: {
                            FeedbackWindowController.shared.show(feedbackService: appState.feedbackService)
                        }) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                Text("Send Feedback")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("About Feedback") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Anonymous", systemImage: "person.fill.questionmark")
                            .font(.subheadline)
                        Text("We only collect app version, macOS version, and an anonymous device ID.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Label("Rate Limited", systemImage: "clock")
                            .font(.subheadline)
                        Text("Maximum 3 feedback submissions per day.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Label("GitHub Issues", systemImage: "checkmark.circle")
                            .font(.subheadline)
                        Text("Feedback is submitted as GitHub issues for transparent tracking.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }
}
