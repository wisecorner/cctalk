import Foundation
import Combine

/// Service for logging errors to a persistent file
class ErrorLoggingService: ObservableObject {

    static let shared = ErrorLoggingService()

    struct ErrorEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let message: String
        let context: String?

        init(message: String, context: String? = nil) {
            self.id = UUID()
            self.timestamp = Date()
            self.message = message
            self.context = context
        }

        var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter.string(from: timestamp)
        }
    }

    // MARK: - Properties

    @Published private(set) var errors: [ErrorEntry] = []

    private let logFileURL: URL
    private let maxEntries = 100

    // MARK: - Initialization

    private init() {
        // Get application support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("CCTalk", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        logFileURL = appFolder.appendingPathComponent("error_log.json")

        loadErrors()
    }

    // MARK: - Public Methods

    /// Log a new error
    func logError(_ message: String, context: String? = nil) {
        let entry = ErrorEntry(message: message, context: context)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.errors.insert(entry, at: 0)

            // Trim to max entries
            if self.errors.count > self.maxEntries {
                self.errors = Array(self.errors.prefix(self.maxEntries))
            }

            self.saveErrors()
        }

        // Also print to console for debugging
        print("CCTalk Error: \(message)" + (context != nil ? " (Context: \(context!))" : ""))
    }

    /// Clear all logged errors
    func clearErrors() {
        DispatchQueue.main.async { [weak self] in
            self?.errors.removeAll()
            self?.saveErrors()
        }
    }

    /// Get the log file path for sharing
    var logFilePath: String {
        logFileURL.path
    }

    // MARK: - Private Methods

    private func loadErrors() {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: logFileURL)
            errors = try JSONDecoder().decode([ErrorEntry].self, from: data)
        } catch {
            print("Failed to load error log: \(error)")
        }
    }

    private func saveErrors() {
        do {
            let data = try JSONEncoder().encode(errors)
            try data.write(to: logFileURL)
        } catch {
            print("Failed to save error log: \(error)")
        }
    }
}
