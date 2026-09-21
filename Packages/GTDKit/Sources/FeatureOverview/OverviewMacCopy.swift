import Foundation
import GTDModel
import DesignSystem

/// Copy and layout numbers of the Mac window added after the first walkthrough (2026-09-19).
/// Same pattern as `OverviewCopy`: no view inlines a user-facing string or a magic number.
enum OverviewMacCopy {
    // Empty detail column, per section (`SidebarItem.emptyDetailBody`).
    static let pickAnAction = "Pick an action from the list."
    static let pickAProject = "Pick a project from the list."
    /// T10 — the `Lists` sidebar row's detail column, before anything is selected.
    static let pickAnItem = "Pick an item from one of the lists."
    static let inboxIsProcessed = "Inbox items are processed in order, not opened one by one."

    static let overdue = "Overdue"

    /// `+2` — the markers of one day that did not fit.
    static func more(_ count: Int) -> String { "+\(count)" }

    /// The label above one day of the calendar strip. One short word that never wraps:
    /// `today`, `Tmrw`, a weekday (`Thu`) for the rest of the week, then `28 Sep`.
    /// ("tomorrow" used to wrap to "to-/mor-/row" in a 14-column strip.)
    static func stripDayLabel(_ day: Day, today: Day) -> String {
        day.days(since: today) == 1 ? "Tmrw" : DateText.short(day, today: today)
    }
}

/// Column and window sizes of the Mac shell (STYLEGUIDE §4.1). Public because the app shell
/// sizes the window from them, so the window can never be narrower than its columns.
public enum OverviewLayout {
    public static let sidebarMinWidth: CGFloat = 180
    public static let sidebarIdealWidth: CGFloat = 210
    public static let sidebarMaxWidth: CGFloat = 320

    /// Below this the list rows hyphenate titles and squeeze their badges.
    public static let listMinWidth: CGFloat = 380
    public static let listIdealWidth: CGFloat = 460

    public static let detailMinWidth: CGFloat = 320
    public static let detailIdealWidth: CGFloat = 380

    /// Sidebar + list + detail at their minimum, plus room for the column dividers.
    public static let windowMinWidth: CGFloat = 1000
    public static let windowMinHeight: CGFloat = 600

    /// Markers the calendar strip shows per day before it says `+n` (STYLEGUIDE §3.10).
    public static let stripMarkersPerDay = 3
    /// Click target of one calendar-strip marker.
    public static let stripMarkerHitSize: CGFloat = 24
    public static let stripDayMinWidth: CGFloat = 40
}
