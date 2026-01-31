import Foundation
import Speech

/// Apple's on-device transcription using SpeechAnalyzer
@available(macOS 26.0, *)
@MainActor
class AppleTranscriptionProvider: TranscriptionProvider {

    // MARK: - Properties

    let name = "Apple (On-device)"
    let description = "Free, private, works offline"
    let requiresAPIKey = false

    private let speechService = SpeechAnalyzerService()

    // MARK: - TranscriptionProvider

    func transcribe(audioURL: URL, language: String?) async throws -> String {
        let locale: Locale
        if let lang = language {
            locale = Locale(identifier: lang)
        } else {
            locale = Locale(identifier: "en_US")
        }

        do {
            return try await speechService.transcribe(audioURL: audioURL, locale: locale)
        } catch let error as SpeechAnalyzerService.AnalyzerError {
            switch error {
            case .localeNotSupported(let loc):
                throw TranscriptionError.languageNotSupported(loc.identifier)
            case .fileNotFound:
                throw TranscriptionError.fileNotFound
            case .audioFileError:
                throw TranscriptionError.invalidAudioFormat
            default:
                throw TranscriptionError.transcriptionFailed(error.localizedDescription)
            }
        }
    }

    func supportedLanguages() async -> [TranscriptionLanguage] {
        let locales = await speechService.supportedLocales()

        // Group locales by language code to avoid duplicates
        var languageMap: [String: Locale] = [:]
        for locale in locales {
            guard let languageCode = locale.language.languageCode?.identifier else {
                continue
            }
            // Keep first locale for each language (or prefer specific ones like en_US)
            if languageMap[languageCode] == nil {
                languageMap[languageCode] = locale
            }
        }

        return languageMap.values.compactMap { locale -> TranscriptionLanguage? in
            guard let languageCode = locale.language.languageCode?.identifier else {
                return nil
            }

            let englishName = Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? languageCode
            let nativeName = locale.localizedString(forLanguageCode: languageCode) ?? englishName

            return TranscriptionLanguage(
                code: locale.identifier,
                name: englishName,
                nativeName: nativeName
            )
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Additional Methods

    /// Check if model is downloaded for language
    func isModelDownloaded(for language: String) async -> Bool {
        let locale = Locale(identifier: language)
        return await speechService.isModelInstalled(for: locale)
    }

    /// Download model for language
    func downloadModel(for language: String) async throws {
        let locale = Locale(identifier: language)
        try await speechService.ensureModelDownloaded(for: locale)
    }

    /// Get download progress
    var downloadProgress: Double {
        speechService.downloadProgress
    }

    /// Is currently downloading
    var isDownloading: Bool {
        speechService.isDownloading
    }
}
