//
//  FeedbackService.swift
//  VoiceClaudePoC
//
//  Manages feedback collection, usage tracking, and automatic popup logic.
//

import Combine
import Foundation

/// Service for collecting and sending user feedback
@MainActor
class FeedbackService: ObservableObject {

    // MARK: - Constants

    private enum Keys {
        static let usageCount = "feedbackUsageCount"
        static let lastPopupDate = "feedbackLastPopupDate"
        static let dismissedPopupDate = "feedbackDismissedPopupDate"
        static let deviceId = "feedbackDeviceId"
        static let recentHashes = "feedbackRecentHashes"
    }

    nonisolated private static let usageThreshold = 10
    nonisolated private static let popupIntervalDays = 7
    nonisolated private static let maxRecentHashes = 5
    nonisolated static let minFeedbackLength = 10
    nonisolated static let maxFeedbackLength = 5000

    // API Configuration
    private static let feedbackEndpoint = "https://wisecorner.com/api/feedback"
    // Token is injected during CI build from CCTALK_FEEDBACK_TOKEN secret
    // Placeholder: __FEEDBACK_TOKEN_PLACEHOLDER__ is replaced by workflow
    private static let appToken = "cctalk-__FEEDBACK_TOKEN_PLACEHOLDER__"

    // MARK: - Published Properties

    @Published var shouldShowPopup = false
    @Published var isSending = false
    @Published var lastError: String?
    @Published var lastSuccessIssueNumber: Int?

    // MARK: - Computed Properties

