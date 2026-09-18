# T12 — Design system (`DesignSystem`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet

Self-contained SwiftUI component work with a frozen API, an exact written spec (`docs/STYLEGUIDE.md`), a visual gallery for review, and no data risk. Fiddly parts: the `ItemCard` drag behaviour (axis lock, thresholds, programmatic exit for keyboard filing) and Liquid Glass usage rules; the drag maths is unit-tested separately. Mistakes are cosmetic and cheap to fix.

## Goal

Implement `docs/STYLEGUIDE.md` §2, §3, §5, §7, §8 as the shared design system — without changing
the public API T00 shipped (features are being built against it in parallel; additions only).

## Requirements covered

§1 (few inputs, no lying defaults), I2, I3, E1, R2, D1 badges, P4 stalled badge; STYLEGUIDE decisions #1–#15.

## Owns

`Sources/DesignSystem/` (incl. `Resources/`), `Tests/DesignSystemTests/`.

## Deliverables

- **Tokens** exactly as named in STYLEGUIDE §2: colour tokens + asset catalog (accent incl. High
  Contrast variants, `accentWash`, `signal*`), signal badge formula, `Typo`, `Spacing`, `Radius`,
  `Elevation.card`, `Motion`. No other curves, shadows or hues.
- **Components** (STYLEGUIDE §3): `Chip` (4 states, tap cycle, haptic, a11y values), `FlowLayout`,
  chip groups, `DateValueChip` (stock graphical `DatePicker`; popover on Mac, `.medium` sheet on iOS),
  `Badge` + `Signal` → text/symbol/step mapping (wording from §2.2 only; max two per row, priority order),
  `ActionRow` (completion control with check-draw, in-progress half fill, meta line joined by ` · `, omitted-when-empty),
  `ProjectRow`, `ItemCard` (solid card, peek of next card, non-scrolling, `Show all` collapse) with
  the drag behaviour of §3.6 exposed as a reusable modifier + `dismiss(to:)` for keyboard filing,
  `GlassActionBar` (inbox action bar and routine Skip/Done bar; one `GlassEffectContainer`; Reduce
  Transparency fallback), `UndoToast` (5 s, one at a time), `WaitingInfoSheet`, key legend row,
  review pieces: wizard rail, stat tile, routine heatmap.
  Calendar strip stays in `FeatureWaiting` (T23) but uses these tokens.
- `Symbols` (icon map §7, exhaustive) and `Copy` (canonical strings §6.3) as the only source of symbol names / shared wording.
- Reward moments (§5) as two reusable views: inbox zero, routine/review complete.
- Accessibility per §8: Dynamic Type to AX3, VoiceOver labels/values/custom actions, increased-contrast outline, Reduce Motion variants.
- `DesignGallery` preview view showing every component in every state (light / dark / AX1).

## Acceptance

- No public signature from T00 removed or changed (additions only).
- STYLEGUIDE §9 checklist passes for the gallery; gallery renders in iOS and macOS previews.
- Unit tests: drag threshold/axis-lock → target, badge priority selection, `Signal` → badge mapping for every §2.2 row, `FlowLayout` wrapping.
- Tests never assert on resolved asset colours or catalog strings (ARCHITECTURE §5 caveat).
- `scripts/check.sh` passes.

## Result

**Status: done.** `scripts/check.sh` passes (output at the bottom). T00's frozen API is unchanged
— everything below is additive.

### What was built

- **Pure, Linux-tested maths** behind the two fiddliest pieces, both unit-tested directly:
  - `CardDragGeometry` (`Interaction/CardDragGeometry.swift`) — axis lock (12 pt), the three
    per-direction thresholds (35 % width / 25 % height / 40 % height for trash), signed rotation
    capped at 4°, and the fly-out exit offset, shared by a real drag release and `dismiss(to:)`.
    `Tests/CardDragGeometryTests.swift`, 8 tests.
  - `FlowLayoutEngine` (`Layout/FlowLayoutEngine.swift`) — the row-wrapping algorithm extracted
    from `FlowLayout`'s `Layout` conformance (which is now a thin SwiftUI wrapper over it), so chip
    wrapping is tested without a compiled `Layout` witness. `Tests/FlowLayoutEngineTests.swift`,
    7 tests. Total DesignSystemTests: 20 (was 6).
