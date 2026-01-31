import Foundation
import Combine

/// ElevenLabs Speech-to-Text API provider
@MainActor
class ElevenLabsTranscriptionProvider: ObservableObject, TranscriptionProvider {

    // MARK: - API Response Models

    private struct TranscriptionResponse: Codable {
        let text: String
        let language_code: String?
        let language_probability: Double?
    }

    private struct ErrorResponse: Codable {
        let detail: ErrorDetail?

        struct ErrorDetail: Codable {
            let message: String?
            let status: String?
        }
    }

    private struct SubscriptionResponse: Codable {
        let character_count: Int
        let character_limit: Int
        let tier: String?
    }

    // MARK: - Properties

    let name = "ElevenLabs API"
    let description = "99 languages, high accuracy"
    let requiresAPIKey = true

    @Published private(set) var isValidatingKey = false
    @Published private(set) var apiKeyStatus: APIKeyStatus = .unknown
    @Published private(set) var characterCount: Int?
    @Published private(set) var characterLimit: Int?

    enum APIKeyStatus: Equatable {
        case unknown
        case saved
        case invalid
        case checking
    }

    var usageText: String? {
        guard let count = characterCount, let limit = characterLimit, limit > 0 else { return nil }
        let remainingPercent = Int(round(Double(limit - count) / Double(limit) * 100))
        return "\(remainingPercent)%"
    }

    private let baseURL = "https://api.elevenlabs.io/v1"
    private let model = "scribe_v1"

    // MARK: - API Key Management

    private static let apiKeyKey = "elevenLabsAPIKey"

    var apiKey: String? {
        UserDefaults.standard.string(forKey: Self.apiKeyKey)
    }

