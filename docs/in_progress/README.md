# In progress

Work that has a branch. Each ticket here is the **single source of truth** for that branch:
what is done, what remains, how to pick it up. It is updated before every push and before a
session could end (rule 3 in `docs/TICKETS.md`); `scripts/check-tickets.sh` fails when code
commits on the branch are newer than the ticket. When the PR merges, the ticket moves to
`docs/history/` with its **Outcome** filled in.
