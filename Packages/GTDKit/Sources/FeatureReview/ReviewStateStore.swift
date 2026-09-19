import Foundation

/// Where the resumable wizard state lives between launches. Injected so persistence is
/// unit-testable without touching the real Application Support directory — and so nothing in
/// this target can ever write into the vault (ARCHITECTURE §3: device-local state is *not*
/// vault data).
public protocol ReviewStateStore: Sendable {
    func load() -> ReviewSessionState?
    func save(_ state: ReviewSessionState)
    func clear()
}

/// Store for tests and previews.
public final class InMemoryReviewStateStore: ReviewStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ReviewSessionState?
    /// How many times `save` was called — lets a test assert that a mutation persisted.
    public private(set) var saveCount = 0

    public init(_ initial: ReviewSessionState? = nil) {
        state = initial
    }

    public func load() -> ReviewSessionState? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func save(_ state: ReviewSessionState) {
        lock.lock()
        defer { lock.unlock() }
        self.state = state
        saveCount += 1
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        state = nil
    }
}

/// The real store: one JSON file in Application Support (ARCHITECTURE §3).
///
/// Failure is never fatal and never silent-but-wrong: an unreadable or corrupt file is treated
/// as "no session in progress" (the review starts fresh) rather than as a half-restored wizard,
/// and a failed write only costs resumability, so it is swallowed rather than thrown at the UI.
public struct FileReviewStateStore: ReviewStateStore {
    /// `~/Library/Application Support/GTD/weekly-review.json` on Apple platforms.
    public static let defaultFileName = "weekly-review.json"
    public static let defaultFolderName = "GTD"

    private let url: URL?

    /// - Parameter directory: where the file lives. Defaults to Application Support; tests pass
    ///   a temporary directory.
    public init(directory: URL? = nil, fileName: String = FileReviewStateStore.defaultFileName) {
        let folder = directory ?? FileReviewStateStore.applicationSupportFolder()
        url = folder?.appendingPathComponent(fileName)
    }

    static func applicationSupportFolder() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        else { return nil }
        return base.appendingPathComponent(defaultFolderName, isDirectory: true)
    }

    public func load() -> ReviewSessionState? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReviewSessionState.self, from: data)
    }

    public func save(_ state: ReviewSessionState) {
        guard let url, let data = try? JSONEncoder().encode(state) else { return }
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Atomic: a crash mid-write must not leave a truncated file that decodes into nonsense.
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
