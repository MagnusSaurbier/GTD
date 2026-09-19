import Foundation
import Observation
import GTDModel
import GTDAppCore
import GTDFixtures
import GTDIntents
import GTDServices
import GTDVault
import FeatureSettings

/// The composition root: the one place that knows about `GTDVault` and `GTDServices`.
///
/// Launch → resolve the security-scoped bookmark → `FileVaultStore` → `VaultBackend` → `AppModel`
/// (ARCHITECTURE §2). Feature targets never see any of it; they get `AppModel` from the
/// environment. With `-useFixtures` the whole chain is replaced by `InMemoryBackend` +
/// `GTDFixtures.sampleSnapshot`, which is what UI tests and screenshots run on.
@MainActor
@Observable
final class AppComposition {

    enum Phase: Equatable {
        /// Resolving the bookmark and doing the first scan.
        case loading
        /// No usable vault yet — `OnboardingView` is on screen. The vault may already be open
        /// behind it: onboarding's later steps show the real snapshot.
        case onboarding
        case ready
    }

    private(set) var phase: Phase = .loading
    /// Swapped when the vault opens, so the environment hands every view the live model.
    private(set) var model: AppModel
    /// Absolute path of the vault root, for `\.vaultRootPath` ("Open in Obsidian", E3).
    private(set) var vaultRootPath: String?
    /// A shell-level failure to show (vault, capture, notification permission). `AppModel`'s own
    /// `lastError` is folded in by `RootView`.
    var error: AppError?

    /// Persisted on every change; the shell re-plans notifications when they change
    /// (`RootView`'s `onChange`), because the morning time and the per-kind toggles live here.
    var deviceSettings: DeviceSettings {
        didSet {
            guard deviceSettings != oldValue else { return }
            settingsStore.save(deviceSettings)
        }
    }

    let isUsingFixtures: Bool
    let pendingRoute = PendingRoute()

    private let bookmark: VaultBookmark
    private let settingsStore: DeviceSettingsStore
    private var store: FileVaultStore?
    private var backend: VaultBackend?
    /// True once the bookmark's security-scoped access is open, so it is stopped exactly once.
    private var isAccessing = false
    /// The day `archiveCompleted` last ran under this process (A5).
    private var lastArchiveDay: Day?

    /// `useFixtures` defaults to the launch argument. Previews pass `true` explicitly, so a
    /// preview can never resolve the bookmark and read the real vault (CLAUDE.md rule 1).
    init(useFixtures: Bool = LaunchOptions.useFixtures) {
        isUsingFixtures = useFixtures
        bookmark = VaultBookmark()
        settingsStore = DeviceSettingsStore(store: UserDefaultsSettingsStore())
        deviceSettings = settingsStore.load()
        if useFixtures {
            let snapshot = Fixtures.sampleSnapshot
            model = AppModel(
                backend: InMemoryBackend(snapshot: snapshot),
                snapshot: snapshot,
                today: { Fixtures.today })
            phase = .ready
        } else {
            // A placeholder so the environment always has a model — onboarding needs one too
            // (`OnboardingView` reads the snapshot for its validation step).
            model = AppModel(backend: InMemoryBackend(snapshot: .empty), snapshot: .empty)
            phase = .loading
        }
    }

    // MARK: - Launch

    /// Resolves a saved vault and opens it. Onboarding otherwise.
    func bootstrap() async {
        guard !isUsingFixtures, phase == .loading else { return }
        guard bookmark.hasSavedVault else {
            phase = .onboarding
            return
        }
        do {
            try await openVault()
            phase = .ready
        } catch {
            // A bookmark that no longer resolves is not a crash: the person picks the folder
            // again. The reason is shown, never swallowed.
            self.error = AppError(message: AppCopy.vaultUnavailable(AppError(error).message))
            phase = .onboarding
        }
    }

    /// Onboarding picked a folder. The vault opens immediately (so onboarding's own validation
    /// step shows the real counts), but onboarding stays on screen until it finishes.
    func pickVault(_ url: URL) async {
        do {
            try bookmark.save(url: url)
            deviceSettings.vaultDisplayName = url.lastPathComponent
            try await openVault()
        } catch {
            self.error = AppError(message: AppCopy.vaultUnavailable(AppError(error).message))
        }
    }

    /// The last onboarding step was read.
    func finishOnboarding() {
        phase = vaultRootPath == nil ? .onboarding : .ready
    }

    /// Settings → "Change vault…": close everything and go back to the picker.
    func changeVault() async {
        await teardown()
        try? bookmark.clear()
        vaultRootPath = nil
        deviceSettings.vaultDisplayName = nil
        model = AppModel(backend: InMemoryBackend(snapshot: .empty), snapshot: .empty)
        phase = .onboarding
    }

    // MARK: - The vault

    private func openVault() async throws {
        await teardown()
        guard bookmark.startAccess() else { throw VaultError.noVaultSelected }
        isAccessing = true
        let root = try bookmark.resolve()
        let store = FileVaultStore(root: root)
        let backend = VaultBackend(store: store, deviceID: DeviceIdentity.current)
        // Creates the folder skeleton, scans, starts watching, runs the daily archive (T16).
        try await backend.start()
        self.store = store
        self.backend = backend
        vaultRootPath = root.path
        model.stop()
        model = AppModel(backend: backend)
    }

    private func teardown() async {
        model.stop()
        await backend?.stop()
        backend = nil
        await store?.close()
        store = nil
        if isAccessing {
            bookmark.stopAccess()
            isAccessing = false
        }
    }

    /// The app came back to the foreground: re-read the vault (N3 — another device may have
    /// synced while we were away) and let the watcher carry on from there.
    func refreshFromDisk() async {
        guard let store else { return }
        do {
            _ = try await store.scan()
        } catch {
            self.error = AppError(error)
        }
    }

    /// A5 — archive done notes once a day.
    ///
    /// `VaultBackend.start()` already does this at launch and remembers the day outside the
    /// vault, but a Mac that stays open for a week never starts again; this covers the day
    /// rolling over under a running app. The command is a no-op when nothing is old enough,
    /// and it is not undoable, so running it once too often costs nothing.
    func runDailyHousekeeping() async {
        guard backend != nil else { return }
        let today = model.today()
        guard lastArchiveDay != today else { return }
        lastArchiveDay = today
        try? await model.send(.archiveCompleted)
    }

    /// Closes the vault cleanly on termination: stop watching, stop security-scoped access.
    func shutdown() async {
        await teardown()
    }

    // MARK: - Capture (C1, I7)

    /// Writes one capture into `Inbox/` and returns its id.
    ///
    /// Capture deliberately bypasses the reducer (there is no capture command — ARCHITECTURE §4)
    /// and goes straight through `InboxWriter`, exactly like the Shortcut and the App Intent do.
    /// It gets its **own** `VaultBookmark` instance so its `startAccess`/`stopAccess` pair cannot
    /// close the access the open vault is holding.
    @discardableResult
    func capture(text: String) -> NoteID? {
        if isUsingFixtures { return nil }
        let writer = InboxWriter(
            layout: model.snapshot.config.layout, bookmark: VaultBookmark())
        do {
            let id = try CaptureRequest(text: text).perform(writer: writer)
            // The watcher will see the new file, but the queue should not wait for a poll.
            Task { await refreshFromDisk() }
            return id
        } catch {
            self.error = AppError(message: AppCopy.captureFailed(AppError(error).message))
            return nil
        }
    }
}
