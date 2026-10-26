---
name: review-eval
description: Measure how well the self-review works, and whether a change to its lenses, prompts or model helped. Keeps a set of past findings as test cases, runs the reviewer blind on them, and records recall and noise. Use after outside review of a change, before and after editing the review skill, and every few rounds as a hold-out.
argument-hint: "[new-case | run <case> | report | diff <runA> <runB>]"
disable-model-invocation: true
---

# Review eval

A list of past findings is not learning: it makes the next review longer, not better. This skill makes the reviewer answer to its own history. Every finding that outside reviewers (people, bots, incident reviews) raised on a change becomes a test case; the reviewer is run blind on the change as it was before the fix; what it found and missed is recorded. Whenever the lenses, prompts or model change, the reviewer is rescored against the whole set, and the change is kept only if recall did not fall and noise did not rise.

Two numbers matter, and both are needed: **recall** (of the real problems, how many the review reported) and **noise** (of what the review reported, how much was wrong or not worth a comment). Recall can always be raised by reporting more; noise is what that costs the author, and an author that is an agent pays for each nit with another commit and another cycle.

## The eval set

One directory per case under `evals/` (or `$EVALS_DIR`): `evals/<id>/case.md`.

```
Case: <id>
Range: <full sha of base>..<full sha of tip>     # the change as it was reviewed, before any finding was fixed
Source: <outside reviewer | incident | audit, with a link or a number>
Date: <yyyy-mm-dd>
Groups: <optional: tags of the round or batch this case belongs to, space separated>

Findings (one per line: id | path:line | class | the defect, in a sentence):

F1 | src/session/store.cpp:212 | state | a damaged metadata file is read as "no metadata", so the next write replaces it
F2 | src/api/params.cpp:88 | validation | a non-string `model_id` is treated as absent
```

Rules for a good case:

- The tip is a real commit that still exists (keep a tag or branch for it, or the case cannot be rerun).
- Every finding was **verified** by a person who knows the code: where the bug is and that it is a bug. A wrong outside comment is not a finding; record it in the Source line as rejected so nobody adds it later.
- A finding says what input or state breaks what, not "this looks risky".
- Incidents and reverts are the best cases: they are the bugs that really cost something. Add the change that caused the incident, the fix-forward, and where the bug was.

`scripts/eval-case.sh new <id> <base> <tip> [source]` creates the file; `eval-case.sh list` lists the cases.

## Running a case (the hold-out)

1. `scripts/eval-blind.sh [--archive] <id> <dest>` sets up the change at `<dest>`, without `evals/` and without the lines of `REVIEW.md` tagged `case:<id>`, or `case:<group>` for a group on the case's `Groups:` line (tag a class line in `REVIEW.md` when it was written because of that case, or because of the round the case came from: a reviewer that can read it has been told the answer). It puts the repository's current `REVIEW.md` (or the file named by `$REVIEW_FILE`, for one kept outside the repository) into `<dest>`, since an old tip has none, and prints the instructions for the reviewer. By default `<dest>` is a detached worktree, which shares the repository's object store, so "no history after the tip" is a rule the reviewer is told. With `--archive` it is a plain tree with no history, plus `range.diff`, `changed-files.txt`, the skill text in `_skill/` and every mechanical sweep hit in `_sweep-hits.txt`: use that for a strict run.
2. Run the `pre-pr-review` skill (multipass if that is what is being measured) in `<dest>` with those instructions. Use a fresh reader with nothing else in its context: a reader that has seen the findings proves nothing. Say which model and how many readers before launching.
3. Compare the report with the case, finding by finding. Record each: `scripts/eval-record.sh finding <run> <case> <Fn> found|partial|missed [note]`. **found**: the report names the same defect at the same place, or the same bug at another line. **partial**: the same line with part of the defect, or the opposite conclusion. **missed**: not reported.
4. Go through what the report found that is **not** in the case. Confirm each in the code. `eval-record.sh extra <run> <case> real|rejected [note]`. A real extra is a bug nobody had found: add it to the case as a new finding with a note, after verifying. A rejected extra is noise and counts against the reviewer.
5. Record what each run cost: `scripts/eval-record.sh cost <run> <case> <tokens> [model]` (the tokens the readers and the verify step used, added up from what the agent reports; record one for every case of the run). `scripts/eval-report.sh` then prints recall (strict and with partials) and noise per run and per case, and tokens per case and recall per 100k tokens, so a cheaper model or fewer readers is judged on what it costs per finding. Remove the worktree: `git worktree remove --force <dest>`.

`<run>` labels what was being measured: a date, or the version of the lenses (`lenses-v3`).

## Changing the reviewer

Before editing the lenses, sweeps or prompts: run the set once and keep the run label. After editing: run again under a new label, then `eval-report.sh diff <old> <new>`. It lists the findings whose verdict changed. Keep the edit if findings moved from missed to found and none moved the other way, and noise did not rise; otherwise it did not help, whatever it felt like. Never score on the cases a change was written from: the lines that came from a case carry its tag precisely so the blind run can drop them.

## Cost

A run is a full multipass review of the change. Do not run the whole set on every edit: run the cases that share the class you touched, and the whole set every few rounds. Use the cheapest model that can read code for the readers, three at most.

## What the set tells you

- Recall by class shows which lens is weak: if state and ordering bugs inside one function are missed on every case, the answer is a sweep or a narrower reader, not a longer list.
- A class that is missed on two cases that were written months apart is the next script or lint rule (see `pre-pr-review`, "Keep it learning").
- Noise by lens shows which lenses are too loose to keep.
- A case the reviewer has found every time for five runs can leave the routine set (keep it for the full run).

See `references/method.md` for the choices behind this and for pitfalls.
