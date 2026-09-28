import Foundation
import GTDModel

/// Creates a new, empty vault (#60): `<location>/<name>/` plus the folder skeleton the app's
/// layout expects (`VaultLayout.requiredFolders`), so onboarding can offer "Create new vault"
/// next to picking an existing folder.
///
/// **It never writes into a folder that already has content.** The target folder may exist only
/// when it is empty (Finder's `.DS_Store` aside); anything else is a `Refusal` and nothing is
/// written. The new vault holds folders only — no sample notes, no `GTD/Config.md` (a missing
/// config reads as the defaults, and the first settings change writes it).
///
/// The caller owns security-scoped access to `location` (`VaultBookmark.withAccess(to:_:)`).
public enum VaultCreator {

    /// Why a vault was not created. Nothing was written when one of these is thrown.
    public enum Refusal: Error, Equatable, LocalizedError {
        /// The name is empty once trimmed.
        case emptyName
        /// The name starts with "." — the folder would be invisible in Finder and Files.
        case hiddenName(String)
        /// The chosen location is missing or is not a folder.
        case locationMissing(String)
        /// `<location>/<name>` is a file.
        case notAFolder(String)
        /// `<location>/<name>` is a folder that already has content.
        case notEmpty(String)

        public var errorDescription: String? {
            switch self {
            case .emptyName:
                "Give the new vault a name."
            case let .hiddenName(name):
                "\"\(name)\" would be a hidden folder. Pick a name that does not start with a dot."
            case let .locationMissing(path):
                "The chosen location \(path) is not a folder. Pick another location."
            case let .notAFolder(name):
                "A file called \"\(name)\" is already there. Pick another name or location."
            case let .notEmpty(name):
                "A folder called \"\(name)\" already exists there and is not empty — nothing was "
                    + "written. Pick another name or location."
            }
        }
    }

    /// Files that do not count as content: Finder drops `.DS_Store` into any folder it shows.
    static let ignorableEntries: Set<String> = [".DS_Store"]

    /// The folder name a typed vault name becomes: trimmed and sanitised like every other file
    /// name the app writes (`VaultLayout.sanitize`). Refuses an empty or hidden name rather than
    /// inventing "Untitled".
    public static func folderName(for typed: String) throws -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Refusal.emptyName }
        guard !trimmed.hasPrefix(".") else { throw Refusal.hiddenName(trimmed) }
        return VaultLayout.sanitize(trimmed)
    }

    /// Creates `<location>/<name>` and the layout's folders inside it; returns the vault root.
    ///
    /// An existing **empty** folder of that name is used as is; a non-empty one, or a file, is
    /// refused before anything is written.
    @discardableResult
    public static func create(
        named typed: String,
        in location: URL,
        layout: VaultLayout = .default,
        fileManager: FileManager = .default
    ) throws -> URL {
        let name = try folderName(for: typed)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: location.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw Refusal.locationMissing(location.path) }

        let root = location.appendingPathComponent(name, isDirectory: true)
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw Refusal.notAFolder(name) }
            let entries: [String]
            do {
                entries = try fileManager.contentsOfDirectory(atPath: root.path)
            } catch {
                throw VaultError.ioFailed(path: root.path, reason: "\(error)")
            }
            guard entries.allSatisfy(ignorableEntries.contains) else { throw Refusal.notEmpty(name) }
        } else {
            do {
                // Not `withIntermediateDirectories`: the location exists, and a create that
                // loses a race to another writer must fail rather than adopt its folder.
                try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
            } catch {
                throw VaultError.ioFailed(path: root.path, reason: "\(error)")
            }
        }

        // Folders only: `createDirectory` never replaces anything, and the root was empty.
        for folder in layout.requiredFolders {
            let url = root.appendingPathComponent(folder, isDirectory: true)
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw VaultError.ioFailed(path: url.path, reason: "\(error)")
            }
        }
        return root
    }
}
