import Foundation
import Speech
import AVFoundation
import Combine

/// Modern speech-to-text using Apple's SpeechAnalyzer (macOS 26+)
/// Much faster and more accurate than SFSpeechRecognizer
@available(macOS 26.0, *)
@MainActor
class SpeechAnalyzerService: ObservableObject {

    enum AnalyzerError: Error, LocalizedError {
        case localeNotSupported(Locale)
        case modelNotInstalled
        case downloadFailed(Error)
        case transcriptionFailed(Error)
        case fileNotFound
        case audioFileError(Error)

        var errorDescription: String? {
            switch self {
            case .localeNotSupported(let locale):
                return "Language not supported: \(locale.identifier)"
            case .modelNotInstalled:
                return "Speech model not installed"
            case .downloadFailed(let error):
                return "Model download failed: \(error.localizedDescription)"
            case .transcriptionFailed(let error):
                return "Transcription failed: \(error.localizedDescription)"
            case .fileNotFound:
                return "Audio file not found"
            case .audioFileError(let error):
                return "Audio file error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var isTranscribing = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0

    // MARK: - Supported Locales

    /// Check if a locale is supported by SpeechTranscriber
    func isLocaleSupported(_ locale: Locale) async -> Bool {
        let supportedLocales = await SpeechTranscriber.supportedLocales
        return supportedLocales.contains(locale)
    }

    /// Get all supported locales
    func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    /// Check if model is installed for locale
    func isModelInstalled(for locale: Locale) async -> Bool {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])
        return status == .installed
    }

    // MARK: - Model Management

    /// Download model for locale if needed
    func ensureModelDownloaded(for locale: Locale) async throws {
        guard await isLocaleSupported(locale) else {
            throw AnalyzerError.localeNotSupported(locale)
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        // Check if already installed
        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .installed {
            return
        }

        // Download the model
        isDownloading = true
        downloadProgress = 0

        defer {
            isDownloading = false
            downloadProgress = 1.0
        }

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                // Track progress using KVO
                let progressObserver = request.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    Task { @MainActor in
                        self?.downloadProgress = progress.fractionCompleted
                    }
                }

                try await request.downloadAndInstall()

                // Clean up observer
                progressObserver.invalidate()
            }
        } catch {
            throw AnalyzerError.downloadFailed(error)
        }
    }

    // MARK: - Transcription

    /// Transcribe audio file using SpeechAnalyzer
    func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AnalyzerError.fileNotFound
        }

        guard await isLocaleSupported(locale) else {
            throw AnalyzerError.localeNotSupported(locale)
        }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            // Ensure model is available
            try await ensureModelDownloaded(for: locale)

            // Create transcriber
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

            // Open audio file
            let audioFile: AVAudioFile
            do {
                audioFile = try AVAudioFile(forReading: audioURL)
            } catch {
                throw AnalyzerError.audioFileError(error)
            }

            // Create analyzer with audio file
            let analyzer = try await SpeechAnalyzer(
                inputAudioFile: audioFile,
                modules: [transcriber],
                finishAfterFile: true
            )

            // Collect results
            var fullText = ""
            for try await result in transcriber.results {
                fullText += String(result.text.characters)
            }

            return fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch let error as AnalyzerError {
            throw error
        } catch {
            throw AnalyzerError.transcriptionFailed(error)
        }
    }
}
