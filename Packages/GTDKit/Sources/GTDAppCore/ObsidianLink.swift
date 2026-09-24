import Foundation
import GTDModel

/// "Open in Obsidian": the one place an `obsidian://open` URL is built.
///
/// Obsidian's URI scheme has two ways to name a note, and they are not interchangeable:
/// `path=` must be an **absolute** file-system path (Obsidian looks for the vault containing
/// it; a vault-relative path fails with "Vault not found"), while a vault-relative path goes
/// in `file=` next to `vault=<vault folder name>`.
///
/// The Mac uses `path=`: the app and Obsidian see the same file system, and it still works when
/// two vaults share a folder name or the picked folder sits inside a larger vault. iOS uses
/// `vault=&file=`: the path the app gets from its security-scoped bookmark is not known to be
/// the one Obsidian's own sandbox uses. Either way the vault root is required — feature targets
/// never see it themselves, so the app shell hands it down through `\.vaultRootPath`
/// (`DesignSystem`). Without one (fixtures, no vault picked) there is no link.
public enum ObsidianLink {

    public enum Form: Sendable {
        /// `obsidian://open?path=<absolute path>`
        case absolutePath
        /// `obsidian://open?vault=<vault folder name>&file=<vault-relative path>`
        case vaultAndFile

        public static var platformDefault: Form {
            #if os(macOS)
            .absolutePath
            #else
            .vaultAndFile
            #endif
        }
    }

    public static func url(for id: NoteID, vaultRoot: String?, form: Form = .platformDefault) -> URL? {
        url(forVaultPath: id.path, vaultRoot: vaultRoot, form: form)
    }

    /// The note's absolute file-system path, for "Copy path" next to "Open in Obsidian": what a
    /// terminal or a `/do <path>` prompt takes. Unescaped — it is not a URL. `nil` exactly when
    /// `url(for:vaultRoot:)` is.
    public static func filePath(for id: NoteID, vaultRoot: String?) -> String? {
        filePath(forVaultPath: id.path, vaultRoot: vaultRoot)
    }

    public static func filePath(forVaultPath relativePath: String, vaultRoot: String?) -> String? {
        let relative = relativePath.trimmingSlashes
        guard let vaultRoot, !relative.isEmpty else { return nil }
        let root = vaultRoot.trimmingTrailingSlashes
        guard !root.isEmpty else { return nil }
        return "\(root)/\(relative)"
    }

    /// `relativePath` is vault-relative (`NoteID.path`, `Project.referenceFiles`,
    /// `VaultIssue.path`). `nil` when the vault root is unknown or either part is empty.
    public static func url(forVaultPath relativePath: String, vaultRoot: String?, form: Form = .platformDefault) -> URL? {
        let relative = relativePath.trimmingSlashes
        guard let vaultRoot, !relative.isEmpty else { return nil }
        let root = vaultRoot.trimmingTrailingSlashes
        guard let name = root.split(separator: "/").last.map(String.init) else { return nil }

        let query: String
        switch form {
        case .absolutePath:
            query = "path=\(encode("\(root)/\(relative)"))"
        case .vaultAndFile:
            query = "vault=\(encode(name))&file=\(encode(relative))"
        }
        return URL(string: "obsidian://open?\(query)")
    }

    /// Everything but RFC 3986's unreserved characters is escaped, as `encodeURIComponent` does
    /// and Obsidian's own examples show (`%2F` for `/`, `%20` for a space). `.urlQueryAllowed`
    /// would leave `&`, `=`, `+` and `#` raw, which cuts a file name short at that character.
    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

private extension String {
    var trimmingTrailingSlashes: String {
        var result = self
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }

    var trimmingSlashes: String {
        var result = trimmingTrailingSlashes
        while result.hasPrefix("/") { result.removeFirst() }
        return result
    }
}
