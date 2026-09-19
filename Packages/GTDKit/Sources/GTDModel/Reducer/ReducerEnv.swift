import Foundation

/// Everything the reducer needs from the outside world. Passing it in keeps `Reducer.reduce`
/// pure and deterministic: same snapshot + same command + same env ⇒ equal `Reduction`.
public struct ReducerEnv: Sendable {
    public var now: Date
    public var today: Day
    /// Stable per-device id; goes into the routine-log file name (N3).
    public var deviceID: String
    public var calendar: Calendar

    public init(now: Date, today: Day, deviceID: String, calendar: Calendar = .current) {
        self.now = now
        self.today = today
        self.deviceID = deviceID
        self.calendar = calendar
    }

    /// Env for "right now" on this device.
    public static func live(deviceID: String, calendar: Calendar = .current) -> ReducerEnv {
        let now = Date()
        return ReducerEnv(now: now, today: Day(now, calendar: calendar), deviceID: deviceID, calendar: calendar)
    }
}

/// The result of one command: the new snapshot, anything the shell should present, and file
/// effects that the snapshot diff cannot express (knowledge notes, trash and archive moves,
/// the weekly review note).
/// `renames` is what tells "this note is gone" apart from "this note is called something else
/// now": a note whose `NoteID` the command changed appears there, so navigation state pointing
/// at the old id can follow it instead of being dropped (`RenameMap`).
public struct Reduction: Sendable {
    public var snapshot: VaultSnapshot
    public var prompts: [AppPrompt]
    public var extraOps: [VaultFileOp]
    public var renames: RenameMap

    public init(
        snapshot: VaultSnapshot,
        prompts: [AppPrompt] = [],
        extraOps: [VaultFileOp] = [],
        renames: RenameMap = .empty
    ) {
        self.snapshot = snapshot
        self.prompts = prompts
        self.extraOps = extraOps
        self.renames = renames
    }
}
