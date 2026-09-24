# DesignSystem

Every token, component and string of `docs/STYLEGUIDE.md`. Feature code contains **no** literal
colours, sizes, durations, symbol names or user-facing strings — it references this target.

## Public API

Platform-free (compiles on Linux, unit-tested):
- `Spacing`, `Radius`, `Elevation`, `MotionTiming`, `ShakeMetrics`, `DragThresholds` — the numbers
  of §2.4/§3.6/§5.
- `Symbols` — the exhaustive SF Symbols map of §7, including `Symbols.list(named:)` (the three
  named lists' own glyph, `listBullet` fallback for a custom list).
- `Copy` — the fixed vocabulary of §6.2 and the canonical strings of §6.3; `DateText` — date and
  age wording of §6.3, written without `DateFormatter`.
- `ChipState { unset, suggested, confirmed, disabled }`, `BadgeContent`,
  `SignalPresentation.badge(for:today:)` / `.badges(for:today:)` — the only place that turns a
  `GTDModel.Signal` into text and a symbol.
- `CardDragGeometry` — the pure drag-to-file maths behind `ItemCard` (§3.6): axis lock, per-
  direction thresholds, rotation, exit offset. `FlowLayoutEngine` — the row-wrapping algorithm
  behind `FlowLayout` (§3.1). `MonthGrid(year:month:)`/`MonthGrid(containing:)` — one month as six
  full Monday-first ISO weeks, with `contains(_:)`, `previous`/`next` and the header titles, behind
  the SwiftUI `DayPicker` (§3.1's date chips). `NavbarPlatform`/`NavbarSlot`/`NavbarLayout.slots(favourites:platform:)`
  — the Knowledge/List navbar's fixed-slot layout (§3.6): which slots exist for N favourites and a
  platform limit (4 on iPhone, 8 on Mac), in which order, with which Mac key index.
  `AppVersion(infoDictionary:)` / `.current` — the bundle's version as the corner stamp
  (`stampLabel`: `0.2`), Settings (`settingsLabel`: `0.2 (1)`) and VoiceOver (`spokenLabel`) word
  it; an unversioned bundle reads as empty, never as an invented "1.0". All are
  unit-tested directly; the SwiftUI types below are thin wrappers over them.

SwiftUI (inside `#if canImport(SwiftUI)`):
- `Color.ink`/`inkInverse`/`textSecondary`/`textTertiary`/`surface`/`surfaceGrouped`/`surfaceCard`/
  `hairline`/`fillQuiet`/`gtdAccent`/`accentWash`/`signalAging`/`signalAttention`/`signalOverdue`/
  `signalDone`, `Color.dynamic(light:dark:)`.
- `Typo`, `Motion`, `Radius.chipShape`/`cardShape`/`tileShape`, `View.cardElevation()`,
  `View.shake(trigger:)` (§3.6/§5's validation shake — 6 pt, 0.3 s, a no-op under Reduce Motion).
- `Chip`, `FlowLayout`, `ContextChipGroup`, `TimeBucketChipGroup`, `DateValueChip`,
  `DayPicker(selection:today:onPick:)` — the app's own month calendar the date chips open
  (popover on Mac, medium sheet on iOS): one click on a day calls `onPick` and the chip writes
  the date and closes the picker. It replaced the stock graphical `DatePicker`, whose clicks
  never reached the chip's binding on macOS, so no date could be picked at all (2026-09-24).
  Its calendar arithmetic is `MonthGrid` (Foundation-only, tested on Linux).
- `VersionStamp(version:)` — the version in the bottom-right corner of both shells
  (`Typo.counter`, `textTertiary`, no hit testing); draws nothing without a version.
- `Badge`, `ActionRow`, `ListItemRow` (§3.3 "List items": completion circle + title only, no
  second line, no badges, no age), `ProjectRow`, `ItemCard`, `CollapsibleText`,
  `View.itemCardPeek(hasNext:)`, `UndoToast`,
  `SectionLabel(_:isMissing:font:foreground:)` — a field/chip-group label with the required-field
  asterisk (§3.6: leading `asterisk` in `signalAttention`, VoiceOver says "required"),
  `WaitingInfoSheet(initial:suggestedWho:today:onSave:)` — follow-up date **required** (+7 d is a
  suggested chip until confirmed), who optional, `Set waiting` disabled until a date is confirmed.
- Sheets that scroll (`Components/SheetScrolling.swift`, sizes in `SheetMetrics`):
  `View.sheetFormStyle()` for every `Form` in a sheet — `.formStyle(.grouped)` plus the Mac sheet
  frame; macOS' default `.columns` never scrolls and draws a text field's title as a left-column
  label. `View.scrollingSheetFrame()` for a `List` in a sheet — min/ideal size on macOS, a no-op
  on iOS (detents size the sheet there). `OverflowScroll { rows }` for an unbounded `ForEach`
  inside a content-sized `VStack` sheet: inline while it fits, scrolling past
  `SheetMetrics.inlineRowsMaxHeight`. Never pin a sheet to a fixed height.
- `GlassActionBar` (the generic capsule) and its three STYLEGUIDE §3.6 variants:
  `StepOneBar` (three equal, neutral, symbol-over-text buttons — none accent-filled),
  `ActionCardBar` (`Waiting`/`Done` buttons + `⋯` "File to" menu → Next/Someday; swaps to a single
  `Done` button while a field is focused), `KnowledgeListNavbar` (the fixed-slot navbar, built on
  `NavbarLayout`).
- Drag-to-file (§3.6): `CardDragDirection`, `CardFilingController` (`@Observable`; one per card —
  owns the live `translation`/`previewDirection`/`previewProgress`, and `dismiss(to:onFile:)` for
  Mac-key/VoiceOver filing), `View.cardSwipeFiling(controller:isEnabled:onFile:)` (the gesture),
  `View.cardDragOverlay(controller:tint:label:)` (the destination label + tint). FeatureInbox owns
  which GTD target each direction files to (`FeatureInbox.CardTarget`/`DragResolver`); this target
  only owns the geometry and the gesture.
- Drag-to-category (E3, `Interaction/NoteDragging.swift`): `NoteDragItem` (the `Transferable`
  a dragged row carries — the `NoteID` under an app-private UTType, so nothing leaves the app),
  `View.draggableNote(_:)` for a row, `View.noteDropTarget(isTargeted:accepts:perform:)` and
  `NoteDropRow { }` (drop target + the `accentWash` row tint while targeted) for a section or
  project row, the `\.moveNote` environment (`MoveNoteHandler`: `accepts`/`move` over
  `GTDAppCore.MoveDestination`, set by the shell that hosts the dialogues, `nil` where there is
  nowhere to move to) and `MoveToMenu(id:)`, the drag's context-menu twin (renders nothing
  without a handler). `DeferDateSheet(initial:today:onConfirm:)` — a `DateValueChip` in the
  smallest sheet that can hold one, for a defer date asked outside a card.
- Reward moments (§5): `RewardMoment.inboxZero(processed:minutes:)`,
  `.routineComplete(routine:done:total:)`, `.reviewComplete(done:total:)` — no third kind.
- Review pieces (§3.10, Mac-only): `StatTile`, `RoutineHeatmap` (+ `HeatmapCellState`),
  `ReviewWizardRail`, `KeyLegendRow`.
- `DesignGallery` — every component, every state, for review (`#Preview`s: light, dark, AX1).

## Invariants

- **Shape carries state, not hue:** outline = undecided, dashed + `sparkles` = suggested,
  ink fill = confirmed. A suggestion is never persisted until the user confirms it.
- Badge wording comes from `SignalPresentation` — never invented at the call site. Max two
  badges per row, highest step first.
- Empty states use stock `ContentUnavailableView`; there is no custom empty-state component.
- Colours are **code-defined**, so nothing breaks when the asset catalog is not compiled
  (ARCHITECTURE §5). Tests never assert on resolved colours or catalog lookups.
- Chip haptic (`.selection`), row-complete haptic (`.success`) and the drag threshold haptic
  (`.impact(.medium)`) use `.sensoryFeedback` — no `UIFeedbackGenerator` import, so nothing here
  is iOS-only at the type level (the modifier itself is inert on platforms without haptics).
- `GlassActionBar`/`UndoToast` use `.glassEffect()` inside one `GlassEffectContainer` behind
  `if #available(iOS 26, macOS 26, *)`, falling back to `.ultraThinMaterial` (or `surfaceCard` +
  hairline under Reduce Transparency) otherwise. ARCHITECTURE §1 sets the deployment target at
  iOS 26/macOS 26 with "no availability checks" as a general rule; this one check stays because
  this container cannot compile a single line of SwiftUI to confirm `.glassEffect()`'s exact
  availability annotation or its default shape — see docs/history/build-out/12-design-system.md Result.

## Ownership and gotchas

Every token, component, symbol and user-facing string the app uses lives here; feature code
holds none of them. Adding is normal, renaming is a cross-target change.
- `DesignSystem` does not depend on `GTDFixtures` (ARCHITECTURE §2: `GTDModel` + `GTDAppCore`
  only), so `DesignGallery` builds its sample data inline rather than importing fixtures. The
  `Feature*` targets do `import GTDFixtures` in their `#Preview`s, and `featureDeps` in
  `Package.swift` lists it for them.
- `RewardMoment` is the **only** implementation of the two reward moments of STYLEGUIDE §5 —
  inbox zero and routine/review complete. A feature that needs one composes it (`FeatureInbox` replaced
  `FeatureInbox`'s second copy); nothing invents a third. Its hero symbol still uses
  `.font(.system(size: 56))`, which §2.3 forbids — see `TEST-INSTRUCTIONS.md` "Unresolved".
- An unset "add a value" chip (`DateValueChip`, `ProjectPicker`) draws `Symbols.addValue` and takes
  its title from `Copy.unsetChipTitle(_:)` — no literal "+", first letter capitalised. `Chip` /
  `DateValueChip` take an optional `signal:` that tints a **confirmed** chip with the `Badge`
  colour formula (Waiting's passed follow-up date). `Badge` is `.fixedSize()` — never squeezed.
- `Symbols.checkboxOn/Off`, `Symbols.moveUp/moveDown`, `Symbols.back/rename/addValue`, and
  `Typo.rowIcon/controlGlyph`, exist
  so feature code contains no literal symbol name or font (STYLEGUIDE §9). None of them is a §7
  concept icon or a §2.2 signal; they are stock control affordances named in one place.
- Everything in `Components/`, `Interaction/`, `DesignGallery.swift` and `Tokens/Colors.swift`,
  `Tokens/Typography.swift` was written without a SwiftUI compiler and is **unverified** — see the
  task's Result for the full file list and what to check first on a Mac.
- `Copy`'s strings are still plain `String` constants, not `LocalizedStringResource`s backed by
  `Resources/Localizable.xcstrings` — left as-is since it cannot be verified under `xcodebuild`
  here either; a Mac-side follow-up, not a blocker (call sites do not change either way).

- **T06 (2026-09-21, inbox rework).** `WaitingInfoSheet` now requires the follow-up date and
  makes `who` optional (W1/D39 reversed the old "who and date" requirement); its save button is
  `Set waiting`, disabled until a date is confirmed, and sends `who: nil` for a blank field rather
  than an empty string. `ActionRow` and `ListItemRow` share one private `CompletionCircle` — the
  check-draw animation lives in one place. `StepOneBar`/`ActionCardBar`/`KnowledgeListNavbar` are
  the only place a feature should reach for the inbox card's bars; a feature target building its
  own `GlassActionBar` row for one of these three purposes is duplicating this file.
- **Accessibility wording is Linux-testable on purpose.** `HeatmapContent.swift` (the
  `HeatmapCellState` cases and `HeatmapSpeech.week`) and `Copy.metaLine`/`Copy.spoken` sit outside
  the SwiftUI guard, so what VoiceOver reads for a heatmap row and for a row's meta line is
  covered by `AccessibilityTextTests` instead of being a claim in a doc comment. Anything that
  carries meaning by colour or position belongs in that shape.
- Sizes that sit under text are `@ScaledMetric`, not constants: the heatmap grid, `Badge`'s
  capsule height. A fixed frame around text clips at the accessibility sizes (STYLEGUIDE §8).

## Testing

`cd Packages/GTDKit && swift test --filter DesignSystemTests` — 47 tests.

`Interaction/KeyBindingsEnvironment.swift` — `EnvironmentValues.keyBindings` (R-10): the shell sets it from
`DeviceSettings.keyBindings`; the inbox card, `MakeActionSheet` and the review deck read it.

`Interaction/VaultRootEnvironment.swift` — `EnvironmentValues.vaultRootPath`: the vault folder's
absolute path, set by the app shell (`RootView` and the Mac `Settings` scene), `nil` on fixtures.
Its one use is `GTDAppCore.ObsidianLink`.

`Interaction/Clipboard.swift` — `Clipboard.copy(_:)`: the general pasteboard (`NSPasteboard` /
`UIPasteboard`) behind one call, so a feature never imports AppKit or UIKit for it. Used by the
detail view's "Copy path" button.
