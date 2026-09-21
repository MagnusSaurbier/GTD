#if canImport(SwiftUI)
import SwiftUI
import GTDAppCore

extension EnvironmentValues {
    /// The device's key table (R-10, N7). The app shell sets it from `DeviceSettings.keyBindings`;
    /// the inbox card, "Make action" and the review deck read it, so a rebind in
    /// Settings › Keyboard reaches every legend and key handler. Defaults to I9's keys.
    @Entry public var keyBindings: KeyBindings = .defaults
}
#endif
