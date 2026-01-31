import Foundation
import CoreServices
import AppKit

// MARK: - Types

/// Claude Code session with TTY and terminal information
struct ClaudeSession: Identifiable, Equatable {
    let pid: Int
    let tty: String           // e.g., "ttys012"
    let ttyDevice: String     // e.g., "/dev/ttys012"
    let terminalApp: String?  // detected terminal (optional)
    let workingDirectory: String?  // working directory, e.g., "~/projects/my-app"

    var id: Int { pid }

    /// Project name (last path segment)
    var projectName: String? {
        guard let cwd = workingDirectory else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// User-readable session description
    var displayName: String {
        if let name = projectName {
            return name
        }
        return "Claude (TTY: \(tty))"
    }

    static func == (lhs: ClaudeSession, rhs: ClaudeSession) -> Bool {
        lhs.pid == rhs.pid
    }
}

/// Validation result before pasting
enum InjectionValidation: Equatable {
    case ready(session: ClaudeSession)
    case noClaudeRunning
    case claudeNotInActiveTab(availableSessions: [ClaudeSession])
    case terminalNotActive(expectedTerminal: String, activeApp: String?)
    case cannotVerifyTab(session: ClaudeSession) // For terminals without API - CC is running but cannot verify tab
    case multipleSessionsFound(sessions: [ClaudeSession]) // Multiple sessions - user must choose

    static func == (lhs: InjectionValidation, rhs: InjectionValidation) -> Bool {
        switch (lhs, rhs) {
        case (.noClaudeRunning, .noClaudeRunning):
            return true
        case (.ready(let s1), .ready(let s2)):
            return s1 == s2
        case (.claudeNotInActiveTab(let s1), .claudeNotInActiveTab(let s2)):
            return s1 == s2
        case (.terminalNotActive(let e1, let a1), .terminalNotActive(let e2, let a2)):
            return e1 == e2 && a1 == a2
        case (.cannotVerifyTab(let s1), .cannotVerifyTab(let s2)):
            return s1 == s2
        case (.multipleSessionsFound(let s1), .multipleSessionsFound(let s2)):
            return s1 == s2
        default:
            return false
        }
    }
}

// MARK: - TerminalDetector

/// Detects Claude Code processes running in terminal sessions
class TerminalDetector {

    /// All supported terminal applications
    static let availableTerminals = ["Ghostty", "Terminal", "iTerm2", "Warp", "Alacritty", "kitty"]

    /// Terminal app bundle identifiers for detection
    private static let terminalBundleIds: [String: String] = [
        "Ghostty": "com.mitchellh.ghostty",
        "Terminal": "com.apple.Terminal",
        "iTerm2": "com.googlecode.iterm2",
        "Warp": "dev.warp.Warp-Stable",
        "Alacritty": "org.alacritty",
        "kitty": "net.kovidgoyal.kitty"
    ]

    /// Detects which terminals are installed on the system
    /// - Returns: Array of installed terminal names, sorted with most common first
    static func detectInstalledTerminals() -> [String] {
        var installed: [String] = []

        for terminal in availableTerminals {
            if let bundleId = terminalBundleIds[terminal] {
                // Check if app exists using LSCopyApplicationURLsForBundleIdentifier
                if let urls = LSCopyApplicationURLsForBundleIdentifier(bundleId as CFString, nil)?.takeRetainedValue() as? [URL],
                   !urls.isEmpty {
                    installed.append(terminal)
                }
            }
        }

        // Terminal.app is always available on macOS
        if !installed.contains("Terminal") {
            installed.append("Terminal")
        }

        return installed
    }

    /// Returns installed terminals, or all available if detection fails
    static var installedTerminals: [String] {
        let detected = detectInstalledTerminals()
        return detected.isEmpty ? availableTerminals : detected
    }

