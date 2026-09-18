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

_(fill in when done)_
