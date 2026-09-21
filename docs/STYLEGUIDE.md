# GTD App — UI Style Guide (v1)

Status: decisions agreed 2026-09-18; inbox card, tiers and lists revised 2026-09-21 (two-step card, Someday, Lists — see requirements §4, §5, §5a). Companion to [[GTD App Requirements]] (IDs like I2, E3 refer to it).
Audience: every agent implementing UI for the SwiftUI macOS and iOS apps. **This document is binding.** If something is not covered, choose the most stock SwiftUI/HIG solution and the quietest visual option — do not invent.

## 0. Decision record

| # | Decision | Choice |
| --- | --- | --- |
| 1 | Design stance | **Native-first.** Stock SwiftUI + system materials/Liquid Glass. Custom only: chips, inbox card, routine card, badges, heatmap, calendar strip. |
| 2 | Personality | **Calm & quiet.** Monochrome base; color only when it carries information. |
| 3 | Typography | **SF Pro only**, system text styles, Dynamic Type. Monospaced digits for numbers. |
| 4 | OS target | **iOS 26 / macOS 26+.** No availability checks, no fallbacks. |
| 5 | Field states | **Outline = undecided, dashed + sparkle = suggested, ink fill = confirmed.** Shape carries state, not hue. |
| 6 | Accent | **Single fixed accent: slate blue.** Rare: primary button, selection, links. |
| 7 | Urgency semantics | **3-step warm scale** yellow → orange → red. Green only for completion moments. |
| 8 | Staleness | **Age badge appears past a threshold**; rows are clean before. |
| 9 | Chip fill | **Ink** (label color), never accent. |
| 10 | Mac list density | **Two-line comfortable rows**, no density toggle. |
| 11 | Cards | **Solid elevated card**; glass only for floating controls. |
| 12 | Card map | **Two-step card.** Step 1 is **buttons only**: Action / Knowledge or List / Trash, plus a quiet `Defer to review` link. The opened action card keeps the **commitment axis**: → Next, ← Someday; ↓ collapses back to step 1; buttons for Waiting / Done; ⋯ (`File to`) repeats Next / Someday for one-handed and AX use. No swipe ever trashes. |
| 13 | Motion | **Functional + two reward moments** (inbox zero, routine/review complete). |
| 14 | Copy | **English, terse GTD terms**, String Catalog for later localisation. |
| 15 | Icons | **SF Symbols only, fixed map** (§7). No ad-hoc symbol choices. |

## 1. Principles (how to decide when the guide is silent)

1. **Nothing shouts unless it matters.** Default state of every screen is black/white/gray + one accent touch. If a screen at rest shows yellow/orange/red, something really needs attention.
2. **No lying UI.** An undecided field looks empty. A suggestion never looks like a decision. A count is always live. Never pre-select, never pre-fill with a fake value (timeEstimate is empty, never 0).
3. **Staleness is visible.** Age is a first-class visual property (§5.3).
4. **One component per concept.** One chip, one badge, one row, one card. Variation comes from state, not from new components.
5. **Stock first.** `List`, `NavigationSplitView`, `NavigationStack`, `Form`, `.toolbar`, `.sheet`, `.confirmationDialog`, `.searchable`, `.swipeActions`, `.contextMenu`, `.inspector`. Custom drawing needs a reason listed in decision #1.
6. **Color is never the only carrier.** Every semantic color is paired with a symbol or text.
7. **Keyboard-complete on Mac, thumb-complete on iPhone.** Every Mac action has a shortcut; every iPhone primary action is reachable in the lower half of the screen.

## 2. Design tokens

All tokens live in one Swift package target `DesignSystem` (shared by both apps). Views must reference tokens — **no literal colors, font sizes, paddings, radii or durations in feature code.** Colors are asset-catalog color sets with Any/Dark variants (plus High Contrast where given).

### 2.1 Color

Base surfaces and text are **system semantic colors** — do not redefine them.

| Token | Value | Use |
| --- | --- | --- |
| `Color.ink` | `Color.primary` (label) | Text, confirmed chip fill, checkmarks |
| `Color.inkInverse` | systemBackground | Text on ink fill |
| `Color.textSecondary` | `.secondary` | Metadata line, labels |
| `Color.textTertiary` | `.tertiary` | Placeholders, disabled, counters at rest |
| `Color.surface` | systemBackground / windowBackground | Page |
| `Color.surfaceGrouped` | systemGroupedBackground | Behind cards (iOS), review wizard |
| `Color.surfaceCard` | secondarySystemGroupedBackground | Inbox/routine card, stat tiles |
| `Color.hairline` | `.separator` | Chip outline, dividers |
| `Color.fillQuiet` | `.quaternary` / quaternarySystemFill | Neutral badge bg, heatmap empty cell |

