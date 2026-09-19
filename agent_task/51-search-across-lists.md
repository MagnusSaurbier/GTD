# T51 — `⌘F` reaches every list, not just `FeatureOverview`'s

**Follow-up from T41 (traceability gap: E1/E3) · after Gate 2**

## Model recommendation

**Difficulty:** Easy–medium · **Recommended model:** Sonnet

One environment key and four call sites. It is small; it was left undone only because it changes
a shared file across four targets that had never been compiled (T41's note in
`agent_task/ORCHESTRATOR-NOTES.md`). Once the app builds, this is mechanical.

## The gap

`⌘F` is in the menu bar and filters `FeatureOverview`'s own lists. It travels through
`\.overviewQuery`, which is **internal** to `FeatureOverview`, so `FeatureNext.NextView`,
`FeatureWaiting.WaitingView` and `FeatureProjects.ProjectsListView` — the three views the Mac
shell embeds for the Next, Waiting and Projects sections — cannot read it. Searching in those
sections does nothing, with no sign that it did nothing, which is exactly the lying UI
STYLEGUIDE §1.2 forbids.

## Owns

`DesignSystem` (the environment key), `FeatureOverview/`, `FeatureNext/`, `FeatureWaiting/`,
`FeatureProjects/`.

## Deliverables

1. Move the environment key into `DesignSystem` (every feature already depends on it) as a
   public `\.searchQuery`, with the empty string meaning "no filter". Keep
   `FeatureOverview`'s behaviour identical.
2. Each of the three views filters its own rows on the query: title first, then the project
   title and the contexts. Matching stays **case- and diacritic-insensitive**, and the filter is
   applied after the list's own rules, never instead of them (a search must not resurrect a
   deferred or done action).
3. The filtered-empty state uses the canonical copy that already exists — `No match` /
   `Nothing in Next fits these filters.` + `Clear filters` (STYLEGUIDE §6.3) — rather than a new
   string per view.
4. Unit tests on the list models (they are Linux-compilable: `NextListModel`,
   `WaitingListModel`, `ProjectsListModel`), not on the views.

## Acceptance

- `⌘F` narrows the list in all four sections; clearing it restores the list exactly.
- No new user-facing string literal in feature code (STYLEGUIDE §9).
- `scripts/check.sh` green; `docs/TRACEABILITY.md`'s E1/E3 rows updated.

## Result

_(fill in when done)_
