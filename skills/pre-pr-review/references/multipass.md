# Multi-pass review

One reader finds about two thirds of what an outside reviewer finds. Readers that each look through one group of lenses with nothing else on their mind find more, and mostly find different things: what a reader with another task skips. This mode runs them, then merges, votes on and verifies what they report.

It costs a full read of the diff per group. Use it before handing over a change; use the single pass (SKILL.md) for a small fix commit.

## 1. Scope

As in SKILL.md section 1. For a stack, run per branch, bottom first, on that branch's own commits. Skip a commit an earlier report already covers.

## 2. Groups (at most three readers)

| Reader | Lenses and sweeps |
|---|---|
| 1. Input, limits, tests | lenses 1, 6, 10; sweeps 2, 3, 4, 5 |
| 2. Error paths, state, concurrency, platform | lenses 2, 3, 9, 11, 17; sweeps 1, 6, 7, 9 |
| 3. Agreement, claims, dead code, routing, UI | lenses 4, 5, 8, 12, 13, 14, 15, 16; sweeps 8, 10, 11, 12 |

Drop what cannot apply (no UI code: skip lens 12) and say what was dropped.

## 3. Launching

- **Say how many readers and which model before launching**, and ask first when the diff is over about 1,500 changed lines.
- Use the cheapest model that can read code. Do the verification in the main session, where judgement is needed.
- Give each reader a file list, not the whole change: split a big change by directory so no reader has to read thousands of lines.
- Launch together so they run in parallel, unless the usage allowance is low: then one after another, and stop when the first report shows the extra readers are not finding more.

Give each reader:

- the working tree path and the exact range (the `git log` and `git diff` commands), read-only;
- the group's lenses and sweeps copied out of SKILL.md (the text, not a pointer), and the matching classes from `classes.md` and the repo's `REVIEW.md`;
- the rules: read whole functions and the callers and siblings needed; write the concrete failure for each candidate and confirm it in the code or with a probe; no style findings; edit nothing; post nothing; list what was read in full and what was skimmed; report in the SKILL.md section 5 format, prefixed with the reader number (`R2-3`);
- a cap of 15 findings, most severe first. "None found" is a valid answer.

Do not tell a reader what the others look for (that keeps them independent), and do not give them an outside reviewer's comments on the change.

## 4. Merge, vote, verify (main session)

1. Merge duplicates (same file and line range, same defect) and keep every reader id that found it.
2. **Vote.** A finding found by two or more readers stands. A finding from one reader needs you to confirm it in the code. Try to disprove each: mark it `confirmed`, `disproved` (say why) or `could not confirm`.
3. Drop style and cleanup findings. Mark the rest Important, Nit or Pre-existing.
4. Sort by severity; count per class and per reader.

## 5. Report file

Write the report where the repo keeps them (default `reviews/<branch with / as ->-<first 8 of tip>.md`):

```
# Review of <branch>
Reviewed-range: <full sha of base>..<full sha of tip>
Mode: multipass (readers 1 2 3, dropped: ...)
Date: <yyyy-mm-dd>
Cycle: <1 | 2 | 3>
Open: <number of confirmed findings with disposition "open">

## F1  <file>:<line>  [class]  <Important|Nit|Pre-existing>  <confirmed|could not confirm>   found by: R1-2, R3-1
What / Failure / Fix / Class as in SKILL.md section 5
Disposition: fixed in <sha> | not changed: <reason> | open

## Read in full / skimmed / not run
```

A repo that gates hand-over on reports can check for `Open: 0` and for a range that covers every commit. After fixing findings, review the fix commits (single pass is enough) and write a second report whose range starts at the first report's tip, with `Cycle` one higher.

## 6. Convergence

- After the first cycle, review the new diff only.
- Group findings by class and fix each class everywhere in one commit; a reader that finds the same class in the next cycle means the fix was too narrow.
- At cycle 3, stop and ask whether the approach is right.
- Of what a reviewer flags in later cycles, much is old code that was always there. Mark those Pre-existing and keep them out of the author's count.

## 7. Score

After outside review of the pushed change, record in the repo's score log: round, change, findings this review had already reported and fixed, new findings from outside, and how many of this review's findings the outside reviewers or author rejected. Recall is found / (found + new outside). Noise is rejected / reported. The `review-eval` skill (planned) keeps the log and reruns the reviewer against past findings.
