# review-loop

Claude Code skills for the review loop: check a change before it goes out, measure how well the check works, and turn recurring findings into checks that run.

| Skill | What it does |
|---|---|
| `pre-pr-review` | Reviews a branch or range through a fixed set of lenses and mechanical sweeps, verifies every finding before reporting it, and writes a report. Single pass for a small change, multi-pass (up to three readers) before handing something over. |

More are planned, see [PLAN.md](PLAN.md).

## Use

Copy or link `skills/pre-pr-review` into `~/.claude/skills/` (or a project's `.claude/skills/`), or install this repository as a plugin. Then ask for a review of a branch, a PR or a range: `/pre-pr-review feature-branch`.

## Per-repo knowledge: `REVIEW.md`

The skills carry the method. What your repo specifically needs a reviewer to know goes in a `REVIEW.md` at its root, which the skills read first: what counts as a failure here, the paths that guard something (auth, installers, sandboxes, billing), paths to ignore, naming and API conventions, extra sweeps, and the finding classes your reviewers have raised before. [REVIEW.example.md](REVIEW.example.md) shows the shape. Keep it short.

## License

Apache-2.0, see [LICENSE](LICENSE).
