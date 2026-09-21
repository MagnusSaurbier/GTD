import Foundation
import GTDModel
@testable import GTDMarkdown

/// The time zone the sample vault's timestamps are written in (`+02:00`).
let vaultTimeZone = TimeZone(secondsFromGMT: 7200)!

/// Decode → encode for whatever kind of note `path` names, so the round-trip test can run over
/// a whole vault without knowing which decoder belongs to which file.
enum RoundTrip {

    static func encodeDecoded(path: String, text: String, timeZone: TimeZone = vaultTimeZone) throws -> String {
        let id = NoteID(path: path)
        switch kind(of: id, text: text) {
        case .inbox:
            return NoteCodec.encode(
                try NoteCodec.decodeInboxItem(id: id, text: text, timeZone: timeZone),
                timeZone: timeZone)
        case .action:
            return NoteCodec.encode(
                try NoteCodec.decodeAction(id: id, text: text, timeZone: timeZone),
                timeZone: timeZone)
        case .listItem:
            return NoteCodec.encode(
                try NoteCodec.decodeListItem(id: id, text: text, timeZone: timeZone),
                timeZone: timeZone)
        case .area:
            return NoteCodec.encode(try NoteCodec.decodeArea(id: id, text: text))
        case .project:
            return NoteCodec.encode(try NoteCodec.decodeProject(id: id, text: text))
        case .routine:
            return NoteCodec.encode(try NoteCodec.decodeRoutine(id: id, text: text))
        case .routineLog:
            return NoteCodec.encodeRoutineLog(
                try NoteCodec.decodeRoutineLog(id: id, text: text, timeZone: timeZone),
                timeZone: timeZone)
        case .config:
            return NoteCodec.encode(try NoteCodec.decodeConfig(id: id, text: text))
        case .review:
            return NoteCodec.encode(
                try NoteCodec.decodeWeeklyReview(id: id, text: text, timeZone: timeZone),
                timeZone: timeZone)
        }
    }

    enum Kind { case inbox, action, listItem, area, project, routine, routineLog, config, review }

    static func kind(of id: NoteID, text: String) -> Kind {
        let layout = VaultLayout.default
        if id.path == layout.configFile { return .config }
        if id.isInside(layout.inbox) { return .inbox }
        if id.isInside(layout.actions) || id.isInside(layout.archive) { return .action }
        if id.isInside(layout.lists) { return .listItem }
        if id.isInside(layout.routines) { return .routine }
        if id.isInside(layout.routineLog) { return .routineLog }
        if id.isInside(layout.reviews) { return .review }
        switch NoteCodec.noteKind(text: text, path: id.path) {
        case "area": return .area
        case "review": return .review
        default: return .project
        }
    }
}

/// A one-line diff for failure messages: the first line where two texts differ.
func firstDifference(_ lhs: String, _ rhs: String) -> String {
    let a = RawText.split(lhs)
    let b = RawText.split(rhs)
    for index in 0..<max(a.count, b.count) {
        let left = index < a.count ? a[index] : nil
        let right = index < b.count ? b[index] : nil
        if left != right {
            return "line \(index + 1): expected \(String(describing: left)) got \(String(describing: right))"
        }
    }
    return "identical"
}
