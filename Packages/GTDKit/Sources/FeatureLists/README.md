# FeatureLists

Lists home, one list's items, the title+notes item editor and **Make action** (§5a, L1–L6).

## Public API

- `ListsHomeView()` — iPhone Lists tab (STYLEGUIDE §4.2): a stock `List` of lists with counts.
  Pushes `ListItemsView` via `NavigationLink(value: ListsRoute.list(_:))`; `App/PhoneShell` owns
  the tab's `NavigationStack` and its `.navigationDestination(for: ListsRoute.self)`, the same way
  it does for the Next tab's `[NoteID]` push.
- `ListItemsView(list:)` — one list's items: `ListItemRow`s (completion circle + title only,
  §3.3), trailing swipe `Done`, context menu `Make action` / `Trash`, a quiet `Show done` button
  revealing `Lists/<name>/Done/`. Pushes `ListItemEditorView` via `ListsRoute.item(_:)`.
- `ListItemEditorView(item:)` — the title + notes editor (autosaving, no Save button), with
  `Make action` in the toolbar. Shared by the iPhone push destination and the Mac detail column.
- `ListsSectionsView(selection:onOpen:)` — the Mac content column for the single `Lists` sidebar
  row (STYLEGUIDE §4.1): every list as a `Section` (name + open count header, `Show done` at the
  end when it has finished items), a stock selectable `List` exactly like
  `FeatureOverview.ActionListView`'s macOS list.
- `MakeActionSheet(model:item:)` — L4: hosts `FeatureInbox.MakeActionCardView` in a sheet, driven end to end by
  `FeatureInbox.MakeActionModel`. It holds no view code of its own — the card is the inbox's.
- `ListsModel(model:)` — rows with counts (`Rules.listRows`), a list's open/finished items,
  `complete`/`trash` (both go through `AppModel.perform`, so a refusal reaches the shell's alert),
  and `makeActionModel(for:)`.
- `ListItemEditModel(model:id:)` — the title/notes autosave brain, the same shape as
  `FeatureOverview.ActionEditModel` reduced to the two fields a list item has: dirty-field overlay
  so a snapshot arriving mid-edit never clobbers an edit in flight, `send(deriving:)` so the
  written command is always built from the *current* snapshot (ARCHITECTURE §4 "Command order"),
  and rename-following since a title change moves the file.
- `ListsRoute` — the iPhone push stack's route type (`.list(String)` / `.item(NoteID)`).

Linux-compilable (and therefore tested): `ListsModel`, `ListItemEditModel`, `ListsRoute`,
`ListsCopy`.

## Invariants

- List items never reach `Rules`' action/stats/notification/review queries — nothing here changes
  that; `ListsModel` only reads `Rules.listRows`/`listItems`/`openListItemCount`.
- Adding items from inside this target is out of scope (STYLEGUIDE, REQUIREMENTS §12 sibling
  rule): items arrive only through the inbox (`InboxDecision.list`).
- Every row/editor command goes through `AppModel.perform`/`send`, never `try? await …` — a
  refusal (`titleCollision`, `notFound`) must reach the person.

## Gotchas

- The three SwiftUI files are wrapped entirely in `#if canImport(SwiftUI)` and **unverified on
  Linux, blind-written** — verify the two-level push, the Mac sections list and the `Make action`
  sheet on a Mac.
- `MakeActionSheet` depends on `FeatureInbox` (permitted: ARCHITECTURE §2, the same direction
  `FeatureReview` already takes for `InboxSession`) but never on `FeatureInbox`'s SwiftUI files,
  which stay `internal` there.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureListsTests` — 18 tests.
