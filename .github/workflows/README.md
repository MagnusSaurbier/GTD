# CI policy — Actions minutes are spent only on code that matters

There are no workflows yet. When one is added, it follows these rules, and
`scripts/check-workflows.sh` (part of `scripts/check.sh`) fails the gate when it does not.

1. **Docs never trigger anything.** Every `push:` and `pull_request:` trigger carries
   `paths-ignore` with at least `'**.md'`, `'docs/**'`, `'.claude/**'` and `'.github/**.md'`.
   A commit that touches only those paths runs no workflow at all.
2. **Belt and braces: docs-only commits say so.** A commit that changes only documentation,
   tickets or agent config ends its subject line with `[skip ci]`. GitHub skips every `push` and
   `pull_request` workflow for such a commit, whatever the workflow says.
3. **Test/build workflows run on `main` and on pull requests only**, never on every push to
   every branch: `push: branches: [main]` plus `pull_request: branches: [main]`. Pushing a
   work-in-progress branch costs nothing; opening the PR is the moment CI starts.
4. **Deployments are never triggered by a push.** A workflow that ships anything — TestFlight,
   a release, a notarised build, a cloud deploy — runs only on `workflow_dispatch` or on a
   version tag (`tags: ['v*']`). Tag or dispatch **only for a merge that changes significant
   functionality**; a fix, a refactor or a docs change does not get a tag. Its file name
   contains `deploy`, `release` or `distribute` so the checker can tell it apart.
5. **`concurrency` with `cancel-in-progress: true`** on every test/build workflow, keyed by
   workflow and ref, so a second push to a PR cancels the run of the first. (Not on deploys: a
   half-cancelled upload is worse than a finished one.)
6. Nothing runs on a schedule.

What "significant functionality" means: the user can do something they could not do before, or
a documented behaviour changed. The issue's **Outcome** says which it was.