    var usageCount: Int {
        UserDefaults.standard.integer(forKey: Keys.usageCount)
    }

    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: Keys.deviceId) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: Keys.deviceId)
        return newId
    }

    var canSubmitFeedback: Bool {
        !isSending
    }

    // MARK: - Usage Tracking

    /// Increment usage count after successful dictation
    func incrementUsageCount() {
        let current = usageCount
        UserDefaults.standard.set(current + 1, forKey: Keys.usageCount)
    }

    /// Reset usage count (after feedback submitted)
    func resetUsageCount() {
        UserDefaults.standard.set(0, forKey: Keys.usageCount)
    }

    // MARK: - Popup Logic

    /// Check if automatic feedback popup should be shown
    func checkShouldShowPopup() {
        // Check usage threshold
        guard usageCount >= Self.usageThreshold else {
            shouldShowPopup = false
            return
        }

        // Check time since last popup or dismissal
        let lastPopup = UserDefaults.standard.object(forKey: Keys.lastPopupDate) as? Date
        let lastDismissed = UserDefaults.standard.object(forKey: Keys.dismissedPopupDate) as? Date

        let referenceDate = [lastPopup, lastDismissed].compactMap { $0 }.max()

        if let reference = referenceDate {
            let daysSince = Calendar.current.dateComponents([.day], from: reference, to: Date()).day ?? 0
            guard daysSince >= Self.popupIntervalDays else {
                shouldShowPopup = false
                return
            }
        }

        // All conditions met - show popup after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.shouldShowPopup = true
            UserDefaults.standard.set(Date(), forKey: Keys.lastPopupDate)
        }
    }

    /// Record that user dismissed popup without sending feedback
    func recordPopupDismissed() {
        shouldShowPopup = false
        UserDefaults.standard.set(Date(), forKey: Keys.dismissedPopupDate)
    }

    /// Record that feedback was submitted
    func recordFeedbackSubmitted() {
        shouldShowPopup = false
        resetUsageCount()
        UserDefaults.standard.set(Date(), forKey: Keys.lastPopupDate)
    }

    // MARK: - Duplicate Detection

    /// Check if feedback is duplicate of recent submissions
    func isDuplicateFeedback(_ text: String) -> Bool {
        let hash = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).hashValue
        let recentHashes = UserDefaults.standard.array(forKey: Keys.recentHashes) as? [Int] ?? []
        return recentHashes.contains(hash)
    }

    /// Add feedback hash to recent list
    private func recordFeedbackHash(_ text: String) {
        let hash = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).hashValue
        var recentHashes = UserDefaults.standard.array(forKey: Keys.recentHashes) as? [Int] ?? []

        // Add new hash and trim to max size
        recentHashes.append(hash)
        if recentHashes.count > Self.maxRecentHashes {
            recentHashes.removeFirst(recentHashes.count - Self.maxRecentHashes)
        }

        UserDefaults.standard.set(recentHashes, forKey: Keys.recentHashes)
    }

    // MARK: - Validation

    enum ValidationError: LocalizedError {
        case tooShort
        case tooLong
        case duplicate

        var errorDescription: String? {
            switch self {
            case .tooShort:
                return "Feedback must be at least \(FeedbackService.minFeedbackLength) characters"
            case .tooLong:
                return "Feedback must be less than \(FeedbackService.maxFeedbackLength) characters"
            case .duplicate:
                return "You've already submitted similar feedback recently"
            }
        }
    }

    func validateFeedback(_ text: String) -> ValidationError? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count < Self.minFeedbackLength {
            return .tooShort
        }

        if trimmed.count > Self.maxFeedbackLength {
            return .tooLong
        }

        if isDuplicateFeedback(trimmed) {
            return .duplicate
        }

        return nil
    }

    // MARK: - Submit Feedback

    enum SubmitResult {
        case success(issueNumber: Int)
        case error(String)
    }

    /// Submit feedback to API
    func submitFeedback(_ text: String) async -> SubmitResult {
        // Validate
        if let error = validateFeedback(text) {
            lastError = error.localizedDescription
            return .error(error.localizedDescription)
        }

        isSending = true
        lastError = nil

        defer {
            Task { @MainActor in
                isSending = false
            }
        }

        // Prepare request
        guard let url = URL(string: Self.feedbackEndpoint) else {
            let error = "Invalid API endpoint"
            lastError = error
            return .error(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.appToken, forHTTPHeaderField: "X-App-Token")
        request.timeoutInterval = 30

        // Get app and system info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let body: [String: Any] = [
            "feedback": text.trimmingCharacters(in: .whitespacesAndNewlines),
            "appVersion": appVersion,
            "macOSVersion": macOSVersion,
            "deviceId": deviceId,
            "usageCount": usageCount
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            let errorMessage = "Failed to encode request"
            lastError = errorMessage
            return .error(errorMessage)
        }

        // Send request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = "Invalid response"
                lastError = error
                return .error(error)
            }

            // Parse response
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            switch httpResponse.statusCode {
            case 201:
                // Success
                if let issueNumber = json?["issueNumber"] as? Int {
                    recordFeedbackHash(text)
                    recordFeedbackSubmitted()
                    lastSuccessIssueNumber = issueNumber
                    return .success(issueNumber: issueNumber)
                } else {
                    recordFeedbackHash(text)
                    recordFeedbackSubmitted()
                    return .success(issueNumber: 0)
                }

            case 400:
                let errorMessage = json?["error"] as? String ?? "Invalid request"
                lastError = errorMessage
                return .error(errorMessage)

            case 401:
                let error = "Authentication failed"
                lastError = error
                return .error(error)

            case 429:
                let error = json?["error"] as? String ?? "Rate limit exceeded. Try again tomorrow."
                lastError = error
                return .error(error)

            default:
                let error = json?["error"] as? String ?? "Server error (\(httpResponse.statusCode))"
                lastError = error
                return .error(error)
            }

        } catch let error as URLError {
            let errorMessage: String
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                errorMessage = "No internet connection. Please check your network."
            case .timedOut:
                errorMessage = "Request timed out. Please try again."
            default:
                errorMessage = "Network error: \(error.localizedDescription)"
            }
            lastError = errorMessage
            return .error(errorMessage)

        } catch {
            let errorMessage = "Unexpected error: \(error.localizedDescription)"
            lastError = errorMessage
            return .error(errorMessage)
        }
    }
}
