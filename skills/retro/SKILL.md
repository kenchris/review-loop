---
name: retro
description: After a round of outside review (people, bots, CI, an incident), work out why the self-review missed what it missed and propose changes to the review setup, ranked by severity: a sweep or lint rule for what is mechanical, a REVIEW.md line for judgement calls, deletion of lines that change nothing. Use after outside reviewers raised findings the self-review did not, after an incident, or when REVIEW.md or the lenses have grown long. Not for deciding thread verdicts (use `triage` first: `retro` learns from those decisions), and not for reviewing a change (use `pre-pr-review`).
license: Apache-2.0
argument-hint: "[round | PR numbers | path to the findings] [--apply]"
disable-model-invocation: true
---

# Retro

The self-review gets better only when something about the setup changes: a check that runs, a line that a reader follows, a line deleted because it changed nothing. This skill turns one round of outside findings into that list of changes. It changes the environment, not the code under review.

## 1. Gather the evidence

Read, before proposing anything:

- the outside findings of the round (an export of review threads, CI failures, an incident review), each with the file and line and what the outside reviewer said was wrong. For review threads on GitHub, `review-loop threads fetch`, then `ingest` and `worksheet` (`references/threads.md`) produce this list with the thread's status, the commit the reviewer saw, and the nearest self-review report entry, and the ledger remembers every decision from earlier rounds;
- the self-review reports for the same changes (`reviews/`), so each outside finding can be matched to "reported" or "not reported";
- the repo's existing checks: lint config, CI jobs, hooks, `REVIEW.sweeps`, `REVIEW.md`. A check that exists but is not wired in, or is broken, is itself a finding;
- `review-loop score show` and, if cases exist, `review-eval` results.

Done when every outside finding is in a table with one of three verdicts: **caught** (the self-review reported it), **missed**, or **rejected** (the outside reviewer was wrong; say why).

## 2. Find why each miss happened

For each missed finding, name the first cause that applies (the list is in `references/miss-causes.md`): no lens covers it; a lens covers it but the reader skipped it; it was greppable and no sweep exists; it was in code the change did not add (an existing function the new code depends on); it was outside every reader's share; the reader lacked context (a spec, a caller, a config); the reader found it and the verification step dropped it.

Group the misses by cause and by class of bug. A cause that explains several misses is worth more than one that explains one.

## 3. Choose the cheapest change that would have caught it

Take the first option that fits:

1. **A check that runs**: a sweep (`REVIEW.sweeps`), a lint rule in the repo's own linter, a unit test, a CI job. Use it for anything mechanical: a fixed syntax pattern, a banned call, a type that must be checked first. A hit costs a reader seconds; a line in `REVIEW.md` costs attention on every review.
2. **A pointer**: a short line in `REVIEW.md` or a skill that names where to look and when ("on any new reader of stored JSON, check the type before the value").
3. **A lens or reader change**: only when the class needs a different way of reading (a reader share that left a function unread, a missing reader for a spec).
4. **A context change**: give the reader the information it lacked (spec text, the caller list, the config) by adding it to the prompt or the registry.
5. **A `REVIEW.md` class line**: last, and only for a judgement call no check can make. One line: the pattern, an example, how to spot it.

Prefer an existing file over a new one. Keep the always-loaded text short: a document that has to be read in full on every review is read worse.

## 4. Prune

For each line of `REVIEW.md` and each lens, ask what a reader does differently because of it. A line that changes nothing is a no-op: delete it. A class the new sweep now covers needs no line. Two lines saying the same thing become one. State the pruning as a proposal with the eval cases that share the class, since a cut is kept only if recall did not fall (`review-eval`).

## 5. Report

A list ranked by severity (a change that would have caught an Important miss first), each entry:

```
R1  [sweep | lint | pointer | lens | context | class line | prune]   severity of what it would have caught
Evidence: <the outside findings (and reports) behind it>
Change:   <the exact file and text to add, change or delete>
Check:    <how to know it works: the eval case or test it becomes, and the sweep hit it should produce>
```

End with the round's numbers (found, missed, rejected, recall, noise), and the misses no cheap change covers, listed honestly as "still missed".

Propose first; apply on agreement (`--apply` after the owner has seen the list). After applying: add each verified miss to the eval cases, rescore the cases that share the class, and record the round with `review-loop score add <round> <change> <found> <outside-new> <rejected>`.

## Rules

- When the same class is missed in two rounds, a line in `REVIEW.md` is not enough: it needs a check or a reader change.
- A change must name the outside finding that justifies it. No evidence, no change.
- The self-review's own noise counts too: a lens whose findings outside reviewers keep rejecting is a candidate for pruning.
- The implementation agent has the most context pressure and the reviewer the least, so put the checking in the reviewer and the sweeps, not in longer instructions to the implementer.
- Do not write tooling-specific disclaimers or attribution into anything the retro produces.
