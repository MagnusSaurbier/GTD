# DesignSystem

Every token, component and string of `docs/STYLEGUIDE.md`. Feature code contains **no** literal
colours, sizes, durations, symbol names or user-facing strings — it references this target.

## Public API

Platform-free (compiles on Linux, unit-tested):
- `Spacing`, `Radius`, `Elevation`, `MotionTiming`, `DragThresholds` — the numbers of §2.4/§3.6/§5.
- `Symbols` — the exhaustive SF Symbols map of §7.
- `Copy` — the fixed vocabulary of §6.2 and the canonical strings of §6.3; `DateText` — date and
  age wording of §6.3, written without `DateFormatter`.
- `ChipState { unset, suggested, confirmed, disabled }`, `BadgeContent`,
  `SignalPresentation.badge(for:today:)` / `.badges(for:today:)` — the only place that turns a
  `GTDModel.Signal` into text and a symbol.
- `CardDragGeometry` — the pure drag-to-file maths behind `ItemCard` (§3.6): axis lock, per-
  direction thresholds, rotation, exit offset. `FlowLayoutEngine` — the row-wrapping algorithm
  behind `FlowLayout` (§3.1). Both are unit-tested directly; the SwiftUI types below are thin
  wrappers over them.

SwiftUI (inside `#if canImport(SwiftUI)`):
- `Color.ink`/`inkInverse`/`textSecondary`/`textTertiary`/`surface`/`surfaceGrouped`/`surfaceCard`/
  `hairline`/`fillQuiet`/`gtdAccent`/`accentWash`/`signalAging`/`signalAttention`/`signalOverdue`/
  `signalDone`, `Color.dynamic(light:dark:)`.
- `Typo`, `Motion`, `Radius.chipShape`/`cardShape`/`tileShape`, `View.cardElevation()`.
- `Chip`, `FlowLayout`, `ContextChipGroup`, `TimeBucketChipGroup`, `DateValueChip`,
  `Badge`, `ActionRow`, `ProjectRow`, `ItemCard`, `CollapsibleText`, `View.itemCardPeek(hasNext:)`,
  `UndoToast`, `GlassActionBar`, `WaitingInfoSheet(initial:suggestedWho:today:onSave:)`.
- Drag-to-file (§3.6): `CardDragDirection`, `CardFilingController` (`@Observable`; one per card —
  owns the live `translation`/`previewDirection`/`previewProgress`, and `dismiss(to:onFile:)` for
  Mac-key/VoiceOver filing), `View.cardSwipeFiling(controller:isEnabled:onFile:)` (the gesture),
  `View.cardDragOverlay(controller:tint:label:)` (the destination label + tint). FeatureInbox owns
  which GTD target each direction files to (`FeatureInbox.CardTarget`/`DragResolver`); this target
  only owns the geometry and the gesture.
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
  availability annotation or its default shape — see agent_task/12-design-system.md Result.

## Ownership and gotchas

T00 froze the API; **T12 (this task) refines the visuals behind it (additions only)**.
- `DesignSystem` does not depend on `GTDFixtures` (ARCHITECTURE §2: `GTDModel` + `GTDAppCore`
  only), so `DesignGallery` builds its sample data inline rather than importing fixtures. Several
  `Feature*` view files already `import GTDFixtures` for their `#Preview`s without that target
  dependency being declared in `Package.swift` — invisible on Linux because those files are
  wrapped in `#if canImport(SwiftUI)`, but it will fail under `xcodebuild`. Not this task's file to
  fix (Package.swift is frozen); flagged for whoever verifies on a Mac.
- Everything in `Components/`, `Interaction/`, `DesignGallery.swift` and `Tokens/Colors.swift`,
  `Tokens/Typography.swift` was written without a SwiftUI compiler and is **unverified** — see the
  task's Result for the full file list and what to check first on a Mac.
- `Copy`'s strings are still plain `String` constants, not `LocalizedStringResource`s backed by
  `Resources/Localizable.xcstrings` — left as-is since it cannot be verified under `xcodebuild`
  here either; a Mac-side follow-up, not a blocker (call sites do not change either way).

## Testing

`cd Packages/GTDKit && swift test --filter DesignSystemTests`.