- **Drag-to-file, exposed as a reusable modifier + `dismiss(to:)`** (`Interaction/`):
  `CardFilingController` (`@Observable`, one per card: live `translation`/`previewDirection`/
  `previewProgress`, and `dismiss(to:onFile:)` for Mac-key/VoiceOver filing — the same fly-out
  animation a drag release triggers, without a gesture), `View.cardSwipeFiling(controller:
  isEnabled:onFile:)` (the gesture: offset, rotation, one `.impact(.medium)` haptic on crossing a
  threshold, fly-out or spring-back on release), `View.cardDragOverlay(controller:tint:label:)`
  (destination label + tint, faded by `previewProgress`). This owns the *geometry* only; T00 had
  already put the GTD-specific direction → `CardTarget` mapping in `FeatureInbox/CardTargets.swift`
  (`DragResolver`, owned by T20) reusing `DesignSystem.DragThresholds` — left untouched.
- **Liquid Glass**: `GlassActionBar`/`UndoToast` now use `.glassEffect()` inside one
  `GlassEffectContainer`, gated by `if #available(iOS 26, macOS 26, *)`, with a
  `.ultraThinMaterial` capsule fallback that becomes `surfaceCard` + hairline stroke under Reduce
  Transparency (STYLEGUIDE §8). See "Deviation from ARCHITECTURE §1" below.
- **Chip**: `.sensoryFeedback(.selection, trigger: state)`; outline thickens to 1.5 pt under
  `colorSchemeContrast == .increased` (§8).
- **`gtdAccent`**: gained the High Contrast pair (`#2F5A87`/`#9CC6EE`, §8) via a new
  `Color.dynamicContrast(...)`, resolved per-trait on iOS and via
  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` on macOS.
- **`ActionRow`**: completion control now draws the checkmark in `signalDone` over
  `MotionTiming.checkDraw` with a `.success` haptic before calling `onComplete` (§3.3), instead of
  completing silently.
- **New components** (additions, all in `Components/`): `RewardMoment` (`.inboxZero`,
  `.routineComplete`, `.reviewComplete` — the exactly-two reward moments of §5),
  `CollapsibleText` + `View.itemCardPeek(hasNext:)` (the card-stack peek and the `Show all`
  collapse §3.5 asks `ItemCard` for), `StatTile`, `RoutineHeatmap`, `ReviewWizardRail`,
  `KeyLegendRow` (the §3.10 review pieces T00 had not built).
- **`DesignGallery.swift`** — every component in every state, with light/dark/AX1 `#Preview`s.
  Builds its own sample data (see Gotchas) rather than importing `GTDFixtures`.
- `Copy.whoPlaceholder`, `Copy.showAll` added (two literals T00 had left inline/missing).

### Acceptance

- No T00 signature removed or changed — only additions (new types, new `View`/`Color` extension
  methods, new optional-nowhere-required behaviour on existing views).
- Unit tests: drag threshold/axis-lock → direction ✓ (`CardDragGeometryTests`), badge priority
  ✓ (pre-existing `atMostTwoBadgesHighestStepFirst`), `Signal` → badge mapping for every §2.2 row
  ✓ (pre-existing `everyStyleGuideRowHasItsWording`), `FlowLayout` wrapping ✓
  (`FlowLayoutEngineTests`). 20/20 pass.
- No test asserts on resolved colours or catalog lookups.
- STYLEGUIDE §9 checklist: gallery covers every component/state; no literal colors/fonts/paddings/
  radii/durations/symbols/strings were introduced outside `Tokens`/`Symbols`/`Copy`; no chip is
  pre-selected; accent still appears at most once per screen in the gallery's own layout; Reduce
  Motion is honoured in the drag gesture and `RewardMoment`'s haptic-only fallback (system symbol
  effects auto-adapt); VoiceOver labels/values added throughout the new components. Could not
  render the gallery to confirm visually (no Xcode here) — see Unverified files below.