    var hasAPIKey: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }

    func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: Self.apiKeyKey)
        apiKeyStatus = .saved
    }

    func deleteAPIKey() {
        UserDefaults.standard.removeObject(forKey: Self.apiKeyKey)
        apiKeyStatus = .unknown
    }

    /// Save API key (validation happens on first transcription)
    /// ElevenLabs doesn't have a lightweight endpoint to validate STT-only keys
    func saveAndValidateAPIKey(_ key: String) async -> Bool {
        saveAPIKey(key)
        return true
    }

    /// Mark key as invalid (called when transcription fails with auth error)
    func markKeyAsInvalid() {
        apiKeyStatus = .invalid
    }

    // MARK: - Subscription Info

    /// Fetch subscription info to get character usage
    func fetchSubscription() async {
        guard let apiKey = apiKey else { return }

        guard let url = URL(string: "\(baseURL)/user/subscription") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            let subscription = try JSONDecoder().decode(SubscriptionResponse.self, from: data)
            self.characterCount = subscription.character_count
            self.characterLimit = subscription.character_limit
        } catch {
            // Silently fail - user may not have permission for this endpoint
            NSLog("ElevenLabs: Failed to fetch subscription: %@", error.localizedDescription)
        }
    }

    // MARK: - TranscriptionProvider

    func transcribe(audioURL: URL, language: String?) async throws -> String {
        guard let apiKey = apiKey else {
            throw TranscriptionError.apiKeyMissing
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound
        }

        NSLog("ElevenLabs: Transcribing with language code: %@", language ?? "auto")

        guard let url = URL(string: "\(baseURL)/speech-to-text") else {
            throw TranscriptionError.transcriptionFailed("Invalid URL")
        }

        // Read audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw TranscriptionError.invalidAudioFormat
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add model_id field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add language_code if specified
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language_code\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }

        // Disable audio event tagging (removes annotations like "(tupanie)", "(pauza)")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"tag_audio_events\"\r\n\r\n".data(using: .utf8)!)
        body.append("false\r\n".data(using: .utf8)!)

        // Add audio file
        let filename = audioURL.lastPathComponent
        let mimeType = mimeTypeForPath(audioURL.pathExtension)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Send request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.networkError(error)
        }

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.transcriptionFailed("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            markKeyAsInvalid()
            throw TranscriptionError.apiKeyInvalid
        case 429:
            throw TranscriptionError.rateLimitExceeded
        case 402:
            throw TranscriptionError.quotaExceeded
        default:
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let message = errorResponse.detail?.message {
                throw TranscriptionError.transcriptionFailed(message)
            }
            throw TranscriptionError.transcriptionFailed("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return transcriptionResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionError.transcriptionFailed("Failed to parse response")
        }
    }

    func supportedLanguages() async -> [TranscriptionLanguage] {
        // ElevenLabs Scribe v1 supported languages with excellent/high accuracy
        return Self.languages
    }

    // MARK: - Helpers

    private func mimeTypeForPath(_ ext: String) -> String {
        switch ext.lowercased() {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "ogg":
            return "audio/ogg"
        case "flac":
            return "audio/flac"
        case "webm":
            return "audio/webm"
        default:
            return "audio/wav"
        }
    }

    // MARK: - Supported Languages

    /// ElevenLabs Scribe v1 supported languages (99 languages, showing main ones)
    static let languages: [TranscriptionLanguage] = [
        // Excellent accuracy (≤5% WER)
        TranscriptionLanguage(code: "en", name: "English", nativeName: "English"),
        TranscriptionLanguage(code: "pl", name: "Polish", nativeName: "Polski"),
        TranscriptionLanguage(code: "de", name: "German", nativeName: "Deutsch"),
        TranscriptionLanguage(code: "fr", name: "French", nativeName: "Francais"),
        TranscriptionLanguage(code: "es", name: "Spanish", nativeName: "Espanol"),
        TranscriptionLanguage(code: "it", name: "Italian", nativeName: "Italiano"),
        TranscriptionLanguage(code: "pt", name: "Portuguese", nativeName: "Portugues"),
        TranscriptionLanguage(code: "nl", name: "Dutch", nativeName: "Nederlands"),
        TranscriptionLanguage(code: "ru", name: "Russian", nativeName: "Pусский"),
        TranscriptionLanguage(code: "uk", name: "Ukrainian", nativeName: "Українська"),
        TranscriptionLanguage(code: "ja", name: "Japanese", nativeName: "日本語"),
        TranscriptionLanguage(code: "zh", name: "Chinese", nativeName: "中文"),
        TranscriptionLanguage(code: "ko", name: "Korean", nativeName: "한국어"),
        TranscriptionLanguage(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt"),
        TranscriptionLanguage(code: "tr", name: "Turkish", nativeName: "Turkce"),
        TranscriptionLanguage(code: "sv", name: "Swedish", nativeName: "Svenska"),
        TranscriptionLanguage(code: "da", name: "Danish", nativeName: "Dansk"),
        TranscriptionLanguage(code: "no", name: "Norwegian", nativeName: "Norsk"),
        TranscriptionLanguage(code: "fi", name: "Finnish", nativeName: "Suomi"),
        TranscriptionLanguage(code: "cs", name: "Czech", nativeName: "Cestina"),
        TranscriptionLanguage(code: "sk", name: "Slovak", nativeName: "Slovencina"),
        TranscriptionLanguage(code: "ro", name: "Romanian", nativeName: "Romana"),
        TranscriptionLanguage(code: "bg", name: "Bulgarian", nativeName: "Български"),
        TranscriptionLanguage(code: "el", name: "Greek", nativeName: "Ελληνικά"),
        TranscriptionLanguage(code: "hu", name: "Hungarian", nativeName: "Magyar"),
        TranscriptionLanguage(code: "id", name: "Indonesian", nativeName: "Bahasa Indonesia"),
        TranscriptionLanguage(code: "ms", name: "Malay", nativeName: "Bahasa Melayu"),
        TranscriptionLanguage(code: "th", name: "Thai", nativeName: "ไทย"),
        TranscriptionLanguage(code: "hi", name: "Hindi", nativeName: "हिन्दी"),
        TranscriptionLanguage(code: "ar", name: "Arabic", nativeName: "العربية"),
        TranscriptionLanguage(code: "he", name: "Hebrew", nativeName: "עברית"),
        TranscriptionLanguage(code: "ca", name: "Catalan", nativeName: "Catala"),
    ].sorted { $0.name < $1.name }
}
