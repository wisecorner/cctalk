import SwiftUI
import Combine

/// Application-wide state management
@MainActor
class AppState: ObservableObject {

    // MARK: - Status

    enum Status: Equatable {
        case ready
        case recording
        case transcribing
        case formatting
        case sending
        case error(String)

        var displayText: String {
            switch self {
            case .ready:
                return "Ready"
            case .recording:
                return "Recording..."
            case .transcribing:
                return "Transcribing..."
            case .formatting:
                return "Formatting with AI..."
            case .sending:
                return "Sending..."
            case .error(let message):
                return "Error: \(message)"
            }
        }

        var isRecording: Bool {
            self == .recording
        }
    }

    // MARK: - Published Properties

    @Published var status: Status = .ready
    @Published var selectedTerminal: String = "Terminal" {
        didSet {
            UserDefaults.standard.set(selectedTerminal, forKey: "selectedTerminal")
        }
    }
    @Published var claudeSessions: [ClaudeSession] = []
    @Published var showClaudeNotInTabAlert: Bool = false
    @Published var alertSessions: [ClaudeSession] = []
    @Published var alertMessage: String = ""
    private var pendingTextToSend: String = "" // Text waiting for session selection
    @Published var lastTranscription: String = ""
    @Published var recordingDuration: TimeInterval = 0
    @Published var previewBeforeSend: Bool {
        didSet {
            UserDefaults.standard.set(previewBeforeSend, forKey: "previewBeforeSend")
        }
    }
    @Published var useAIFormatting: Bool {
        didSet {
            UserDefaults.standard.set(useAIFormatting, forKey: "useAIFormatting")
        }
    }
    @Published var aiFormattingPrompt: String {
        didSet {
            UserDefaults.standard.set(aiFormattingPrompt, forKey: "aiFormattingPrompt")
        }
    }
    @Published var transcriptionEngine: TranscriptionEngine {
        didSet {
            UserDefaults.standard.set(transcriptionEngine.rawValue, forKey: "transcriptionEngine")
        }
    }
    @Published var appleTranscriptionLanguage: String {
        didSet {
            UserDefaults.standard.set(appleTranscriptionLanguage, forKey: "appleTranscriptionLanguage")
        }
    }
    @Published var elevenLabsTranscriptionLanguage: String {
        didSet {
            UserDefaults.standard.set(elevenLabsTranscriptionLanguage, forKey: "elevenLabsTranscriptionLanguage")
        }
    }

    /// Current transcription language based on selected engine
    var transcriptionLanguage: String {
        get {
            switch transcriptionEngine {
            case .apple:
                return appleTranscriptionLanguage
            case .elevenLabs:
                return elevenLabsTranscriptionLanguage
            }
        }
        set {
            switch transcriptionEngine {
            case .apple:
                appleTranscriptionLanguage = newValue
            case .elevenLabs:
                elevenLabsTranscriptionLanguage = newValue
            }
        }
    }

    static let defaultAIPrompt = "Add punctuation and fix capitalization. Output ONLY the corrected text:"

    /// Languages supported by Apple Foundation Models (Apple Intelligence)
    static let foundationModelsLanguages = ["en", "de", "es", "fr", "it", "ja", "ko", "pt", "zh", "vi"]

    // MARK: - Services

    let terminalDetector = TerminalDetector()
    let keystrokeInjector = KeystrokeInjector()
    let audioRecorder = AudioRecorder()
    let speechAnalyzerService = SpeechAnalyzerService()
    let foundationModelsService = FoundationModelsService()
    let hotkeyManager = HotkeyManager()
    let errorLogger = ErrorLoggingService.shared
    let feedbackService = FeedbackService()

    // Transcription providers
    let appleTranscriptionProvider = AppleTranscriptionProvider()
    let elevenLabsTranscriptionProvider = ElevenLabsTranscriptionProvider()

    // MARK: - Private State

    private var currentRecordingURL: URL?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var canInject: Bool {
        !claudeSessions.isEmpty && status == .ready
    }

    var isRecording: Bool {
        status.isRecording
    }

    var canRecord: Bool {
        switch status {
        case .ready, .error:
            return true
        default:
            return false
        }
    }

    var hasError: Bool {
        if case .error = status {
            return true
        }
        return false
    }

    /// Clear error state and return to ready
    func clearError() {
        if case .error = status {
            status = .ready
        }
    }

    /// Set error status and log to file
    private func setError(_ message: String, context: String? = nil) {
        status = .error(message)
        errorLogger.logError(message, context: context)
    }

    // MARK: - Initialization

