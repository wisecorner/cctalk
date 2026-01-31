import Foundation
import SwiftData
import Combine

/// SwiftData model for storing prompt history
@Model
final class PromptHistory {
    var text: String
    var timestamp: Date
    var terminal: String

    init(text: String, timestamp: Date = Date(), terminal: String) {
        self.text = text
        self.timestamp = timestamp
        self.terminal = terminal
    }
}

// MARK: - History Service

@MainActor
class PromptHistoryService: ObservableObject {
    private var modelContext: ModelContext?

    @Published var recentPrompts: [PromptHistory] = []

    static let shared = PromptHistoryService()

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        fetchRecentPrompts()
    }

    func addPrompt(text: String, terminal: String) {
        guard let modelContext = modelContext else { return }

        let prompt = PromptHistory(text: text, terminal: terminal)
        modelContext.insert(prompt)

        do {
            try modelContext.save()
            fetchRecentPrompts()
        } catch {
            print("Failed to save prompt history: \(error)")
        }
    }

    func fetchRecentPrompts(limit: Int = 10) {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<PromptHistory>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let allPrompts = try modelContext.fetch(descriptor)
            recentPrompts = Array(allPrompts.prefix(limit))
        } catch {
            print("Failed to fetch prompt history: \(error)")
            recentPrompts = []
        }
    }

    func deletePrompt(_ prompt: PromptHistory) {
        guard let modelContext = modelContext else { return }

        modelContext.delete(prompt)

        do {
            try modelContext.save()
            fetchRecentPrompts()
        } catch {
            print("Failed to delete prompt: \(error)")
        }
    }

    func clearAllHistory() {
        guard let modelContext = modelContext else { return }

        do {
            try modelContext.delete(model: PromptHistory.self)
            try modelContext.save()
            recentPrompts = []
        } catch {
            print("Failed to clear history: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension PromptHistory {
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var truncatedText: String {
        if text.count > 50 {
            return String(text.prefix(50)) + "..."
        }
        return text
    }
}
