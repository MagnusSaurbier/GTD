# T12 — Design system (`GTDDesign`)

**Wave 1 · needs T00**

## Goal

Turn the minimal T00 components into a coherent, calm visual language shared by all features —
without changing their public API (features are being built against it in parallel).

## Requirements covered

§1 (few inputs, no lying defaults, suggestions look different), I2, I3, E1, R2 (big buttons), D1 badges, P4 stalled badge.

## Owns

`Sources/GTDDesign/`, `Tests/GTDDesignTests/`.

## Deliverables

- Tokens: spacing, radii, typography, semantic colours (light/dark, increased contrast), status colours.
- Components (keep T00 signatures; add new ones freely):
  `ChipPicker`, `ContextChips`, `TimeBucketChips`, `DateChip` (defer / due / follow-up with quick
  picks: tomorrow, +3 d, +7 d, next Monday, custom), `ActionRow`, `ProjectLabel`, `Badge` variants,
  `CountBadge`, `CardContainer`, `SwipeCard` (drag in 4 directions with threshold, direction
  labels that fade in, haptics on iOS, programmatic `dismiss(to:)` for keyboard use),
  `BigChoiceButtons` (done / skip), `EmptyState`, `CapMeter` ("14 / 15"), `KeyHint` (Mac shortcut legend),
  `MarkdownTextEditor` (plain monospaced editor with checkbox toggling — no rich rendering).
- Three visual states for every metadata control: **empty**, **suggested** (dashed/ghost), **confirmed**.
- Accessibility: Dynamic Type, VoiceOver labels and custom actions for every swipe target, minimum hit targets.
- A `DesignGallery` preview view showing everything in all states (used for visual review).

## Acceptance

- No public signature from T00 removed or changed (additions only).
- Gallery renders on iOS and macOS previews; `scripts/check.sh` passes.
- `SwipeCard` logic (threshold → direction) is unit-tested separately from the view.

## Result

_(fill in when done)_
