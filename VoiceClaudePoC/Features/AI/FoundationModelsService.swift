import Foundation
import FoundationModels
import Combine

/// Service for text processing using Apple's Foundation Models (on-device LLM)
@available(macOS 26.0, *)
@MainActor
class FoundationModelsService: ObservableObject {

    enum ServiceError: Error, LocalizedError {
        case notAvailable(String)
        case processingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .notAvailable(let reason):
                return "Foundation Models not available: \(reason)"
            case .processingFailed(let error):
                return "Processing failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var isProcessing = false
    @Published private(set) var isAvailable = false
    @Published private(set) var availabilityMessage = ""

    private var session: LanguageModelSession?

    // MARK: - Initialization

    init() {
        checkAvailability()
    }

    // MARK: - Availability

    func checkAvailability() {
        let availability = SystemLanguageModel.default.availability

        switch availability {
        case .available:
            isAvailable = true
            availabilityMessage = "Ready"
        case .unavailable(let reason):
            isAvailable = false
            switch reason {
            case .appleIntelligenceNotEnabled:
                availabilityMessage = "Enable Apple Intelligence in Settings"
            case .deviceNotEligible:
                availabilityMessage = "Device not eligible for Apple Intelligence"
            case .modelNotReady:
                availabilityMessage = "Model is downloading..."
            @unknown default:
                availabilityMessage = "Unavailable"
            }
        @unknown default:
            isAvailable = false
            availabilityMessage = "Unknown status"
        }
    }

    // MARK: - Text Formatting

    /// Format and improve transcribed speech text
    /// Adds proper punctuation, capitalization, and paragraph breaks
    /// - Parameters:
    ///   - rawText: The text to format
    ///   - customPrompt: Optional custom prompt (use placeholder {TEXT} for input text)
    func formatTranscription(_ rawText: String, customPrompt: String? = nil) async throws -> String {
        // Check availability first
        if !isAvailable {
            checkAvailability()
        }

        guard isAvailable else {
            // Return original text if Foundation Models not available
            return rawText
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let session = LanguageModelSession {
                "You are a text formatter. You ONLY output the corrected text. Never add introductions, explanations, URLs, or commentary. Never say 'Sure' or 'Here is'. Just output the corrected text directly."
            }

            // Use custom prompt if provided, otherwise use default
            let prompt: String
            if let customPrompt = customPrompt, !customPrompt.isEmpty {
                // Replace {TEXT} placeholder with actual text, or append if no placeholder
                if customPrompt.contains("{TEXT}") {
                    prompt = customPrompt.replacingOccurrences(of: "{TEXT}", with: rawText)
                } else {
                    prompt = "\(customPrompt)\n\(rawText)"
                }
            } else {
                prompt = """
                Add punctuation and fix capitalization. Output ONLY the corrected text:
                \(rawText)
                """
            }

            let response = try await session.respond(to: prompt)

            // Clean up any potential preamble the model might add
            var result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove common LLM preambles if present
            let preambles = [
                "Sure, here is the formatted text:",
                "Here is the formatted text:",
                "Sure,",
                "Here you go:",
                "---"
            ]
            for preamble in preambles {
                if result.lowercased().hasPrefix(preamble.lowercased()) {
                    result = String(result.dropFirst(preamble.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Remove any URLs that might have been added
            let urlPattern = #"https?://[^\s]+"#
            if let regex = try? NSRegularExpression(pattern: urlPattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return result.isEmpty ? rawText : result

        } catch {
            throw ServiceError.processingFailed(error)
        }
    }

    /// Quick cleanup - just fix basic punctuation and capitalization
    func quickCleanup(_ rawText: String) async throws -> String {
        guard isAvailable else {
            return rawText
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let session = LanguageModelSession()

            let prompt = """
            Add punctuation and fix capitalization in this text. Keep it concise.
            Return ONLY the corrected text:
            \(rawText)
            """

            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch {
            // On error, return original
            return rawText
        }
    }
}