    /// Finds all Claude Code processes with an active TTY (terminal session)
    /// - Returns: Array of process info strings (e.g., "1335 ttys012 claude")
    func getClaudeTerminalProcesses() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "ps -eo pid,tty,comm 2>/dev/null | grep claude || true"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            print("TerminalDetector: Failed to run ps: \(error)")
            return []
        }

        // Read output BEFORE waitUntilExit to avoid deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Filter only processes with TTY (not "??")
        let results = lines
            .filter { !$0.contains("??") }
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return results
    }

    /// Checks if Claude Code is running in any terminal
    func isClaudeRunning() -> Bool {
        !getClaudeTerminalProcesses().isEmpty
    }

    /// Gets the count of active Claude Code sessions
    func activeSessionCount() -> Int {
        getClaudeTerminalProcesses().count
    }

    // MARK: - Enhanced Session Detection

    /// Gets Claude sessions filtered for the selected terminal (without activating windows)
    /// - Parameter terminal: Name of the selected terminal
    /// - Returns: Claude sessions for this terminal, or empty array if terminal is not running
    func getFilteredClaudeSessions(terminal: String) -> [ClaudeSession] {
        let allSessions = getClaudeSessions()
        guard !allSessions.isEmpty else { return [] }

        switch terminal {
        case "Terminal":
            // If Terminal.app is not running, return empty (not all sessions)
            guard isAppRunning(bundleId: "com.apple.Terminal") else {
                return []
            }
            let terminalTTYs = getTerminalAppAllTTYs()
            if !terminalTTYs.isEmpty {
                return allSessions.filter { session in
                    terminalTTYs.contains(session.ttyDevice) || terminalTTYs.contains("/dev/\(session.tty)")
                }
            }
            // Terminal is running but we couldn't get TTYs - return empty to be safe
            return []

        case "iTerm2":
            // If iTerm2 is not running, return empty
            guard isAppRunning(bundleId: "com.googlecode.iterm2") else {
                return []
            }
            let itermTTYs = getITermAllSessionTTYs()
            if !itermTTYs.isEmpty {
                return allSessions.filter { session in
                    itermTTYs.contains(session.ttyDevice) || itermTTYs.contains("/dev/\(session.tty)")
                }
            }
            // iTerm2 is running but we couldn't get TTYs - return empty to be safe
            return []

        case "Ghostty":
            guard isAppRunning(bundleId: "com.mitchellh.ghostty") else {
                return []
            }
            // Can't filter by TTY for Ghostty, but at least check it's running
            return allSessions

        case "Warp":
            guard isAppRunning(bundleId: "dev.warp.Warp-Stable") else {
                return []
            }
            return allSessions

        case "Alacritty":
            guard isAppRunning(bundleId: "org.alacritty") else {
                return []
            }
            return allSessions

        case "kitty":
            guard isAppRunning(bundleId: "net.kovidgoyal.kitty") else {
                return []
            }
            return allSessions

        default:
            return allSessions
        }
    }

    /// Gets detailed Claude sessions with TTY information
    func getClaudeSessions() -> [ClaudeSession] {
        let processes = getClaudeTerminalProcesses()

        return processes.compactMap { line -> ClaudeSession? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int(String(parts[0])) else {
                return nil
            }

            let tty = String(parts[1])
            let ttyDevice = "/dev/\(tty)"
            let cwd = getProcessWorkingDirectory(pid: pid)

            return ClaudeSession(
                pid: pid,
                tty: tty,
                ttyDevice: ttyDevice,
                terminalApp: nil,
                workingDirectory: cwd
            )
        }
    }

    /// Gets the working directory of a process
    private func getProcessWorkingDirectory(pid: Int) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-d", "cwd", "-p", "\(pid)", "-Fn"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Format: "p1234\nn/path/to/cwd"
        // Look for line starting with "n"
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n") {
                return String(line.dropFirst())
            }
        }

        return nil
    }

    /// Checks which application is currently in the foreground
    func getFrontmostApp() -> String? {
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// Checks if the given application is a terminal
    func isTerminalApp(_ appName: String) -> Bool {
        Self.availableTerminals.contains(appName)
    }

    // MARK: - Injection Validation

    /// Verifies if it's safe to paste to the terminal
    /// - Parameter terminal: Name of the selected terminal
    /// - Returns: Validation result
    func validateInjection(terminal: String) -> InjectionValidation {
        // 1. Get Claude sessions filtered for the selected terminal
        let sessions = getFilteredClaudeSessions(terminal: terminal)

        guard !sessions.isEmpty else {
            return .noClaudeRunning
        }

        // 2. Terminal-specific validation
        switch terminal {
        case "iTerm2":
            return validateITerm2Session(sessions: sessions)

        case "Terminal":
            return validateTerminalAppSession(sessions: sessions)

        case "kitty":
            return validateKittySession(sessions: sessions)

        default:
            // Ghostty, Warp, Alacritty - no API to verify tab
            if sessions.count > 1 {
                return .multipleSessionsFound(sessions: sessions)
            } else if let firstSession = sessions.first {
                return .cannotVerifyTab(session: firstSession)
            }
            return .noClaudeRunning
        }
    }

    /// Checks if an application with the given bundle ID is running
    private func isAppRunning(bundleId: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }

    /// Gets TTY of all Terminal.app tabs
    func getTerminalAppAllTTYs() -> [String] {
        // Don't call AppleScript if Terminal is not running - it would launch it
        guard isAppRunning(bundleId: "com.apple.Terminal") else {
            return []
        }

        let script = """
        tell application "Terminal"
            set ttyList to {}
            repeat with w in windows
                repeat with t in tabs of w
                    set end of ttyList to tty of t
                end repeat
            end repeat
            return ttyList
        end tell
        """

        guard let result = runAppleScript(script) else {
            return []
        }

        // Result format: "/dev/ttys001, /dev/ttys002, ..."
        return result.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Gets TTY of all iTerm2 sessions
    func getITermAllSessionTTYs() -> [String] {
        // Don't call AppleScript if iTerm2 is not running - it would launch it
        guard isAppRunning(bundleId: "com.googlecode.iterm2") else {
            return []
        }

        let script = """
        tell application "iTerm"
            set ttyList to {}
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set end of ttyList to tty of s
                    end repeat
                end repeat
            end repeat
            return ttyList
        end tell
        """

        guard let result = runAppleScript(script) else {
            return []
        }

        return result.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - iTerm2 Detection

    /// Gets TTY of the active iTerm2 session
    func getITermActiveSessionTTY() -> String? {
        let script = """
        tell application "iTerm"
            tell current session of current window
                tty
            end tell
        end tell
        """

        return runAppleScript(script)
    }

    private func validateITerm2Session(sessions: [ClaudeSession]) -> InjectionValidation {
        guard let activeTTY = getITermActiveSessionTTY() else {
            // Failed to get TTY - maybe iTerm has no open window
            if sessions.count > 1 {
                return .multipleSessionsFound(sessions: sessions)
            }
            if let firstSession = sessions.first {
                return .cannotVerifyTab(session: firstSession)
            }
            return .noClaudeRunning
        }

        // Check if Claude is running on the active TTY
        // activeTTY is in format "/dev/ttys012", sessions have "ttys012"
        let normalizedTTY = activeTTY.replacingOccurrences(of: "/dev/", with: "")

        if let matchingSession = sessions.first(where: { $0.tty == normalizedTTY }) {
            return .ready(session: matchingSession)
        }

        // Claude is running, but not in the active tab
        if sessions.count > 1 {
            return .multipleSessionsFound(sessions: sessions)
        }
        return .claudeNotInActiveTab(availableSessions: sessions)
    }

    // MARK: - Terminal.app Detection

    /// Checks if the active Terminal.app tab is busy
    func isTerminalAppTabBusy() -> Bool {
        let script = """
        tell application "Terminal"
            busy of (selected tab of window 1)
        end tell
        """

        let result = runAppleScript(script)
        return result?.lowercased() == "true"
    }

    /// Gets TTY of the active Terminal.app tab
    func getTerminalAppActiveTTY() -> String? {
        let script = """
        tell application "Terminal"
            tty of (selected tab of window 1)
        end tell
        """

        return runAppleScript(script)
    }

    private func validateTerminalAppSession(sessions: [ClaudeSession]) -> InjectionValidation {
        // Terminal.app has `tty` property for tabs
        guard let activeTTY = getTerminalAppActiveTTY() else {
            // Fallback: check if tab is busy
            if isTerminalAppTabBusy() {
                // Tab is busy, but we can't verify if it's Claude
                if let firstSession = sessions.first {
                    return .cannotVerifyTab(session: firstSession)
                }
            }
            return .claudeNotInActiveTab(availableSessions: sessions)
        }

        // Normalize TTY (remove /dev/ if present)
        let normalizedTTY = activeTTY.replacingOccurrences(of: "/dev/", with: "")

        if let matchingSession = sessions.first(where: { $0.tty == normalizedTTY }) {
            return .ready(session: matchingSession)
        }

        // Claude is not in the active tab
        if sessions.count > 1 {
            // Multiple sessions - user must choose
            return .multipleSessionsFound(sessions: sessions)
        }

        // Single session - auto-switch
        if let claudeSession = sessions.first {
            if switchTerminalAppToTab(withTTY: claudeSession.tty) {
                return .ready(session: claudeSession)
            }
        }

        return .claudeNotInActiveTab(availableSessions: sessions)
    }

    /// Switches Terminal.app to the tab with the given TTY
    /// - Parameter tty: TTY of the tab (e.g., "ttys004")
    /// - Returns: true if switch was successful
    func switchTerminalAppToTab(withTTY tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            set targetTTY to "/dev/\(tty)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is targetTTY then
                        set selected tab of w to t
                        set frontmost of w to true
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """

        let result = runAppleScript(script)
        return result?.lowercased() == "true"
    }

    // MARK: - kitty Detection

    /// Checks kitty sessions using remote control API
    /// Requires `allow_remote_control=yes` in kitty.conf
    func getKittySessionPIDs() -> [Int]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "kitten @ ls 2>/dev/null"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            return nil // Remote control is probably disabled
        }

        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Parse JSON output to extract foreground_processes PIDs
        // Format: "foreground_processes": [{"pid": 1234, ...}]
        var pids: [Int] = []

        // Simple regex to extract PIDs from foreground_processes
        let pattern = #""pid"\s*:\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(output.startIndex..., in: output)
            let matches = regex.matches(in: output, range: range)

            for match in matches {
                if let pidRange = Range(match.range(at: 1), in: output) {
                    if let pid = Int(output[pidRange]) {
                        pids.append(pid)
                    }
                }
            }
        }

        return pids.isEmpty ? nil : pids
    }

    private func validateKittySession(sessions: [ClaudeSession]) -> InjectionValidation {
        guard let kittyPIDs = getKittySessionPIDs() else {
            // Remote control is disabled - fallback
            if let firstSession = sessions.first {
                return .cannotVerifyTab(session: firstSession)
            }
            return .noClaudeRunning
        }

        // Check if any Claude PID is in the active kitty window
        for session in sessions {
            if kittyPIDs.contains(session.pid) {
                return .ready(session: session)
            }
        }

        return .claudeNotInActiveTab(availableSessions: sessions)
    }

    // MARK: - TTY Utilities

    /// Checks if Claude is running on the given TTY
    func isClaudeOnTTY(_ tty: String) -> Bool {
        let normalizedTTY = tty.replacingOccurrences(of: "/dev/", with: "")
        let sessions = getClaudeSessions()
        return sessions.contains { $0.tty == normalizedTTY }
    }

    // MARK: - AppleScript Helper

    private func runAppleScript(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            print("TerminalDetector: AppleScript failed: \(error)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            return nil
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