    init() {
        // Load settings from UserDefaults
        self.previewBeforeSend = UserDefaults.standard.bool(forKey: "previewBeforeSend")
        self.useAIFormatting = UserDefaults.standard.object(forKey: "useAIFormatting") as? Bool ?? true
        self.aiFormattingPrompt = UserDefaults.standard.string(forKey: "aiFormattingPrompt") ?? AppState.defaultAIPrompt

        // Load transcription settings
        if let engineRaw = UserDefaults.standard.string(forKey: "transcriptionEngine"),
           let engine = TranscriptionEngine(rawValue: engineRaw) {
            self.transcriptionEngine = engine
        } else {
            self.transcriptionEngine = .apple
        }
        self.appleTranscriptionLanguage = UserDefaults.standard.string(forKey: "appleTranscriptionLanguage") ?? "en_US"
        self.elevenLabsTranscriptionLanguage = UserDefaults.standard.string(forKey: "elevenLabsTranscriptionLanguage") ?? "en"

        // Load selected terminal, defaulting to first installed
        if let savedTerminal = UserDefaults.standard.string(forKey: "selectedTerminal"),
           TerminalDetector.installedTerminals.contains(savedTerminal) {
            self.selectedTerminal = savedTerminal
        } else if let firstInstalled = TerminalDetector.installedTerminals.first {
            self.selectedTerminal = firstInstalled
        }

        setupBindings()
        setupHotkey()

        // Check Claude status on startup
        Task {
            checkClaudeStatus()
        }

        // Check if feedback popup should be shown
        feedbackService.checkShouldShowPopup()
    }

