---
name: pre-pr-review
description: Review a branch, PR or commit range the way a careful external reviewer would, before it goes out, so the findings are fixed in the same round instead of arriving one batch at a time. Use before pushing or handing over a change, when asked for a self-review or pre-PR review, and after a fix round (fix commits get reviewed too).
argument-hint: "[PR number | branch | base..head | 'stack'] [multipass] [--fix]"
---

# Pre-PR review

A good reviewer reads every changed hunk with the code around it and reports one problem per comment, each saying what input or state makes it wrong. Most of what such a reviewer finds is not style: it is validation gaps, error paths that report success, state reset in one place and not another, and claims (comments, docs, tests) that the code does not back. This skill makes you do that pass first, and keeps it from running forever.

If the repo has a `REVIEW.md`, read it first: what counts as a failure there, which paths guard something, what to ignore, its conventions, and the finding classes its reviewers have raised before. `references/classes.md` lists classes that recur across projects; use both as lenses.

## 1. Scope

- The argument is a PR number, a branch, `base..head`, or nothing (the current branch against its PR base, else the default branch). `stack`: every branch of a stack, bottom first; review each PR's own commits, not the cumulative diff.
- `git diff --stat <base>...<head>` and `git log --oneline <base>..<head>`. Skip generated and vendored files and lock files (and whatever `REVIEW.md` ignores).
- Review each commit's effect on the final tree, and report against the final tree. A fix commit is reviewed like new code: reviewers comment on those too.
- **Cycles.** The first pass reads the whole change. A second pass reads only what changed since the first. After three passes, stop and ask whether the approach is right instead of looking for a fourth round of line fixes. Do not re-report what an earlier pass reported and the author answered.

## 2. Read, don't skim

For every changed file, read the whole function around each hunk, and the callers and siblings you need to answer a question, not only the diff lines. Say in the report what you read in full and what you skimmed. Code that guards a boundary (authentication, sandboxes, file and path access, tokens, proxies, installers that run with elevated rights) must be read in full and attacked: for each check, what reaches the protected thing without passing it?

## 3. Lenses (run every hunk through these)

