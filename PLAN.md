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

## Decisions of 2026-10-26 (from reading other skill collections, then an interview with the owner)

Taken from a public collection of engineering skills (`mattpocock/skills`): a separate Spec axis for code review, a post-session `retro`, the writing rules of `writing-for-agents`, a gated fix procedure from `diagnosing-bugs`, a Summary / Evidence / Merge-danger PR body from `pr`, and explicit finding states plus an out-of-scope record from `triage`. Not taken: a disclaimer on generated comments (conflicts with the no-attribution rule). Kept as ours: verifying every finding, voting, severity, the cycle cap.

Decided:

1. **Spec means an external specification** (a protocol or format the change implements, such as MCP), not a plan document. A plan stays an intent check (lens 14). A real spec gets rule-by-rule conformance.
2. **Where it is known:** a "Specs we implement" section in `REVIEW.md` (name, pinned version or date, where the text is, which paths implement which part). When the owner hands over a spec to implement, the implementer adds or refreshes the entry as part of that work. A diff touching spec paths with no entry makes the reviewer ask.
3. **Who checks it:** a fourth reader (Spec) when the change touches a listed spec path; otherwise the intent check is part of reader 3. The three-reader cap has this one exception.
4. **Spec findings** quote the requirement text and the code that breaks or omits it. MUST / MUST NOT is Important, SHOULD is Nit, MAY is not a finding. A finding without a quoted rule is dropped.
5. **Gate:** `review-gate.sh` takes several required lines (`REVIEW.gate`: `Name ## path regex`), for example `Casing` for an API surface and `Spec` for a spec path. The old single pair still works.
6. **Invocation:** multipass stays model-invocable (a hand-off requires it); `review-eval` is user-invoked only.
7. **Pruning `REVIEW.md`:** judged by the eval (remove or merge lines, rescore the cases that share the class, keep the cut only if recall did not fall). Needs more cases first: turn the fix commits of the last two rounds into cases.

Order: (a) Spec axis in the skill and the multipass doc, the REVIEW.md section; (b) generalised gate with tests; (c) invocation flag on review-eval; (d) cases from the round fix commits; (e) `retro`, `triage`, a gated fix procedure and `risk-tier`, each after its design is agreed.

(Done 2026-10-26: step (e) `retro`. Still to do: the cases from the round fix commits and the pruning they judge, `triage`, a gated fix procedure, `risk-tier`, `explain-slice`.)
