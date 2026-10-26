# review-loop

Claude Code skills for the review loop: check a change before it goes out, measure how well the check works, and turn recurring findings into checks that run.

| Skill | What it does |
|---|---|
| `pre-pr-review` | Reviews a branch or range through a fixed set of lenses and mechanical sweeps, verifies every finding before reporting it, and writes a report. Single pass for a small change, multi-pass (up to three readers) before handing something over. |

| `review-eval` | Keeps verified past findings as test cases, runs the reviewer blind on them, and records recall and noise, so a change to the lenses is kept only if it measurably helped. |

More are planned, see [PLAN.md](PLAN.md).

## What a good review loop has, and where it lives here

| Piece | Where |
|---|---|
| Verify before asking for review: show a runnable result, review the diff with a fresh reader | `pre-pr-review`, sections 2 and 4 (read whole functions, confirm each finding in code) |
| A per-repo file that says what failure means, what to ignore and what to require | `REVIEW.md` ([example](REVIEW.example.md)) |
| Several reviewers in parallel, a vote on each finding, style filtered out, severity marked | `pre-pr-review` multipass (`references/multipass.md`) |
| Every finding fixed or closed with a reason; nothing merges with an open one | `scripts/review-gate.sh` |
| Fix what the reviewer keeps flagging at the source: a lint rule, a sweep, a doc line | `scripts/diff-sweeps.sh`, `REVIEW.sweeps`, "Keep it learning" |
| A review that converges: capped cycles, re-review the diff only, fix the class | `pre-pr-review` section 1 and multipass section 6 |
| Past incidents and findings are the eval; every change to the reviewer is rescored; noise is measured | `review-eval`, `scripts/review-score.sh` |
| Risk decides how much review a change gets | not yet (planned) |
| Explainers, so reading diffs is not the only way to learn the code | not yet (`explain-slice`, planned) |

## Use

Copy or link `skills/pre-pr-review` into `~/.claude/skills/` (or a project's `.claude/skills/`), or install this repository as a plugin. Then ask for a review of a branch, a PR or a range: `/pre-pr-review feature-branch`.

## Per-repo knowledge: `REVIEW.md`

The skills carry the method. What your repo specifically needs a reviewer to know goes in a `REVIEW.md` at its root, which the skills read first: what counts as a failure here, the paths that guard something (auth, installers, sandboxes, billing), paths to ignore, naming and API conventions, extra sweeps, and the finding classes your reviewers have raised before. [REVIEW.example.md](REVIEW.example.md) shows the shape. Keep it short.

## License

Apache-2.0, see [LICENSE](LICENSE).
