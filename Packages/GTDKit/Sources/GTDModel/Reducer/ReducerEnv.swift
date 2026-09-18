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
public struct Reduction: Sendable {
    public var snapshot: VaultSnapshot
    public var prompts: [AppPrompt]
    public var extraOps: [VaultFileOp]

    public init(snapshot: VaultSnapshot, prompts: [AppPrompt] = [], extraOps: [VaultFileOp] = []) {
        self.snapshot = snapshot
        self.prompts = prompts
        self.extraOps = extraOps
    }
}
