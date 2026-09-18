# T41 — QA, traceability & hardening

**Wave 3 · after T40**

## Model recommendation

**Difficulty:** Hard (judgment-heavy) · **Recommended model:** Opus

An adversarial audit is only worth as much as the auditor: tracing every requirement to evidence, hunting data-safety violations, designing sync torture tests. A weaker model tends to confirm rather than challenge. The follow-up fixes it spawns can go to Sonnet.

## Goal

Prove the app meets REQUIREMENTS v1 and is safe to point at the real vault.

## Owns

`docs/TRACEABILITY.md`, `docs/MANUAL_TEST.md` (extend), new tests anywhere; bug fixes anywhere
(keep them small and list each in Result; large ones become follow-up task docs `5x-*.md`).

## Deliverables

1. **Traceability matrix:** every requirement ID (N1–N6, C1–C4, I1–I7, A1–A5, P1–P7, W1–W2, D1–D3,
   E1–E4, R1–R6, §10 steps, M1–M6) → implementing module, test(s), status (met / partial / missing) with evidence.
2. **Data-safety review** of everything that writes: confirm ARCHITECTURE §7 rules hold; grep for
   `FileManager` use outside `GTDVault`; confirm no hard deletes; fuzz the codec with the sample
   vault + mutated files; verify unknown frontmatter survives every command (golden-file tests).
3. **Sync torture tests** on a temp vault: external edits during a commit, rename while open in
   detail view, conflict copies, evicted-file placeholders, two simulated devices writing routine logs for the same day.
4. **"No lying defaults" audit:** walk every form; no pre-filled values except the documented
   defaults (follow-up +7 d, last-used knowledge folder shown as *suggestion*).
5. **Performance:** cold launch to usable Next view with 1 000 notes; snapshot rebuild; typing latency in the detail editor.
6. **Accessibility pass** (VoiceOver through inbox card + routine runner, Dynamic Type XXL, keyboard-only on Mac).
7. **First-real-use checklist** for the user: back up vault → run T02 migration dry run → apply →
   pick vault in the app → first weekly review to settle Next vs Backlog.

## Acceptance

- `docs/TRACEABILITY.md` complete; every "partial/missing" has a follow-up task doc.
- All new tests pass in `scripts/check.sh`; no test touches the real vault.

## Result

_(fill in when done)_
