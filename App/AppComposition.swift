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
    /// The crash-safe copy of text the editors hold (#56), one per run and handed to every
    /// model. Fixture runs keep their own file, so they never offer the real vault's text.
    let unsavedJournal: UnsavedTextJournal
    /// What open dialogs hold that has no place in the vault yet (#94), one per run, handed to
    /// every model like the journal. Fixture runs keep their own file.
    let inputDrafts: InputDrafts

    private let bookmark: VaultBookmark
    private let settingsStore: DeviceSettingsStore
    private var store: FileVaultStore?
    private var backend: VaultBackend?
    /// True once the bookmark's security-scoped access is open, so it is stopped exactly once.
    private var isAccessing = false
    /// The day `archiveCompleted` last ran under this process (A5).

    /// `useFixtures` defaults to the launch argument. Previews pass `true` explicitly, so a
    /// preview can never resolve the bookmark and read the real vault (CLAUDE.md rule 1).
    init(useFixtures: Bool = LaunchOptions.useFixtures) {
        isUsingFixtures = useFixtures
        bookmark = VaultBookmark()
        settingsStore = DeviceSettingsStore(store: UserDefaultsSettingsStore())
        deviceSettings = settingsStore.load()
        let journalStore = FileUnsavedTextStore.standard(
            fileName: useFixtures ? "unsaved-text-fixtures.json" : "unsaved-text.json")
        unsavedJournal = UnsavedTextJournal(store: journalStore ?? InMemoryUnsavedTextStore())
        let draftStore = FileInputDraftStore.standard(
            fileName: useFixtures ? "input-drafts-fixtures.json" : "input-drafts.json")
        inputDrafts = InputDrafts(store: draftStore ?? InMemoryInputDraftStore())
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
        model.unsavedJournal = unsavedJournal
        model.inputDrafts = inputDrafts
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

    /// Onboarding → "Create new vault" (#60): creates `<location>/<name>` with the layout's
    /// folders and opens it like a picked vault. Returns `nil` on success, otherwise why it did
    /// not — onboarding shows that under the name field and the person picks again.
    /// `VaultCreator` refuses a folder that already has content before writing anything.
    ///
    /// The location's security scope stays open across creating the folder *and* bookmarking
    /// it: the new folder is reachable only through the location the person picked. Opening
    /// then goes through the new folder's own bookmark, like any picked vault.
    func createVault(named name: String, in location: URL) async -> String? {
        do {
            let root = try bookmark.withAccess(to: location) {
                let root = try VaultCreator.create(named: name, in: location)
                try bookmark.save(url: root)
                return root
            }
            deviceSettings.vaultDisplayName = root.lastPathComponent
            try await openVault()
            return nil
        } catch {
            return AppError(error).message
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
        model.unsavedJournal = unsavedJournal
        model.inputDrafts = inputDrafts
        phase = .onboarding
    }

    // MARK: - The vault

    private func openVault() async throws {
        await teardown()
        // Resolve first: `resolve()` tells "never picked" (`noVaultSelected`) apart from "saved
        // but no longer resolvable" (`bookmarkStale`), and onboarding shows that reason. Asking
        // `startAccess()` first would collapse both into the same message (T41).
        let root = try bookmark.resolve()
        guard bookmark.startAccess() else {
            throw VaultError.ioFailed(
                path: root.path, reason: "the system refused access to the vault folder")
        }
        isAccessing = true
        let store = FileVaultStore(root: root)
        let backend = VaultBackend(store: store, deviceID: DeviceIdentity.current)
        // Creates the folder skeleton, scans, starts watching, runs the daily archive (T16).
        try await backend.start()
        self.store = store
        self.backend = backend
        vaultRootPath = root.path
        model.stop()
        model = AppModel(backend: backend)
        model.unsavedJournal = unsavedJournal
        model.inputDrafts = inputDrafts
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

    /// Returns once every change the person made is in the vault's files (or was refused and
    /// reported). Writes are queued behind the UI; see `PendingWrites.swift` for who waits.
    func flushWrites() async {
        // Text still held by an open editor first — it becomes a queued write like any other.
        await model.flushHeldEdits()
        await backend?.flush()
    }

    /// Closes the vault cleanly: stop watching, stop security-scoped access.
    ///
    /// **Nothing calls this yet, on purpose.** `scenePhase == .background` is not termination —
    /// on the Mac it fires when the window is merely hidden, and on iOS the background refresh
    /// task still needs the vault — and SwiftUI offers no reliable "about to quit" hook on both
    /// platforms. Process exit releases the security scope anyway; this exists for a shell that
    /// grows a real termination hook (T41: reviewed, left unwired deliberately).
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
    ///
    /// The write is a coordinated one into an iCloud folder and can take a moment, so it runs
    /// off the main actor: the capture sheet is already gone while the file is being written.
    @discardableResult
    func capture(text: String) async -> NoteID? {
        if isUsingFixtures { return nil }
        let layout = model.snapshot.config.layout
        do {
            let id = try await Task.detached {
                try CaptureRequest(text: text).perform(
                    writer: InboxWriter(layout: layout, bookmark: VaultBookmark()))
            }.value
            // The watcher will see the new file, but the queue should not wait for a poll.
            Task { await refreshFromDisk() }
            return id
        } catch {
            self.error = AppError(message: AppCopy.captureFailed(AppError(error).message))
            return nil
        }
    }
}
