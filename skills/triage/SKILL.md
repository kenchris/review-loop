---
name: triage
description: Decide the review threads of a round without doing it one thread at a time. Reads every undecided thread (from Copilot, CI bots or people) against the code, proposes a verdict for each with the evidence, and records the ones you confirm in a single call. Use after `review-loop threads sync`, before `/retro`, when a round has more undecided threads than you want to decide by hand. Not for reviewing a change (use `pre-pr-review`), and not for working out why a review missed something (use `retro`, after the threads are decided).
license: Apache-2.0
argument-hint: "[PR numbers]"
disable-model-invocation: true
---

# Triage

A verdict is the owner's decision about one outside thread: fixed, wrong, already reported, real but not now. The ledger needs one for every thread before `/retro` can learn from the round, and deciding forty of them by hand is the part people skip. This skill does the reading and proposes; you confirm once; it records. Nothing is recorded that you did not confirm, and nothing is posted to GitHub.

You start it yourself: it writes decisions to the ledger.

## 1. Gather

- `review-loop threads worksheet` lists what is undecided (and what was marked `missed`), each with the nearest entry of your own review report as a hint. If the ledger is empty or old, ask for the repository (`owner/name`) and run `review-loop threads sync --repo owner/name` first. Do not guess a repository.
- With PR numbers as the argument, keep only those pull requests (`review-loop threads list --verdict new --pr <n>`).
- For each thread read the whole thread, not the first line: the ledger (`$THREADS_LEDGER`, or `reviews/threads-ledger.json` in `$REVIEWS_DIR`) holds every comment. A later comment in the thread often says the author already answered.
- Read the code the reviewer saw: `git show <commit_reviewed>:<path>` around the line. Then the code now, and what happened in between: `git log --oneline <commit_reviewed>..HEAD -- <path>` and the diff of any commit that touched that spot.

## 2. Decide a proposal for each thread

Verify, do not trust: an outside comment is cheap and sometimes wrong, and so is a proposal. Write the concrete reason ("`top_k: 1.5` passes the check and reaches the sampler as 1") and confirm it in the code. Then take the first line that fits:

| Proposal | When | What you attach |
|---|---|---|
| `fixed` | the comment is right, and a commit after `commit_reviewed` changed that spot to address it | the sha, after reading its diff |
| `caught` | the comment is right, and an entry of the self-review report describes the same defect | the report and entry (nearness alone is not enough: read it) |
| `missed` | the comment is right, the self-review did not report it, and it is not fixed yet | what it would take to fix |
| `rejected` | the comment is wrong or does not apply | the reason, from the code: what it does that makes the comment wrong |
| `deferred` | real, and the owner or the PR text says not now | the quote, or leave it to the owner to say |
| left `new` | you could not confirm it either way | what you would need to know |

- A comment from a person (not a bot) usually carries a design point. Propose a verdict if the code settles it, but mark it as a judgement for the owner, never as obvious.
- Do not propose `fixed` without a commit you have read. Do not propose `rejected` without a reason a person can check.
- Do not edit code in this skill. A real comment that is not fixed yet is `missed`, or left undecided, with what it would take.

## 3. Propose, once

Show one table, grouped by proposal, most important first:

```
id        where                    who        comment (short)                       proposal   evidence
a1b2c3d   js/secretCode.js:196     copilot    listener never removed                rejected   added once in init, page lives as long as the game
```

Under it: counts per proposal, the threads left undecided and why, and the list of human comments marked for the owner's judgement. Then ask once: apply all of it, or which ids to change or skip. Say exactly what you will run. "Apply all" is a valid confirmation, and so is a list of corrections.

For more than about 25 threads, read them in shares (by pull request or by file), up to three read-only readers, one share each. Say how many readers and which model before launching, as in `pre-pr-review` multipass. Check the proposals yourself before showing them.

## 4. Record

Write the confirmed decisions to a temporary file, one per line, fields separated by a tab: the id (a piece of it is enough), the verdict, the fixing commit or `-`, the note or `-`.

```
a1b2c3d	rejected	-	added once in init, the page lives as long as the game
e4f5a6b	fixed	9c8d7e6	range check added in 9c8d7e6
```

Then one call:

```
review-loop threads verdict --batch <file>
```

It checks every line first and records nothing if one line is wrong (an id that matches no thread or two, an unknown verdict), so a typo cannot leave a half-decided round.

## 5. Finish

Report how many were recorded and how many are still undecided. When none are left, suggest `/retro round <name>`. Optionally `review-loop threads cases --evals evals --repo-dir . --tag` turns the `fixed` ones into eval cases.

## Rules

- A verdict is the owner's decision. Never record one that was not confirmed.
- A wrong comment is recorded as `rejected` with its reason: the reason is what keeps it out of the eval and stops it being fixed twice.
- "Could not confirm" is an answer. Leave the thread undecided rather than guess.
- Post nothing to GitHub, resolve no thread, change no code.