Brand + semantic (asset catalog, names exactly as below):

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `accent` | `#3F6E9E` | `#7FB0DE` | App `AccentColor`. Primary button, selection, links, focus ring, progress |
| `accentWash` | accent @ 12 % | accent @ 24 % | Selected row bg where system selection isn't used, drag-target tint for Next |
| `signalAging` | systemYellow | systemYellow | Step 1: aging / approaching |
| `signalAttention` | systemOrange | systemOrange | Step 2: needs attention |
| `signalOverdue` | systemRed | systemRed | Step 3: overdue / broken |
| `signalDone` | systemGreen | systemGreen | Completion moments only (check-draw, inbox zero, heatmap done cells) |

Signal badge rendering (one formula for all three): background = signal color @ 18 % (light) / 28 % (dark); foreground = `.primary` text + symbol tinted with the signal color. This keeps text contrast ≥ 4.5:1 in both modes (never yellow text on white).

**Rules**
- Accent may appear **at most once as a filled element per screen** (the primary button). Links/selection don't count.
- Green is never a resting state: no green "on track" labels, no green counts.
- No per-status or per-context hues. No gradients. No custom shadows except `Elevation.card`.
- Never apply `.opacity()` to text to make it quieter — use `textSecondary`/`textTertiary`.

### 2.2 Signal semantics (what gets which step)

| Condition | Step | Badge text | Symbol |
| --- | --- | --- | --- |
| Action untouched > 14 days | aging | `16d` | `clock` |
| Action untouched > 30 days | attention | `34d` | `clock.badge.exclamationmark` |
| Waiting, follow-up within 2 days | aging | `follow up Fri` | `hourglass` |
| Waiting, follow-up date passed → **chase** item in Next | attention | `chase · 9d` | `bell.badge` |
| `due` within 3 days | aging | `due Thu` | `calendar` |
| `due` today | attention | `due today` | `calendar.badge.exclamationmark` |
| `due` passed | overdue | `2d overdue` | `exclamationmark.circle` |
| Defer date reached, item resurfaced (first 24 h) | neutral badge | `back` | `arrow.uturn.up` |
| Active project with zero open actions (**stalled**) | attention | `stalled` | `pause.circle` |
| Next at cap (15/15) | attention | sidebar count turns into badge `15/15` | — |
| Next over cap (only possible via file edits) | overdue | `17/15` | — |
| Inbox item older than 7 days | aging | `8d` | `clock` |

"Untouched" = file modification date or last status change, whichever is later. Thresholds live in one `StalenessPolicy` struct, not in views.

### 2.3 Typography

System text styles only, via `Font.TextStyle`. Never `.system(size:)`.

| Token | Style | Use |
| --- | --- | --- |
| `Typo.screenTitle` | `.largeTitle` (iOS nav large title) / `.title2.weight(.semibold)` (Mac) | Screen titles |
| `Typo.cardText` | `.title3` | Raw captured text on inbox card, routine step title |
| `Typo.sectionHeader` | `.headline` | `Why?`, `What?`, list section headers, wizard step titles |
| `Typo.body` | `.body` | Row titles, editor text, field content |
| `Typo.meta` | `.subheadline` + `textSecondary` | Row second line, helper text |
| `Typo.chip` | `.subheadline.weight(.medium)` (iOS) / `.callout` (Mac) | Chips |
| `Typo.badge` | `.caption.weight(.medium).monospacedDigit()` | Badges |
| `Typo.counter` | `.footnote.monospacedDigit()` + `textSecondary` | "3 of 14 left", sidebar counts, stats |
| `Typo.stat` | `.title.weight(.semibold).monospacedDigit()` | Review stat tiles |

- All numbers that can change (counts, ages, dates, percentages) use `.monospacedDigit()`.
- Weights: regular, medium, semibold only. No bold/heavy, no italics, no ALL CAPS, no custom tracking.
- Dynamic Type must work to AX3 on iPhone: rows wrap (title up to 2 lines → unlimited at AX sizes), chips wrap via flow layout, nothing truncates critical info. Use `@ScaledMetric` for any custom dimension tied to text.
- User-written text (captured text, Why?, What?, outcome) is never truncated in detail/card views; in rows, title truncates at 2 lines.

### 2.4 Spacing, radius, elevation

4-pt grid. `Spacing.xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32`.

