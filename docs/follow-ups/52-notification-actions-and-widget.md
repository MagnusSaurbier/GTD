# T52 — Notification actions and the routine Control Widget

**Follow-up from T41 (traceability gaps: D2, R3) · after Gate 2**

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet at high effort, Opus if the widget target
turns into a project-structure question

`UNNotificationAction` is well-trodden. The widget is not: it needs a **new build target** that
`project.yml` does not declare, which is a repo-structure change — if that part starts touching
the composition root or the security-scoped bookmark, escalate rather than improvise. A widget
that reads the vault is a second reader of the user's files.

## The gap

- **D2 is partial.** Notifications are planned (`GTDNotifications.NotificationPlanner`, fully
  unit-tested), scheduled and routed (`App/NotificationService.swift`, tapping one opens the
  right screen). What they do not have is **actions on the notification itself** — "Start
  routine" on a routine reminder, "Done" on a due/follow-up one — so every notification costs a
  full app launch. Skipped by T13/T30, recorded in `docs/history/build-out/ORCHESTRATOR-NOTES.md`.
- **R3 is partial in the same way.** "Start via … home-screen button / Shortcut" is satisfied by
  the Routines tab and `StartRoutineIntent`. The `ControlWidget` (Control Centre / Lock Screen
  button) was skipped because there is no widget-extension target.

## Owns

`GTDNotifications/`, `App/NotificationService.swift`, `project.yml`, a new
`Widgets/` directory if the widget is built, `GTDIntents/`, `Shortcuts/README.md`,
`docs/MANUAL_TEST.md` §6.

## Deliverables

1. **Notification categories and actions.** One category per `NotificationKind` that has a
   sensible action:
   - `routineStart` → `Start routine` (opens the runner at step 1; the deep link already exists:
     `gtd://routine/<path>`),
   - `dueApproaching` / `followUp` → `Done` and `Snooze` is **forbidden** (STYLEGUIDE §6.2 bans
     the word and the concept); use `Chase` for a follow-up and nothing else for a due date.
   Handle them in the delegate. A background action that writes must go through the same
   `VaultBackend`, never straight to a file.
2. **The action must not lie.** If the app cannot complete the action in the background (no
   vault access, an evicted file), it opens the app on that item instead of silently doing
   nothing.
3. **Control Widget (R3).** A widget extension target in `project.yml`, one `ControlWidget`
   button per routine that opens the runner. Read-only: the widget never writes to the vault.
   If the extension cannot reach the vault through the security-scoped bookmark, **stop, write
   that down in the Result, and ship only the notification actions** — an app group / shared
   container is a design change for the user, not a decision for this task.
4. **An `AppEntity` for routines (R3, same theme).** `StartRoutineIntent.routine` is a plain
   `String` matched against the title, so Shortcuts shows a text field instead of a picker. Fine
   for two routines, wrong as soon as there are five. The entity query needs the routine list
   without loading the whole vault; if that turns out to be impossible, leave it and say so.
5. `docs/MANUAL_TEST.md` §6: one line per new action, the widget, and the Shortcuts picker.

## Acceptance

- A routine reminder can be started from the notification without opening the app first.
- Turning a kind off in Settings removes its pending notifications *and* its actions.
- `scripts/check.sh --app` green with the new target; `docs/TRACEABILITY.md` D2/R3 rows updated.

## Result

_(fill in when done)_