    private func setupBindings() {
        // Bind recording duration from AudioRecorder
        audioRecorder.$recordingDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)
    }

    private func setupHotkey() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        hotkeyManager.onFnReleased = { [weak self] in
            Task { @MainActor in
                // Only stop if we're currently recording (for hold-to-record mode)
                if self?.isRecording == true {
                    self?.stopRecording()
                }
            }
        }
        // HotkeyManager loads saved hotkey in init(), no need to register here
    }

    // MARK: - Claude Detection

    func checkClaudeStatus() {
        Task {
            let result: ([ClaudeSession], [ClaudeSession]) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else {
                        continuation.resume(returning: ([], []))
                        return
                    }

                    let all = self.terminalDetector.getClaudeSessions()
                    let filtered = self.terminalDetector.getFilteredClaudeSessions(terminal: self.selectedTerminal)

                    continuation.resume(returning: (filtered, all))
                }
            }

            let (filteredSessions, allSessions) = result
            claudeSessions = filteredSessions

            if filteredSessions.isEmpty && status == .ready {
                if allSessions.isEmpty {
                    print("AppState: No Claude sessions found")
                } else {
                    print("AppState: Claude running in other terminal (\(allSessions.count) sessions), but not in \(selectedTerminal)")
                }
            }
        }
    }

    /// Validates injection before sending
    private func validateBeforeSend() -> InjectionValidation {
        return terminalDetector.validateInjection(terminal: selectedTerminal)
    }

    // MARK: - Recording Flow

    func startRecording() {
        guard canRecord else { return }

        // Clear any previous error
        clearError()

        // Check if Claude is running in selected terminal BEFORE recording
        // This filters sessions to the selected terminal without activating windows
        let sessions = terminalDetector.getFilteredClaudeSessions(terminal: selectedTerminal)
        if sessions.isEmpty {
            showNoClaudeAlert()
            return
        }

        // Check and request microphone permission
        if !audioRecorder.checkPermission() {
            Task {
                let granted = await audioRecorder.requestPermission()
                if granted {
                    doStartRecording()
                } else {
                    setError("Microphone permission denied. Grant access in System Settings → Privacy & Security → Microphone", context: "startRecording")
                }
            }
        } else {
            doStartRecording()
        }
    }

    private func doStartRecording() {
        do {
            // AVAudioEngine automatically uses the system's default input device
            currentRecordingURL = try audioRecorder.startRecording()
            status = .recording
            // Show floating recording indicator
            RecordingIndicatorWindowController.shared.show(appState: self)
        } catch {
            setError("Recording failed: \(error.localizedDescription)", context: "doStartRecording")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        // Hide floating recording indicator
        RecordingIndicatorWindowController.shared.hide()

        guard let recordingURL = audioRecorder.stopRecording() else {
            setError("No recording to process", context: "stopRecording")
            return
        }

        currentRecordingURL = recordingURL
        transcribeAndSend(audioURL: recordingURL)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Transcription

    /// Get the current transcription provider based on settings
    private var currentTranscriptionProvider: TranscriptionProvider {
        switch transcriptionEngine {
        case .apple:
            return appleTranscriptionProvider
        case .elevenLabs:
            return elevenLabsTranscriptionProvider
        }
    }

    /// Check if current language is supported by Foundation Models
    private var isLanguageSupportedByFoundationModels: Bool {
        let langCode = String(transcriptionLanguage.prefix(2)).lowercased()
        return Self.foundationModelsLanguages.contains(langCode)
    }

    private func transcribeAndSend(audioURL: URL) {
        status = .transcribing

        Task {
            do {
                // Use selected transcription provider
                var text = try await currentTranscriptionProvider.transcribe(
                    audioURL: audioURL,
                    language: transcriptionLanguage
                )

                // Clean up recording file
                audioRecorder.deleteRecording(at: audioURL)
                currentRecordingURL = nil

                if text.isEmpty {
                    setError("No speech detected", context: "transcribeAndSend")
                    return
                }

                // Apply AI formatting if enabled AND language is supported
                // Foundation Models only supports: EN, DE, ES, FR, IT, JA, KO, PT, ZH, VI
                let shouldUseAIFormatting = useAIFormatting
                    && foundationModelsService.isAvailable
                    && isLanguageSupportedByFoundationModels

                if shouldUseAIFormatting {
                    status = .formatting
                    do {
                        text = try await foundationModelsService.formatTranscription(text, customPrompt: aiFormattingPrompt)
                    } catch {
                        // If formatting fails, continue with original text
                        print("AI formatting failed: \(error.localizedDescription)")
                    }
                }

                lastTranscription = text

                // Show preview or auto-send
                if previewBeforeSend {
                    status = .ready
                    showPreviewWindow(text: text)
                } else {
                    // Auto-send to Claude
                    await sendToClaudeWithRetry(text: text)
                }
            } catch {
                setError("Transcription failed: \(error.localizedDescription)", context: "transcribeAndSend")
                // Clean up recording file even on error
                audioRecorder.deleteRecording(at: audioURL)
                currentRecordingURL = nil
            }
        }
    }

    private func showPreviewWindow(text: String) {
        PreviewPromptWindowController.shared.show(
            transcribedText: text,
            onSend: { [weak self] editedText in
                guard let self = self else { return }
                self.lastTranscription = editedText
                Task { @MainActor in
                    await self.sendToClaudeWithRetry(text: editedText)
                }
            },
            onCancel: { [weak self] in
                self?.status = .ready
            }
        )
    }

    private func sendToClaudeWithRetry(text: String) async {
        // Refresh Claude sessions first
        checkClaudeStatus()
        try? await Task.sleep(nanoseconds: 300_000_000) // Wait for check to complete

        // Validate and send
        sendPromptWithValidation(text)
    }

    // MARK: - Prompt Sending

    /// Send prompt with validation (recommended)
    func sendPromptWithValidation(_ text: String) {
        let validation = validateBeforeSend()

        switch validation {
        case .ready:
            // Claude is in active tab - proceed
            doSendPrompt(text, validation: validation)

        case .cannotVerifyTab(let session):
            // Terminal doesn't support tab detection but Claude is running
            // Trust the user and proceed - they have the terminal active
            doSendPrompt(text, validation: .ready(session: session))

        case .noClaudeRunning:
            setError("Claude Code is not running in any terminal", context: "sendPromptWithValidation")
            showNoClaudeAlert()

        case .claudeNotInActiveTab(let sessions):
            if sessions.count > 1 {
                // Multiple sessions - show picker
                pendingTextToSend = text
                alertMessage = "Claude Code is not in the active tab. Select a session:"
                alertSessions = sessions
                showClaudeNotInTabAlert = true
                status = .ready
                showSessionPickerWindow(sessions: sessions)
            } else if sessions.count == 1 {
                // Single session - auto-switch for Terminal.app
                if selectedTerminal == "Terminal", let session = sessions.first {
                    if terminalDetector.switchTerminalAppToTab(withTTY: session.tty) {
                        doSendPrompt(text, validation: .ready(session: session))
                        return
                    }
                }
                // Show alert
                alertMessage = "Claude Code is not in the active tab. Switch to the tab with Claude and try again."
                alertSessions = sessions
                showClaudeNotInTabAlert = true
                status = .ready
                showClaudeNotInTabAlertWindow()
            }

        case .terminalNotActive(let expected, let actual):
            if let actual = actual {
                setError("Terminal \(expected) is not active (active app: \(actual))", context: "sendPromptWithValidation")
            } else {
                setError("Terminal \(expected) is not active", context: "sendPromptWithValidation")
            }

        case .multipleSessionsFound(let sessions):
            // Multiple Claude sessions - show picker
            pendingTextToSend = text
            alertMessage = "Found \(sessions.count) Claude Code sessions. Select which one to send to:"
            alertSessions = sessions
            showClaudeNotInTabAlert = true
            status = .ready
            showSessionPickerWindow(sessions: sessions)
        }
    }

    /// Show session picker for multiple sessions
    private func showSessionPickerWindow(sessions: [ClaudeSession]) {
        ClaudeNotInTabAlertController.shared.showSessionPicker(
            message: alertMessage,
            sessions: sessions,
            onSelectSession: { [weak self] selectedSession in
                guard let self = self else { return }
                self.dismissClaudeNotInTabAlert()
                // Send to selected session
                self.sendToSession(self.pendingTextToSend, session: selectedSession)
            },
            onDismiss: { [weak self] in
                self?.dismissClaudeNotInTabAlert()
                self?.pendingTextToSend = ""
            }
        )
    }

    /// Send text to a specific session (switch tab if needed for Terminal.app)
    private func sendToSession(_ text: String, session: ClaudeSession) {
        // For Terminal.app, switch to the correct tab first
        if selectedTerminal == "Terminal" {
            _ = terminalDetector.switchTerminalAppToTab(withTTY: session.tty)
        }

        // Proceed with sending
        doSendPrompt(text, validation: .ready(session: session))
    }

    /// Legacy send without validation (for backward compatibility)
    func sendPrompt(_ text: String) {
        guard !claudeSessions.isEmpty else {
            setError("No Claude session found", context: "sendPrompt")
            return
        }

        doSendPrompt(text, validation: .ready(session: claudeSessions.first!))
    }

    private func doSendPrompt(_ text: String, validation: InjectionValidation) {
        status = .sending

        keystrokeInjector.injectPromptWithValidation(text, terminal: selectedTerminal, validation: validation) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.status = .ready
                    // Save to history
                    PromptHistoryService.shared.addPrompt(text: text, terminal: self.selectedTerminal)
                    // Track usage for feedback popup
                    self.feedbackService.incrementUsageCount()
                case .failure(let error):
                    self.handleInjectionError(error)
                }
            }
        }
    }

    private func handleInjectionError(_ error: KeystrokeInjector.InjectionError) {
        switch error {
        case .claudeNotInActiveTab(let sessions):
            // This shouldn't happen as validation is done before injection
            // But handle it gracefully
            if sessions.count > 1 {
                alertMessage = "Claude Code is not in the active tab. Select a session:"
                alertSessions = sessions
                showClaudeNotInTabAlert = true
                status = .ready
                showSessionPickerWindow(sessions: sessions)
            } else {
                alertMessage = "Claude Code is not in the active tab."
                alertSessions = sessions
                showClaudeNotInTabAlert = true
                status = .ready
                showClaudeNotInTabAlertWindow()
            }

        case .terminalNotActive(let expected, let actual):
            if let actual = actual {
                setError("Terminal \(expected) is not active (active app: \(actual))", context: "keystrokeInjection")
            } else {
                setError("Terminal \(expected) is not active", context: "keystrokeInjection")
            }

        case .noClaudeRunning:
            setError("Claude Code is not running", context: "keystrokeInjection")

        case .cannotVerifyTab:
            setError("Cannot verify if Claude is in the active tab", context: "keystrokeInjection")

        case .scriptExecutionFailed(let message):
            setError("Script error: \(message)", context: "keystrokeInjection")

        case .processLaunchFailed(let error):
            setError("Launch error: \(error.localizedDescription)", context: "keystrokeInjection")
        }
    }

    /// Dismiss the Claude not in tab alert
    func dismissClaudeNotInTabAlert() {
        showClaudeNotInTabAlert = false
        alertSessions = []
        alertMessage = ""
    }

    /// Show the Claude not in tab alert window
    private func showClaudeNotInTabAlertWindow() {
        ClaudeNotInTabAlertController.shared.show(
            message: alertMessage,
            sessions: alertSessions,
            onDismiss: { [weak self] in
                self?.dismissClaudeNotInTabAlert()
            }
        )
    }

    /// Show alert when Claude is not running
    private func showNoClaudeAlert() {
        let alert = NSAlert()
        alert.messageText = "Claude Code is not running"
        alert.informativeText = "Start Claude Code in \(selectedTerminal) before recording.\n\nType 'claude' in terminal to start."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func resendLastTranscription() {
        guard !lastTranscription.isEmpty else { return }
        sendPrompt(lastTranscription)
    }

    // MARK: - Microphone Permission

    func requestMicrophonePermission() async -> Bool {
        await audioRecorder.requestPermission()
    }

    func hasMicrophonePermission() -> Bool {
        audioRecorder.checkPermission()
    }
}