1. **Untrusted and stored input.** Anything from a client, a stored file, a tool result, a model, a config value: what if it is missing, `null`, the wrong type (a scalar where an object is expected), an array, negative, fractional, huge, NaN, empty, megabytes long, multibyte? A type check is not a range check. A present-but-wrong value is rejected, not treated like an absent one.
2. **Error paths tell the truth.** Every `bool`/status/`success` return: can it be true after a write, read, parse or spawn failed? Is an error swallowed, logged and then ignored, or turned into "empty/null/new"? A damaged file is not a missing file. Does a failure after a "started" event also send a "failed" or "done"?
3. **State and lifecycle.** For each flag or cache, list every writer and every reset. Is one reset and not its partner? Reload, reconnect, cancel, retry, switching context, concurrent requests, shutdown during work. Check-then-use: what can change between the check and the use?
4. **Two places must agree.** A value computed in one place and used in another; a setting that reaches the top-level path but not the nested one, the other transport, the other backend; a value copied into a request and then overwritten. Search for every sibling and caller.
5. **Claims are true.** A comment, doc, test name, commit message or log line that says "never", "always", "guarantees", "only", "same as": verify it for every backend and caller. A document that contradicts the code is a finding.
6. **Limits, units and sizes.** Bytes vs characters (slicing multibyte text), tokens vs bytes, page sizes that undercount, checks that run before the thing they must account for is added (a hint, a wrapper), a total vs per-item caps, off-by-one, integer width and sign, overflow, defaults larger than the space left.
7. **Cost on hot paths.** Work repeated per message, call or turn; unbounded growth of logs, maps and queues.
8. **Routing and protocol.** A request that falls through to a more generic handler, auth or CORS applied in one handler but not its twin, registration order, methods not covered.
9. **Platform.** Differences between operating systems, runtimes and compilers: path case, rename over an existing file, special files, string literal limits, debug vs release.
10. **Tests.** Does a test exercise each new branch, the failure branch included? Do tests share fixed temp paths (parallel jobs collide)? Does a test that skips for a missing environment mean the code ran at all? Would the test fail if the fix were reverted?
11. **Concurrency.** Every shared mutable thing the diff adds or touches: function-static state, plain members written on one thread and read on another, publishing an object before its start returns, a decision made under a lock and acted on after releasing it, a snapshot used after a reset, a temp file name shared by two writers. Which threads call this, and what if two do at once?
12. **UI lifecycle and async.** Listeners added without the matching removal; an async API used as if synchronous; results of an async call installed after a newer navigation (use a generation counter); state reset in one place but not its partner; DOM changed outside the framework's state; replay paths that overwrite user state.
13. **Dead, duplicate and mismatched code.** A new helper nothing calls (the feature is silently not wired in); a block copied twice; the same entry registered twice; a name spelled differently in two places; a schema that says `required` for something the code makes optional; an override that merges where the comment says it replaces; a value parsed but never passed on.
14. **Text matches the shipped scope.** The PR description, commit message, plan doc, README examples (is that command valid?) and code comments against what this change does: features described as shipped that arrive later, stale references to removed code, a limitation listed that something already lifts.
15. **Repo rules.** Whatever `REVIEW.md` and the contributor docs require: naming and API conventions, attribution rules, what docs may say, each commit building on its own.
16. **Other doors to the same resource.** For every guard (a URL or domain policy, a scope list, a permission, a sandbox, a token): list the other paths that reach what it protects (redirects, a second client, a proxy that resolves names itself, a nested or scripted caller, a cache read, a retry, the second backend) and check each carries the same scope and check. An empty scope must not mean "everything" on a path that forgot to pass it. Test for parity.
17. **Policy values on the unhappy machine.** For every policy field the diff accepts: what happens when the state it depends on is missing (a model not loaded, no browser, offline, asleep)? A value accepted but treated as another value, or one that makes an unattended job silently skip, is a finding: implement it, or refuse it with a message; add the scenario as a test; make the waiting state visible.
18. **CI-only failures.** Rebase onto the target branch (a conflict there is what CI hits), rebuild after it, run the suites for anything the diff touches.
19. **Spec conformance (only when the change implements an external specification).** The specs a repo implements are listed in `REVIEW.md` under "Specs we implement" (name, pinned version, where the text is, which paths implement which part), or were handed over with the task. A plan or design document is not a spec: it is the intent that lens 14 checks the text against. For each requirement the change touches, check the code against the spec text, in three shapes: a requirement the code omits or only half meets, behaviour the spec forbids (or the change adds beyond it), and something that looks implemented but is wrong. **Quote the requirement and the code line.** A breach of MUST / MUST NOT is Important, SHOULD / SHOULD NOT is Nit, MAY is not a finding. A finding without a quoted rule is dropped. Something the spec marks deprecated, or the entry lists under "Deliberately not implemented", is not a finding when it is absent; adding back a part the repo dropped on purpose is one. If the entry says `latest`, fetch the current text at review time and state in the report which revision and date you read (`Spec: checked <name> <revision read>`); a quote is checkable only against a named revision. If the diff touches a spec's paths and there is no entry, ask which spec and version before reviewing.

## 3b. Mechanical sweeps (a design read misses these)

Run each as a search over the changed files and look at every hit. A hit is a finding until you can say why not.

1. **Ignored results.** A call whose bool, status, error code or optional result is dropped: writes, saves, renames, removals, initialisers, starts. What does the caller report on failure, and is anything deleted afterwards on the assumption it worked?
2. **Typed access to data you do not own.** Typed getters, indexing and lookups on JSON or other data from a client, file or tool; string-to-number conversions; `front()`/`back()` on a maybe-empty container; a search result used as an offset without a not-found check.
3. **Arithmetic on stored or client numbers.** `+ 1`, `* n`, subtraction, casts to unsigned or narrower types: what happens at the largest and the negative value?
4. **Copies and loops over client-sized data.** A loop over an array, a copy of a string, serialising a whole message: bounded before the work, or only after?
5. **A budget applied per item.** A cap or floor applied to each of N items: what is the total? Is the cap checked before or after a wrapper, hint or escaping is added?
6. **Listeners, timers, threads, handles.** For each one started: where is it stopped, and does the stop run on every exit path, exceptions included?
7. **"Started" events.** For each event that says started or begin: does every exit path send the matching done or failed?
8. **New names.** Every new function, file, setting, scenario or element: is it called, imported or registered from production code, and exactly once?
9. **Handles and OS results.** Every file, process, pipe or socket opened: checked for failure before use, closed on every path, not inherited by a child that should not have it.
10. **Persisted shapes.** Every `contains`, key access, `size` or `length` on a value read from storage or a client: is the container type checked first?
11. **A changed lookup or normalisation (aliases, spellings, ids, paths).** Search for the OLD form across every file and list each hit with the route it belongs to; each must use the new rule. A function you changed must have a caller.
12. **A cascade or merge you did.** Scan every branch for conflict markers, check that appended tests still close, compare trees before and after a rebase (the diff must be empty or explained).

