import Foundation
import GTDModel

/// Remembers the day this device last archived (A5), so `archiveCompleted` runs once per launch
/// *and* at most once per day — moving 30-day-old notes is not something to repeat on every
/// command, and on a synced vault every device doing it at once is pure noise.
///
/// Device-local, next to the undo journal in Application Support: it describes this device's
/// behaviour, not the user's data, so it never belongs in the vault (ARCHITECTURE §3).
actor HousekeepingState {
    private let file: URL?
    private var lastArchiveDay: Day??      // outer nil = not loaded yet

    init(directory: URL?, fileName: String = "housekeeping.json") {
        self.file = directory?.appendingPathComponent(fileName)
    }

    func shouldArchive(on today: Day) -> Bool {
        load() != today
    }

    func didArchive(on today: Day) {
        lastArchiveDay = .some(today)
        save()
    }

    // MARK: Persistence

    private func load() -> Day? {
        if let lastArchiveDay { return lastArchiveDay }
        var stored: Day?
        if let file, let data = try? Data(contentsOf: file),
           let state = try? JSONDecoder().decode(State.self, from: data) {
            stored = state.lastArchiveDay.flatMap(Day.init(iso:))
        }
        lastArchiveDay = .some(stored)
        return stored
    }

    private func save() {
        guard let file, let lastArchiveDay else { return }
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let state = State(lastArchiveDay: lastArchiveDay?.iso)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private struct State: Codable {
        var lastArchiveDay: String?
    }
}
