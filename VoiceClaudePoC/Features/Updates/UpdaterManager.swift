//
//  UpdaterManager.swift
//  VoiceClaudePoC
//
//  Manages Sparkle auto-updates for the menu bar app.
//

import Foundation
import Sparkle
import AppKit
import OSLog

/// Manages Sparkle 2 auto-updates for the menu bar app.
/// Menu bar apps require special handling since they have no main window.
@MainActor
final class UpdaterManager: NSObject, @preconcurrency Sendable {
    static let shared = UpdaterManager()

    private let logger = Logger(subsystem: "com.wisecorner.cctalk", category: "Updater")

    /// The SPUUpdater instance
    private var updater: SPUUpdater?

    /// The standard user driver for update UI
    private var userDriver: SPUStandardUserDriver?

    // MARK: - State

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? true }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    /// Whether an update check is currently in progress
    var isCheckingForUpdates: Bool {
        updater?.sessionInProgress ?? false
    }

    /// Last update check date
    var lastUpdateCheckDate: Date? {
        updater?.lastUpdateCheckDate
    }

    /// Whether the updater can check for updates right now
    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    /// Configures and starts the updater. Call this in applicationDidFinishLaunching.
    func configure() {
        logger.info("Configuring Sparkle updater")

        userDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: self)

        guard let userDriver = userDriver else {
            logger.error("Failed to create SPUStandardUserDriver")
            return
        }

        do {
            updater = try SPUUpdater(
                hostBundle: Bundle.main,
                applicationBundle: Bundle.main,
                userDriver: userDriver,
                delegate: self
            )

            try updater?.start()
            logger.info("Sparkle updater started successfully")

        } catch {
            logger.error("Failed to start Sparkle updater: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Actions

    /// Manually check for updates
    func checkForUpdates() {
        logger.info("Manual update check requested")
        updater?.checkForUpdates()
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdaterManager: SPUStandardUserDriverDelegate {

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            self.logger.info("Update available: \(update.displayVersionString)")
        }
    }

    nonisolated func standardUserDriverRequestsWindow() -> NSWindow? {
        nil
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func standardUserDriverDidDismissModalAlert() {
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterManager: SPUUpdaterDelegate {

    nonisolated func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        false
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            self.logger.error("Update check aborted: \(error.localizedDescription)")
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        Task { @MainActor in
            self.logger.info("Loaded appcast with \(appcast.items.count) items")
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        Task { @MainActor in
            self.logger.info("No update found (current version is latest)")
        }
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        []
    }
}
