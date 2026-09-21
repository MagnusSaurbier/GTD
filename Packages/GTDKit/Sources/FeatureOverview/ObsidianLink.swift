import Foundation
import GTDModel

/// "Open in Obsidian" (E3): `obsidian://open?path=<file>`.
///
/// Obsidian resolves `path` as a **file-system path**, so the link is only exact when the app
/// knows where the vault lives. Feature targets never see the vault URL (only `GTDVault` does),
/// so the app shell passes it down through `\.vaultRootPath`; without it the link carries the
/// vault-relative path, which Obsidian still resolves when the vault is the active one.
public enum ObsidianLink {

    public static func url(for id: NoteID, vaultRoot: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path(for: id, vaultRoot: vaultRoot))]
        return components.url
    }

    static func path(for id: NoteID, vaultRoot: String?) -> String {
        guard let vaultRoot, !vaultRoot.isEmpty else { return id.path }
        let root = vaultRoot.hasSuffix("/") ? String(vaultRoot.dropLast()) : vaultRoot
        return "\(root)/\(id.path)"
    }
}