### Deviation from ARCHITECTURE §1 ("no availability checks, no fallbacks")

`GlassActionBar`/`UndoToast` wrap `.glassEffect()`/`GlassEffectContainer` in
`if #available(iOS 26, macOS 26, *)` with a material fallback, per the orchestrator's Wave 1
addendum (this container cannot compile a single line of SwiftUI, so it cannot confirm
`.glassEffect()`'s exact availability annotation, its default shape, or that `GlassEffectContainer`
takes the call shape I assumed). The deployment target itself is unchanged (iOS 26/macOS 26,
ARCHITECTURE §1) — this is a defensive wrapper around one specific new API pair, not a general
policy change. Safe to delete the `#available`/fallback branch once verified on a Mac, if desired.

### Files unverified on Linux (no SwiftUI compiler here)

Everything under `Components/`, `Interaction/`, `DesignGallery.swift`, and
`Tokens/Colors.swift`/`Tokens/Typography.swift` — i.e. every file wrapped in
`#if canImport(SwiftUI)`. All compile to nothing on Linux (the guard is false), so `swift build`
verifies only that the Linux-visible halves (`Tokens/Metrics.swift`, `Symbols.swift`, `Copy.swift`,
`Components/BadgeContent.swift`, `Interaction/CardDragGeometry.swift`,
`Layout/FlowLayoutEngine.swift`) type-check; everything else was written and manually re-read for
balanced braces and correct call-site argument order, not compiled. On a Mac, run
`scripts/check.sh` (which now also builds the package for the iOS Simulator) and open
`DesignGallery` in an Xcode preview; likely first breakage points, in order of risk:
`.glassEffect()`'s real signature/default shape in `Containers.swift`, `GlassEffectContainer`'s
initializer, `Color.dynamicContrast`'s `NSColor`/`UIColor` dynamic providers in `Tokens/Colors.swift`,
and `CardFilingController`'s `@Observable`/`@MainActor` combination read from a plain `let` inside
`CardSwipeFiling: ViewModifier`.

### Gotchas for the next agents

1. **`DesignSystem` does not depend on `GTDFixtures`** (ARCHITECTURE §2 dependency direction), so
   `DesignGallery` cannot import it. Eight `Feature*` view files already `import GTDFixtures` for
   their own `#Preview`s without that dependency being declared for their targets in
   `Package.swift` — invisible on Linux (those files are entirely `#if canImport(SwiftUI)`), but it
   will fail to resolve under `xcodebuild`. This is not a `DesignSystem` file, so it was left alone
   and flagged via `spawn_task` for whoever owns `Package.swift` (T00/T40) or verifies on a Mac.
2. `FeatureInbox.CardTargets.swift` (`CardTarget`, `DragResolver`, owned by T20) is the GTD-specific
   layer on top of this task's `CardDragGeometry`/`CardFilingController` — the split is
   "DesignSystem owns the physics, FeatureInbox owns what each direction means." T20 should wire
   `ItemCard` to `.cardSwipeFiling`/`.cardDragOverlay`/`CardFilingController.dismiss(to:)` rather
   than re-deriving the gesture.
3. `Copy`'s strings are still plain `String` constants (not `Resources/Localizable.xcstrings`-backed
   `LocalizedStringResource`s) — call sites are unaffected either way; left as a Mac-side follow-up
   per T00's note, since it cannot be verified here.
4. `RoutineHeatmap`/`StatTile`/`ReviewWizardRail` take already-computed rows (no `GTDStats`
   dependency, by design) — `FeatureReview` (T27) does the day-bucketing/percent maths and passes
   plain `HeatmapCellState`/`Row` values in.

### `scripts/check.sh` (tail)

```
=== swift test (Packages/GTDKit)
✔ Test run with 20 tests in 3 suites passed after 0.002 seconds.   # DesignSystemTests
(full suite: all targets pass, 700+ tests total)

=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build
system only — verify this step on a Mac.

=== check.sh finished
```