`scripts/diff-sweeps.sh <base> <tip>` runs the greppable ones for you over the lines the range added, and prints each hit as a question. The patterns live in `scripts/sweeps/*.sweeps` (C and C++, JavaScript, general); a repo adds its own in a `REVIEW.sweeps` file at its root, one `name ## globs ## regex ## why` per line. Ordinary sweeps show at most 12 hits each (`DIFF_SWEEPS_MAX`, 0 for all); a sweep whose name starts with `!` is high priority: it is listed first and never capped, because what it points at (a thrown exception, a dropped write result, a leaked handle) is what a cap must not hide. Mark a sweep `!` when a missed hit costs more than reading the extra lines. When a class has been found twice, make it a sweep or a lint rule instead of a line here.

## 4. Verify before you report

External reviewers are cheap and sometimes wrong; yours should not be. For each candidate, write the concrete failure ("`top_k: 1.5` passes the check and reaches the sampler as 1") and confirm it in the code. If a test or a three-line probe settles it, run it. Drop what you cannot make concrete, or list it under "could not confirm". Do not discount a finding because it is "hardening", "documented" or "only in tests".

## 5. Report

One entry per finding, most severe first:

```
F3  path/to/file:235   [correctness | validation | state | claim | limits | cost | routing | platform | test | rules]   Important | Nit | Pre-existing
What:    <one sentence: the defect>
Failure: <input or state -> wrong result>
Fix:     <concrete change; the test to add>
Class:   <the class of bug, and the other places to look for it>
Rule:    <spec findings only: the requirement quoted from the spec, with its section>
```

- **Important**: wrong behaviour, a hole, or a false claim that someone will act on. **Nit**: real but small. **Pre-existing**: not introduced by this change; report it, do not count it against the author.
- Style-only and cleanup-only observations are left out.
- Then: what was read in full, what was skimmed, what was run, what could not be run, and a count per class.
- Post nothing to a hosting service unless asked.

If `--fix` is given, or the developer asks afterwards: propose the plan first and get agreement, then fix the **class** of each finding, not only the line (search for the other places, per `Class:`), in the commit it belongs to, add the regression test, review the fix commits, and only then hand over.

## 6. Keep it learning

After each round of outside review, for every finding this review did not catch:

1. Add one line to the repo's `REVIEW.md` under its class: the pattern, the example, how to spot it. If it is greppable, add a sweep or a lint rule instead.
2. Record the round with `scripts/review-score.sh add <round> <change> <found> <outside-new> <rejected>`: how many of the outside findings this review had already reported (recall), and how many of this review's findings the outside reviewers or author rejected (noise). `review-score.sh show` prints both per round. A falling recall means the lenses need the new class; rising noise means a lens is too loose.
3. When the same class shows up a second time, stop adding lines: make it a check that runs.

## 7. Multi-pass mode

`/pre-pr-review multipass <target>` runs up to three independent readers, each looking through one group of lenses (a fourth, for spec conformance, when the change touches a spec listed in `REVIEW.md`), then merges, votes on and verifies what they report. Use it before handing over a change that is not small: `review-loop depth <base> <tip>` says whether a change needs it (documentation and tests only, or a small code change away from any guard path, is one reader; a guard path is always multipass) and which model to use. A single-reader report written in the same format satisfies the gate. Procedure, prompts and report file: `references/multipass.md`.
