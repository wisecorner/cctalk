import Foundation
import AppKit

/// Injects keystrokes into terminal applications using AppleScript
class KeystrokeInjector {

    enum InjectionError: Error, LocalizedError {
        case scriptExecutionFailed(String)
        case processLaunchFailed(Error)
        case claudeNotInActiveTab(sessions: [ClaudeSession])
        case terminalNotActive(expected: String, actual: String?)
        case noClaudeRunning
        case cannotVerifyTab

        var errorDescription: String? {
            switch self {
            case .scriptExecutionFailed(let message):
                return "Script execution failed: \(message)"
            case .processLaunchFailed(let error):
                return "Failed to launch osascript: \(error.localizedDescription)"
            case .claudeNotInActiveTab(let sessions):
                let count = sessions.count
                return "Claude Code is not in the active tab (found \(count) session(s) in other tabs)"
            case .terminalNotActive(let expected, let actual):
                if let actual = actual {
                    return "Terminal \(expected) is not active (active app: \(actual))"
                }
                return "Terminal \(expected) is not active"
            case .noClaudeRunning:
                return "Claude Code is not running in any terminal"
            case .cannotVerifyTab:
                return "Cannot verify if Claude is in the active tab"
            }
        }
    }

    /// Injects a prompt into the specified terminal application
    /// Uses clipboard + Cmd+V for reliable Unicode support and to avoid overwhelming the terminal
    /// - Parameters:
    ///   - text: The prompt text to inject
    ///   - terminal: The terminal application name (e.g., "Ghostty", "Terminal")
    ///   - completion: Callback with result (success or error)
    func injectPrompt(_ text: String, terminal: String, completion: @escaping (Result<Void, InjectionError>) -> Void) {
        // Copy text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Use Cmd+V to paste - much faster and doesn't overwhelm the terminal
        let script = """
        tell application "\(terminal)"
            activate
            -- Wait until terminal is frontmost
            repeat 20 times
                if frontmost then exit repeat
                delay 0.1
            end repeat
        end tell
        -- Extra delay to ensure terminal is fully ready for input
        delay 0.5
        tell application "System Events"
            keystroke "v" using command down
            delay 0.3
            keystroke return
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", script]

                let errorPipe = Pipe()
                task.standardError = errorPipe
                task.standardOutput = FileHandle.nullDevice

                try task.run()
                task.waitUntilExit()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        completion(.success(()))
                    } else {
                        completion(.failure(.scriptExecutionFailed(errorOutput)))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.processLaunchFailed(error)))
                }
            }
        }
    }

    /// Synchronous version for async/await contexts
    @MainActor
    func injectPrompt(_ text: String, terminal: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            injectPrompt(text, terminal: terminal) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Validated Injection

    /// Injects prompt only after validating Claude is in the active terminal tab
    /// - Parameters:
    ///   - text: The prompt text to inject
    ///   - terminal: The terminal application name
    ///   - validation: Pre-computed validation result from TerminalDetector
    ///   - completion: Callback with result
    func injectPromptWithValidation(
        _ text: String,
        terminal: String,
        validation: InjectionValidation,
        completion: @escaping (Result<Void, InjectionError>) -> Void
    ) {
        switch validation {
        case .ready:
            // Claude is in active tab - proceed with injection
            injectPrompt(text, terminal: terminal, completion: completion)

        case .cannotVerifyTab:
            // Terminal doesn't support tab detection but Claude is running
            // Trust the user and proceed with injection
            injectPrompt(text, terminal: terminal, completion: completion)

        case .noClaudeRunning:
            completion(.failure(.noClaudeRunning))

        case .claudeNotInActiveTab(let sessions):
            completion(.failure(.claudeNotInActiveTab(sessions: sessions)))

        case .terminalNotActive(let expected, let actual):
            completion(.failure(.terminalNotActive(expected: expected, actual: actual)))

        case .multipleSessionsFound:
            // This should be handled by AppState showing a picker
            // If we get here, treat as error
            completion(.failure(.noClaudeRunning))
        }
    }

    /// Async version of validated injection
    @MainActor
    func injectPromptWithValidation(
        _ text: String,
        terminal: String,
        validation: InjectionValidation
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            injectPromptWithValidation(text, terminal: terminal, validation: validation) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
