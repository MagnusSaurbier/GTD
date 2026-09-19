# T54 — Make "captured vs processed" a real number

**Follow-up from T41 (traceability gap: §10.3) · after the first two weekly reviews**

## Model recommendation

**Difficulty:** Medium–hard · **Recommended model:** Opus

Not because the code is hard — it is a field and a stat — but because it is a **change to the
vault format**, which means a migration note, a round-trip guarantee and a decision the user has
to agree with. Everything the app writes into a note is something they will read in Obsidian
forever.

## The gap

REQUIREMENTS §10.3 asks the systems check to show "captured vs processed" so the weekly review
can answer "is the inbox trustworthy, did anything slip?". `GTDStats.WeeklyStats.compute`
documents honestly that it can only approximate it: the vault records when a note was **created**
and when it was **completed**, never when it was **filed out of the inbox**. So

- an item captured *and* trashed, or filed into `Knowledge/`, disappears from the count entirely
  (its file no longer carries a `created` the stats can see);
- "captured last week, processed this week" and "captured this week, still queued" are
  indistinguishable, although they mean opposite things about the system.

`FeatureReview` presents the number honestly today, which is the right stopgap. **Do not start
this task until the user has run at least two weekly reviews and can say whether the number is
actually misleading in practice** — a vault-format change to fix a stat nobody mistrusts is a bad
trade.

## Owns

`docs/REQUIREMENTS.md` is read-only (it is a snapshot of a vault note — ask the user to change
the source). Otherwise: `GTDModel` (schema), `GTDMarkdown` (codec + round-trip tests),
`GTDModel/Reducer`, `GTDStats`, `GTDFixtures`, `Tools/migrate/` (a note, not a rewrite),
`docs/ARCHITECTURE.md` §3.

## Deliverables

1. **Pick the cheapest honest mechanism and write the decision into ARCHITECTURE §6 first.**
   Two candidates, and they are not equal:
   - a `filed` timestamp in the action's frontmatter — visible in Obsidian, survives everything,
     but adds a field to every note and says nothing about items that were trashed;
   - a per-device, per-day **filing log** next to the routine log
     (`GTD/FilingLog/<day>--<device>.md`), which is append-only-per-device, already a proven
     shape in this vault (R5, N3 §7.2), and *does* capture trashed and knowledge-filed items.
   The second is the one this brief expects to win; make the case either way.
2. **Write it in exactly one place** — the reducer, on the commands that take an item out of the
   inbox (`fileInbox`, `deferInboxToReview`). Never in a view.
3. **N2 must keep holding.** Unknown frontmatter and body sections still round-trip byte for
   byte; `GTDMarkdownTests/FuzzRoundTripTests` must stay green without being relaxed.
4. `GTDStats.WeeklyStats` reads the new record, keeps the approximation as the fallback for weeks
   that predate it, and says which it used. A stat that silently changes meaning mid-history is
   worse than the approximation.
5. `Tools/migrate/README.md`: one line saying existing notes have no filing record and the first
   weeks will fall back.

## Acceptance

- The systems check shows a number that is true for a week where an item was captured, filed,
  trashed and deferred to review.
- Round-trip tests unchanged and green; the sample vault regenerated.
- `docs/TRACEABILITY.md`'s §10.3 row updated.

## Result

_(fill in when done)_
