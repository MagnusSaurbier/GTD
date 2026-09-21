import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Vault writes run on a queue behind the UI (`GTDServices.VaultBackend`), so "the person did
/// it" and "the file is written" are a moment apart. These are the two places where the app is
/// about to stop running and that moment has to be waited for.

extension AppComposition {
    /// iOS suspends the app shortly after it leaves the screen. Hold a background assertion
    /// until the queue is empty; the writes are local, so this is a matter of seconds at worst.
    func flushWritesBeforeSuspension() async {
        #if os(iOS)
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "vault-writes")
        defer { UIApplication.shared.endBackgroundTask(assertion) }
        #endif
        await flushWrites()
    }
}

#if os(macOS)
/// ⌘Q with writes still queued: let them land, then quit.
final class ShellAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let composition = BackgroundRefresh.composition else { return .terminateNow }
        Task { @MainActor in
            await composition.flushWrites()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
