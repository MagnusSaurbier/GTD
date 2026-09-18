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

SwiftUI (inside `#if canImport(SwiftUI)`):
- `Color.ink`/`inkInverse`/`textSecondary`/`textTertiary`/`surface`/`surfaceGrouped`/`surfaceCard`/
  `hairline`/`fillQuiet`/`gtdAccent`/`accentWash`/`signalAging`/`signalAttention`/`signalOverdue`/
  `signalDone`, `Color.dynamic(light:dark:)`.
- `Typo`, `Motion`, `Radius.chipShape`/`cardShape`/`tileShape`, `View.cardElevation()`.
- `Chip`, `FlowLayout`, `ContextChipGroup`, `TimeBucketChipGroup`, `DateValueChip`,
  `Badge`, `ActionRow`, `ProjectRow`, `ItemCard`, `UndoToast`, `GlassActionBar`,
  `WaitingInfoSheet(initial:suggestedWho:today:onSave:)`.

## Invariants

- **Shape carries state, not hue:** outline = undecided, dashed + `sparkles` = suggested,
  ink fill = confirmed. A suggestion is never persisted until the user confirms it.
- Badge wording comes from `SignalPresentation` — never invented at the call site. Max two
  badges per row, highest step first.
- Empty states use stock `ContentUnavailableView`; there is no custom empty-state component.
- Colours are **code-defined**, so nothing breaks when the asset catalog is not compiled
  (ARCHITECTURE §5). Tests never assert on resolved colours or catalog lookups.

## Ownership and gotchas

T00 froze the API; **T12 refines the visuals behind it (additions only)**. Two things T12 must
finish once a Mac is available: adopt `.glassEffect()` in a `GlassEffectContainer` for
`GlassActionBar`/`UndoToast` (T00 uses `.ultraThinMaterial`), and move `Copy`'s strings into
`Resources/Localizable.xcstrings` as `LocalizedStringResource`s — the keys stay the same, so call
sites do not change. Everything in `Components/` and `Tokens/Colors.swift`,
`Tokens/Typography.swift` was written without a compiler for SwiftUI and is **unverified**.

## Testing

`cd Packages/GTDKit && swift test --filter DesignSystemTests`.
