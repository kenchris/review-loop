# review-loop: plan

A small set of Claude Code skills for the review loop around a change: check it yourself before it goes out, measure how well that check works, and turn what the reviewers (people, bots, CI) keep finding into checks that run.

## Principles

- **Generic.** Skills describe method, not a product. Anything specific to one repo (its guard paths, API conventions, past findings, extra sweeps) lives in that repo's `REVIEW.md`, which the skills read when it exists.
- **Standalone.** POSIX shell and git only. No dependency on any hand-off, push or stacking tooling; a repo that has such tooling can call these scripts, not the other way round.
- **Learning is measured.** A list of past findings is not learning. Recall and noise are recorded per round, the reviewer is rescored against the past findings whenever its lenses change, and a class that repeats becomes a script or a lint rule.
- **Converges.** At most three review cycles per change; after the first, review only the new diff; fix the class of a bug, not the one line.

## Layout

    skills/<name>/SKILL.md          method, short enough to read in one go
    skills/<name>/references/       lenses, report formats, worked examples
    skills/<name>/scripts/          optional helpers (POSIX sh + git)
    REVIEW.example.md               what a repo puts in its own REVIEW.md

## Order

1. `pre-pr-review`: lenses, mechanical sweeps, verify-before-report, severity and vote, cycle cap, report format. (done in this commit)
2. `review-eval`: eval-set format (finding, commit before the fix, where the bug is), a blind-run setup, a recorder and a recall and noise report. (done)
3. `triage`: import an external reviewer's threads, group them by class, mark each fix / reply-only / reject, fix the class.
4. `sweeps`: a skill of its own for growing the sweep files (the script and the first sweep files ship with `pre-pr-review` already; the gate and score scripts too).
5. `explain-slice`: an up-to-date explainer for a module, so reading diffs is not the only way to learn the code.
6. `risk-tier`: classify a change by the paths it touches (from `REVIEW.md`) into quick, standard or deep review, and name the paths that always need a person.

Out of scope here: anything that builds bundles, push plans or reply scripts for a particular hosting setup.

## Open

- Whether the report format should carry a machine-readable header for a merge gate (a range and an open count), or leave that to the repo.