| Token | Value | Use |
| --- | --- | --- |
| `Spacing.screenMargin` | 16 (iPhone) / 20 (Mac content) | Horizontal page inset |
| `Spacing.cardPadding` | 20 | Inside inbox/routine cards |
| `Spacing.chipGap` | 8 | Between chips (both axes) |
| `Spacing.rowVertical` | 10 | Row top/bottom padding (yields ~44 pt two-line rows on Mac, ≥ 56 pt on iOS) |
| `Radius.card` | 24, `.continuous` | Inbox/routine card |
| `Radius.tile` | 12, `.continuous` | Stat tiles, heatmap container, calendar strip |
| `Radius.chip` | `Capsule()` | Chips, badges |
| `Radius.cell` | 4 | Heatmap cells |
| `Elevation.card` | shadow `black 10 %`, radius 16, y 6 (light); none in dark — use `surfaceCard` contrast + 0.5 pt `hairline` stroke | The only shadow in the app |

Minimum hit target: 44×44 pt on iOS, 24×24 pt on Mac (chips on Mac are 24 pt tall, iOS 34 pt).

### 2.5 Materials / Liquid Glass

- Glass belongs to the **control layer only**: toolbars, tab bar, sidebar (all automatic from stock components), plus two custom floating elements: the **inbox action bar** and the **routine done/skip bar** (`.glassEffect()` inside one `GlassEffectContainer`).
- Never put glass behind editable or long-form text. Never stack glass on glass. Never tint glass except the single primary action (`.buttonStyle(.glassProminent)` with accent).
- Don't set custom toolbar/nav backgrounds; let the system scroll-edge effect work.

## 3. Core components

Each is one SwiftUI view in `DesignSystem`, with previews for every state in light/dark and at AX1.

### 3.1 `Chip`

The main input control (I3, A4, E1). Capsule, `Typo.chip`, horizontal padding 12 (iOS) / 10 (Mac).

| State | Look | Meaning |
| --- | --- | --- |
| `.unset` | 1 pt `hairline` outline, `textSecondary` label, no fill | Available, not chosen |
| `.suggested` | 1 pt **dashed** outline (dash 4/3) in `textSecondary`, leading `sparkles` symbol, `textSecondary` label | App proposes this (last-used folder, +7 d follow-up, later LLM). **Not saved to the file until confirmed.** |
| `.confirmed` | `ink` fill, `inkInverse` label, no icon | User decided. Written to frontmatter |
| `.disabled` | as unset with `textTertiary` | Not applicable (rare; prefer hiding) |

- Tap: unset → confirmed; suggested → confirmed; confirmed → unset. No long-press menus.
- Single-select groups (time bucket) behave like radio chips; multi-select (contexts) toggle independently. No group ever has a default selection.
- **Filter chips** in the Next view (E1) are the same component: active filter = confirmed look. A trailing `xmark` "Clear" text button appears when any filter is active.
- Value chips for dates (`defer`, `due`, follow-up): unset shows `+ defer` / `+ due` with `plus` symbol; confirmed shows the formatted date (`Fri 25 Sep`) in ink fill; tapping opens a stock graphical `DatePicker` in a popover (Mac) / sheet with `.presentationDetents([.medium])` (iOS). The +7 d follow-up default renders as **suggested** (dashed) until tapped — W1's "default" must not silently write a date.
- Layout: custom `FlowLayout` (wraps lines, `chipGap` both ways). Never a horizontal scroller for the pickers on the card; the Next-view filter bar may scroll horizontally on iPhone.
- Accessibility: `accessibilityAddTraits(.isSelected)` for confirmed; suggested announces "suggested, <label>"; VoiceOver value states unset/suggested/confirmed.
- Haptic (iOS): `.selection` on toggle.

### 3.2 `Badge`

Small capsule, `Typo.badge`, optional leading symbol, height 20. Variants: `.neutral` (`fillQuiet` bg, `textSecondary`), `.aging`, `.attention`, `.overdue` (formula in §2.1). Text comes from §2.2 — agents do not invent badge wording. Max **two** badges per row; priority: overdue > attention > aging > neutral.

### 3.3 `ActionRow`

Used in every action list on both platforms (E1–E3).

```
(○)  Title of the action, up to two lines                 [16d] [due Thu]
     Project name · mac · phone · ≤30 min
```

