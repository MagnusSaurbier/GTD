import Foundation

/// The path the conflict sheet writes to, from the folder the note lives in and the title the
/// person typed (Foundation-only, tested on Linux). A title *is* a file name, so it is trimmed,
/// a slash would create a folder and becomes a dash, and an empty title is no path at all.
public enum MergedNote {
    public static func path(folder: String, title: String) -> String? {
        let name = title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return folder.isEmpty ? "\(name).md" : "\(folder)/\(name).md"
    }
}
