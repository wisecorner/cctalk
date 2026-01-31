import Foundation

/// Represents a language supported by a transcription provider
struct TranscriptionLanguage: Identifiable, Hashable, Codable {
    let code: String       // ISO code: "pl", "en", "de"
    let name: String       // English name: "Polish", "English", "German"
    let nativeName: String // Native name: "Polski", "English", "Deutsch"

    var id: String { code }

    /// Display name combining native and English names
    var displayName: String {
        if nativeName == name {
            return name
        }
        return "\(nativeName) (\(name))"
    }
}

/// Protocol for transcription providers
protocol TranscriptionProvider {
    /// Provider name for display
    var name: String { get }

    /// Provider description
    var description: String { get }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool { get }

    /// Transcribe audio file to text
    /// - Parameters:
    ///   - audioURL: URL of the audio file
    ///   - language: Optional language code (ISO 639-1)
    /// - Returns: Transcribed text
    func transcribe(audioURL: URL, language: String?) async throws -> String

    /// Get list of supported languages
    func supportedLanguages() async -> [TranscriptionLanguage]
}

/// Errors that can occur during transcription
enum TranscriptionError: Error, LocalizedError {
    case fileNotFound
    case invalidAudioFormat
    case languageNotSupported(String)
    case apiKeyMissing
    case apiKeyInvalid
    case networkError(Error)
    case transcriptionFailed(String)
    case rateLimitExceeded
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .languageNotSupported(let lang):
            return "Language '\(lang)' is not supported"
        case .apiKeyMissing:
            return "API key is not configured"
        case .apiKeyInvalid:
            return "API key is invalid"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .quotaExceeded:
            return "API quota exceeded"
        }
    }
}

/// Transcription engine selection
enum TranscriptionEngine: String, CaseIterable, Codable {
    case apple = "apple"
    case elevenLabs = "elevenlabs"

    var displayName: String {
        switch self {
        case .apple:
            return "Apple (On-device)"
        case .elevenLabs:
            return "ElevenLabs API"
        }
    }

    var description: String {
        switch self {
        case .apple:
            return "Free, private, works offline"
        case .elevenLabs:
            return "99 languages, high accuracy"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .apple:
            return false
        case .elevenLabs:
            return true
        }
    }
}