- Leading: completion control — 22 pt circle, 1.5 pt `textTertiary` stroke. Tap → check-draw in `signalDone` (0.25 s) + `.success` haptic → row collapses after 0.4 s (A5). Undo via toast (§3.8). In-progress status: circle shows a half-fill in `ink`.
- Title: `Typo.body`, `ink`. Second line: `Typo.meta`, items joined by ` · ` — project (if any) first, then contexts as plain lowercase text (not chips), then time bucket. Missing values are simply omitted — never "No project", never "0 min".
- Trailing: badges (§3.2). No chevrons on Mac; stock disclosure chevron on iOS only where a push follows.
- Chase items (W2) use the same row with title `Chase: <who> — <what>` and the `chase` badge; they sort above regular Next items, separated by a section header `Chase`.
- iOS swipe actions: trailing = `Done` (full swipe), leading = `Someday` (demote). Mac: context menu + shortcuts (§4.5).
- **List items** (L1) use the same row: completion circle + title only — no second line, no badges, no age (a list item is not a commitment and cannot go stale). Trailing swipe = `Done` (moves it to the list's `Done/`, L3); context menu: `Make action`, `Trash`.
- Stock `List` row; selection uses system selection color (accent). No custom row backgrounds, no card-per-row.

### 3.4 `ProjectRow` (E4)

Line 1: project name + `stalled` badge if applicable. Line 2 (`Typo.meta`): `<n> active · <m> steps left`. Below, indented, up to 3 active actions as compact one-line `ActionRow`s. Area names are `List` section headers (`Typo.sectionHeader`).

### 3.5 `ItemCard` (inbox processing I2 / routines R2)

Solid card: `surfaceCard`, `Radius.card`, `Elevation.card`, `cardPadding`, on `surfaceGrouped`. Max width 560 pt (Mac / iPad-like widths), centered.

The inbox card has **two steps** (I2). It is the same card view in both; step 2 **expands in place** (`Motion.standard`), it is never a new screen or a sheet.

**Step 1 — small card** (content order fixed):
1. Meta line: capture timestamp, relative (`Typo.counter`) + inbox age badge if any.
2. The **full capture text** — `Typo.cardText`, no truncation, no `Show all`. It is the item's **title**: tapping it makes it editable in place (`TextField(axis: .vertical)`, no visible field border until focused).

Nothing else is on the step-1 card: no fields, no chips. The card grows with its text up to the available height; beyond that **the text scrolls inside the card** (the only place a card scrolls internally).

**Step 2a — opened action card** (after `Action`):
1. Meta line and title as in step 1 (title still editable on tap).
2. `Why?` — `Typo.sectionHeader` label + borderless multi-line field, placeholder `What do I gain?`
3. `What?` — same, placeholder `The next physical action`. Typing `- ` or pressing the checklist button turns lines into checkboxes. When a **second checkbox** exists, show inline text button `Turn into project` (accent, `square.stack` symbol) under the field (A2).
4. Chips: `Context` group, `Time` group (`≤10` `≤30` `≤60` `60+`), then value chips `+ defer` `+ due` `+ project`. Group labels in `Typo.meta`.

**Step 2b — opened Knowledge / List card** (after `Knowledge / List`):
1. Meta line and title as in step 1.
2. `Notes` — one borderless multi-line field, placeholder `Notes (optional)`. No chips, nothing required.

On iPhone an opened card taller than the screen scrolls with the page (not internally); see §3.6 for how it is then filed.

Stack look: the next card peeks 8 pt below, scaled 0.96, no content visible (forced order — the peek only signals "more").

### 3.6 Inbox action bar + gestures (I2–I4, decision #12)

**Step 1 — buttons only, no gestures.** No drag is recognised on the small card.

| Target | iPhone | Mac key (default) | Symbol |
| --- | --- | --- | --- |
| Action | bar button | `A` | `bolt` |
| Knowledge / List | bar button | `K` | `archivebox` |
| Trash | bar button | `X` | `trash` |
| Defer to review | quiet text button under the card | `D` | `arrow.uturn.right.circle` |

**Step 2a — opened action card.**

| Target | iPhone | Mac key (default) | Drag/confirm tint | Symbol |
| --- | --- | --- | --- | --- |
| Next | swipe → | `→` | `accentWash` | `arrow.right.circle` |
| Someday | swipe ← | `←` | `fillQuiet` | `moon.zzz` |
| Collapse to step 1 | swipe ↓ | `Esc` | none | `chevron.down` |
| Waiting | bar button | `W` | — | `hourglass` |
| Done (2-minute rule) | bar button | `⌘↩` | — | `checkmark.circle` |
| Project | `+ project` chip | `P` | — | `square.stack` |

**Step 2b — opened Knowledge / List card.**

| Target | iPhone | Mac key (default) | Symbol |
| --- | --- | --- | --- |
| Knowledge | navbar slot 1 → folder picker | `1` | `books.vertical` |
| Favourite lists | navbar slots, fixed order → files instantly | `2`…`9` | the list's symbol (§7) |
| More… | last navbar slot → sheet with all lists | `0` | `ellipsis` |
| Collapse to step 1 | swipe ↓ | `Esc` | `chevron.down` |

**Always:** Undo last card — toolbar button / `⌘Z` (`arrow.uturn.backward`). Quit session — toolbar `Close` / `Esc` on step 1 with no field focused (it is `Close`, not `Done`, because `Done` on this screen files the card as done). `Esc` is a ladder: focused field → blur; opened card → collapse; step 1 → quit.

- **Step-1 bar (iPhone):** floating glass capsule pinned above the home indicator with three **equal, neutral** labelled buttons (symbol over text): `Action` · `Knowledge / List` · `Trash`. **None of them is accent-filled** — the app does not know the right answer, so it must not look like it suggests one (§1.2). `Defer to review` is a quiet text button (`Typo.meta`, `textSecondary`) centred between card and bar. **Mac:** the same three as a row of stock bordered buttons under the card, `Defer to review` as a text button beside them, and the key legend below.
- **Opening and collapsing:** choosing `Action` or `Knowledge / List` expands the card in place and swaps the bar with a cross-fade; focus goes to `Why?` (2a) or stays unfocused (2b). Collapsing keeps everything already typed — the draft survives until the card is filed or the session ends. Trash and Defer are reachable **only from step 1**.
- **Drag behaviour (opened action card, iPhone):** card follows the finger on the dominant axis only (axis locks after 12 pt), max rotation 4°. Horizontal: past 35 % of card width a destination label (symbol + name, `Typo.sectionHeader`) fades in on the leading/trailing edge, the card gets the tint overlay, and one `.impact(.medium)` haptic fires. Release past threshold → card flies out (0.25 s) and the next card springs up. Release before → springs back. Downward: past 25 % of card height the label `Back` (`chevron.down`) appears, no tint; release → the card collapses to step 1. **Upward drags do nothing.** The Knowledge / List card recognises only the downward drag.
- **Swipes are disabled while any text field is focused** (keyboard up). A `Done` keyboard-toolbar button dismisses the keyboard.
- **Action bar (opened action card, iPhone):** glass capsule with `Waiting` and `Done` as labelled buttons and `⋯` at the end. The `⋯` menu (`File to`) repeats the two swipe targets (Next / Someday) so a card can be filed without a swipe, and is how a card taller than the screen is filed. While a field has the keyboard, the bar is replaced by a `Done` bar that blurs the field.
- **Navbar (Knowledge / List card):** glass capsule, a **fixed row with stable positions**: `Knowledge` first, then the favourite lists in the order set in Settings (at most **four** on iPhone, eight on Mac), then `More…`. Positions never reorder by use. A list button files the card at once (undoable); `Knowledge` and `More…` open a sheet.
- **Validation before leaving (D12):** Next requires `Why?`, `What?`, at least one context and a time bucket; Someday requires `What?`; Waiting requires `What?` plus the sheet's follow-up date; Done, lists, Knowledge and Trash require nothing. If something is missing the card shakes once (6 pt, 0.3 s), `.error` haptic, the first missing text field gets focus, and **every missing field or chip group shows a leading `asterisk` symbol in `signalAttention` on its label** until it is filled. No alert, no red borders. Undecided remains a legal state for every other exit.
- **Next at cap:** filing to Next at 15/15 springs the card back and presents a sheet `Next is full` listing the Next items with `Demote` buttons (demotes to Someday, then files the card) and `Cancel`. There is no automatic choice and no "send to Someday instead" shortcut — after `Cancel` the user swipes ← themselves.
- **Sheets** (iOS `.medium`/`.large` detents; Mac popover-sized sheet):
  - **Project picker** (from the `+ project` chip, I4a): stock search field on top; below it a stock `OutlineGroup` — projects without an area first, **without a header** (never a "No area" label), then areas with their projects. Typing filters the tree. When the text matches no project exactly, the last row is `Create project "<text>"` (`plus` symbol); it creates the project with that name only and confirms the chip.
  - **Knowledge folder tree:** stock `OutlineGroup`, last-used folder shown as a **suggested** dashed row at top; below the tree a section `Projects` lists the active projects' folders as filing targets (reference material, I4b).
  - **Waiting:** follow-up date chip (**required**; +7 d shown as a *suggested* chip the user must confirm) and a `Who or what (optional)` field. `Set waiting` stays disabled until a date is confirmed.
  - **Defer to review:** the reason in a single text field; `Defer` stays disabled until non-empty.
  - **More…:** plain list of all lists; tapping one files the card.
- **Hints and VoiceOver:** a one-time hint overlay shows `← Someday` / `→ Next` / `↓ Back` the first time an action card is opened. VoiceOver exposes **every exit of the current step** as a custom action.
- **Mac:** same card centered in the window; below it a quiet key legend row in `Typo.counter`, per step — step 1: `A Action · K Knowledge / List · X Trash · D Defer to review`; action card: `← Someday  → Next    W Waiting · ⌘↩ Done · P Project · Esc Back`; Knowledge / List card: `1 Knowledge · 2 Read · 3 Watch · 4 Wish · 0 More… · Esc Back`. **The legend always renders the current bindings** (they are rebindable, §4.5). `Tab` moves title → Why? → What? → chips; `Esc` blurs a focused field so the keys act on the card; on the action card contexts toggle with `1…8` and time buckets with `⇧1…⇧4` when no field is focused. Filing animates the card out in the key's direction.
- **Counter:** `3 of 14 left` in `Typo.counter`, top center (iOS nav bar principal / Mac toolbar). No progress bar.

### 3.7 Routine card (R2)

Same `ItemCard` shell. Content: routine name + step index (`Typo.counter`, `Morning · 4 of 11`), step title (`Typo.cardText`), sub-steps as checkboxes (`Typo.body`). Journaling steps (R4) show the title plus meta text `On the reMarkable` with `pencil.and.scribble` — no input.
Bottom glass bar with two large buttons, each ≥ 56 pt tall, equal width: `Skip` (plain glass) and `Done` (`.glassProminent`, accent). No swipe filing on routine cards (avoid accidental skips); horizontal swipe back = previous step. Completion screen: see §5.

### 3.8 Undo toast (N6)

After any filing/status change: bottom-anchored glass capsule, `Moved to Someday` + `Undo` button, auto-dismiss 5 s, one at a time (new replaces old). Mac additionally supports `⌘Z`. Same component for completion of actions.

### 3.9 Empty states

Stock `ContentUnavailableView` with the concept's symbol (§7), a title naming the state, one line of body, optional action. Exact copy in §6.3. Inbox zero is the only one with a reward treatment (§5).

### 3.10 Review-only components (Mac)

- **Wizard frame:** stock window; left rail lists the 4 stages with sub-steps (checkmark when done, accent dot for current), content centered max 720 pt, bottom bar with `Back` / `Continue` (primary). Resumable: rail shows progress on reopen.
- **Deck cards** (Next ↔ Someday): reuse `ItemCard`, read-only content, default keys `K` keep · `D` demote · `P` promote · `T` trash (rebindable, §4.5), legend row as in §3.6. The Someday part of the deck is ordered stalest first, project-linked before unlinked, and its header shows the `untouched > 30 days` count (`Typo.counter`). List items never appear in the deck.
- **Stat tile:** `surfaceCard`, `Radius.tile`, `Typo.meta` label on top, `Typo.stat` number, optional trend line `▲ 3 vs last week` in `Typo.counter` (`textSecondary` — trends are **not** colored).
- **Routine heatmap:** rows = steps, 7 columns = days; cells 18×18, `Radius.cell`, gap 3. Done = `signalDone` @ 85 %, skipped = `fillQuiet` with a centered 4 pt `textTertiary` dot, no data = `fillQuiet` empty. Row trailing: completion % (`Typo.counter`). Legend below. Weekday initials as column headers.
- **Calendar strip (D3):** horizontal 14-day strip, `Radius.tile`; each day column shows up to 3 markers, distinguished by **symbol** not hue: `defer` = `arrow.uturn.up`, `due` = `calendar`, follow-up = `hourglass`; markers take a signal color only when §2.2 says so. Today column has an accent 2 pt underline.

## 4. Platform patterns

### 4.1 macOS window (E3)
`NavigationSplitView` three columns: **sidebar** (stock `List(.sidebar)`: Inbox · Next · Someday · Waiting · Lists · Projects · Deferred, then `Review`, `Routines`; live counts as trailing `Typo.counter` text, turning into a signal badge per §2.2) · **content list** (grouped by area/project with section headers; filter chips in a bar under the toolbar) · **detail** (note editor: title, Why?/What? fields, chips — same building blocks as the card, without card chrome). **Lists** is a single sidebar row (count = open items across all lists); its content column shows every list as a section (header = list name + count, items as list-item rows §3.3, a quiet `Show done` text button at the end of a section that has finished items); the detail column is the note editor (title + notes) with a `Make action` toolbar button. Minimum window 900×560. Inbox row shows a primary toolbar button `Process inbox` when count > 0.

### 4.2 iPhone
`TabView` with four tabs, in this order: **Inbox** (count badge; big `Process inbox` primary button + read-only list of raw captures) · **Next** (selected on launch, E2) · **Lists** (stock `List` of the lists with counts → push to the list's items; rows per §3.3; tapping an item pushes the note editor with `Make action` in the toolbar; L5) · **Routines**. `Make action` opens the opened action card (§3.5 step 2a) as a sheet. Inbox processing and routines run as `fullScreenCover`. No settings tab — settings via toolbar gear on Next.

### 4.3 Sheets, dialogs, alerts
Sheets for pickers and sub-flows. `confirmationDialog` only for destructive actions that are **not** undoable (there should be almost none). Never use `alert` for validation — use inline shake/focus (§3.6).

### 4.4 Forms & text
Borderless text fields inside cards/detail; stock `Form` (grouped) in settings. Placeholders are real prompts (§6.3). Editing autosaves; there are no Save buttons anywhere.

### 4.5 Mac keyboard map (global within the main window)
`⌘N` new capture · `⌘1…7` sidebar sections · `⌘⏎` mark done · `⌘⇧N/S` move to Next/Someday · `⌘⇧W` set waiting · `⌘F` search · `⌘Z` undo · `⌘I` process inbox · `Space` toggles focused chip/checkbox. All shortcuts also appear in the menu bar (stock `Commands`). These `⌘` shortcuts are **fixed**.

**Rebindable keys (N7).** The single-key commands of inbox processing (§3.6: `A K X D`, `← →`, `W P`, `1…9 0`) and of the review deck (§3.10: `K D P T`) are rebindable in **Settings › Keyboard** (Mac only, stored per device): a stock `Form` with one row per command, grouped by screen, each with a key-recorder field, and `Reset to defaults` at the end. A key already used on the same screen is refused inline (`Already used by <command>`) — never an alert. `Esc`, `Tab`, `⌘Z` and `⌘↩` are not rebindable. Every legend row renders the current binding.

## 5. Motion, haptics, sound

- Default animation: `.snappy(duration: 0.3)`; card fly-out `.easeIn(0.25)`; spring-back `.spring(response: 0.35, dampingFraction: 0.8)`. Tokens: `Motion.standard`, `Motion.cardExit`, `Motion.cardReturn`. No other curves.
- `accessibilityReduceMotion`: replace movement with 0.2 s cross-fades; no rotation, no shake (use focus + haptic only).
- Haptics (iOS only): chip `.selection`; swipe threshold `.impact(.medium)`; complete action `.success`; validation `.error`; routine Done `.impact(.light)`.
- **No sounds.**
- **Reward moments — exactly two:**
  1. **Inbox zero:** last card leaves → `tray` symbol draws on with `.symbolEffect(.bounce)` once, `signalDone` checkmark badge, title `Inbox zero`, body with session stats (`14 processed · 6 min`). One `.success` haptic.
  2. **Routine / weekly review complete:** same pattern with `checkmark.circle`, title `Morning done` / `Review complete`, body `9 of 11 steps`.
  No confetti, particles, streak counters or praise copy.

## 6. Voice & copy

### 6.1 Rules
English. Sentence case everywhere. Verb-first buttons, 1–3 words. No exclamation marks, no "please", no "successfully", no emoji, no praise ("Great job"). GTD terms are fixed vocabulary — never synonyms.

### 6.2 Fixed vocabulary
Inbox · Next · Someday · Waiting · List · Project · Area · Knowledge · Trash · Action · Notes · Defer · Due · Follow-up · Chase · Stalled · Routine · Weekly review · `Why?` · `What?` · Process inbox · Turn into project · Make action · Defer to review · Promote · Demote · Done · Skip · Back · Close · More….
Never: "Task", "To-do", "Backlog", "Maybe", "Later", "Priority", "Tag", "Snooze", "Archive" (user-facing). List names (`Read`, `Watch`, `Wish`, …) are the user's folder names, shown as they are.

### 6.3 Canonical strings
| Place | Copy |
| --- | --- |
| Why? placeholder | `What do I gain?` |
| What? placeholder | `The next physical action` |
| Counter | `3 of 14 left` |
| Undo toast | `Moved to Someday` · `Undo` — lists: `Added to Read`; list item finished: `Done` |
| Cap sheet | `Next is full` / `Demote one to make room.` |
| Notes placeholder (Knowledge / List card) | `Notes (optional)` |
| Waiting sheet, who field | `Who or what (optional)` |
| Project picker, create row | `Create project "<text>"` |
| Rebinding a taken key | `Already used by <command>` |
| Defer-to-review prompt | `Why doesn't this fit?` |
| After completing a project action (P5) | `What's next for <project>?` |
| Empty Next | `Nothing in Next` / `Promote from Someday, or process your inbox.` |
| Empty Someday | `Nothing in Someday` |
| Empty list | `Nothing in <list>` |
| Empty Next (filtered) | `No match` / `Nothing in Next fits these filters.` + `Clear filters` |
| Empty Waiting | `Not waiting on anyone` |
| Empty Inbox | `Inbox zero` |
| Stalled project | `No open action. Add one or put the project on hold.` |
| Dates | Relative within 7 days (`today`, `tomorrow`, `Thu`), else `25 Sep`; ages as `16d`; never times of day except capture timestamp |

All strings go through a String Catalog (`Localizable.xcstrings`); no string literals in views beyond keys.

## 7. Icon map (SF Symbols — canonical, exhaustive)

Rendering: `.symbolRenderingMode(.hierarchical)`, monochrome `ink`/`textSecondary`; signal tint only inside badges. Use outline variants; filled variants only for the selected tab (system does this).

| Concept | Symbol | | Concept | Symbol |
| --- | --- | --- | --- | --- |
| Inbox | `tray` | | Done / complete | `checkmark.circle` |
| Next | `arrow.right.circle` | | Undo | `arrow.uturn.backward` |
| Someday | `moon.zzz` | | Suggestion | `sparkles` |
| Lists (and any custom list) | `list.bullet` | | Stale (attention) | `clock.badge.exclamationmark` |
| Waiting | `hourglass` | | Aging | `clock` |
| Chase | `bell.badge` | | Due | `calendar` |
| Projects | `square.stack` | | Overdue | `exclamationmark.circle` |
| Area | `folder` | | Defer / resurfaced | `arrow.uturn.up` |
| Knowledge | `books.vertical` | | Defer to review | `arrow.uturn.right.circle` |
| Trash | `trash` | | Stalled | `pause.circle` |
| Routines | `sunrise` (Morning), `moon.stars` (Bedtime), `repeat` (generic) | | Weekly review | `checklist` |
| Capture | `plus.circle` | | reMarkable journaling | `pencil.and.scribble` |
| Settings | `gearshape` | | Promote step / Make action | `arrow.up.right.circle` |
| Action (step-1 kind) | `bolt` | | Knowledge / List (step-1 kind) | `archivebox` |
| List: Read | `book` | | List: Watch | `play.rectangle` |
| List: Wish | `gift` | | More… | `ellipsis` |
| Collapse / Back | `chevron.down` | | Required field missing | `asterisk` |

Contexts have **no icons** — they are lowercase text chips (`mac`, `phone`, `home`, `campus`, `errands`, `calls`, `deep-work`). A concept missing from this table → add it here first, then use it.

## 8. Accessibility (non-negotiable)

- Dynamic Type to AX3 (iOS) without loss of function; Mac respects system text size.
- VoiceOver: every custom component has label, value, traits; the inbox card exposes every exit of its current step as `accessibilityAction(named:)`; badges read in full words (`16 days old`, `due Thursday`).
- Contrast ≥ 4.5:1 for text, ≥ 3:1 for chip outlines/controls; provide High Contrast variants for `accent` (`#2F5A87` / `#9CC6EE`) and thicken chip outline to 1.5 pt under `accessibilityContrast == .increased`.
- Differentiate Without Color: satisfied by design (symbols + text everywhere) — keep it that way.
- Reduce Motion / Reduce Transparency honoured (glass bars fall back to `surfaceCard` + hairline).
- Full Keyboard Access on Mac and iPad-style hardware keyboards: chips and card targets are focusable.

## 9. Agent checklist (run before opening a PR)

- [ ] No literal colors, fonts sizes, paddings, radii, durations, symbols names or user-facing strings in feature code — tokens, icon map and String Catalog only.
- [ ] No pre-selected chips, no pre-filled dates, no `0`/"None" placeholders for undecided values; suggestions render dashed + sparkles and are not persisted until confirmed.
- [ ] Screen at rest (no stale/due data) is monochrome + at most one accent-filled element.
- [ ] Every signal color is accompanied by a symbol or text from §2.2.
- [ ] New UI uses stock SwiftUI containers; any custom-drawn view is one listed in decision #1 or is added to this guide first.
- [ ] Previews exist for light, dark, AX1, and every component state; Mac and iOS both build.
- [ ] Keyboard path (Mac) and VoiceOver actions exist for every interaction added.
- [ ] Reduce Motion path verified.
- [ ] Wording matches §6.2/§6.3; badge texts match §2.2.

## 10. Open items (UI-relevant, not yet decided)

- Exact staleness thresholds (14 d / 30 d / inbox 7 d) are first guesses — tune after two weekly reviews; they live in `StalenessPolicy`.
- App icon and launch appearance.
- iPad / Apple Watch: out of scope.
