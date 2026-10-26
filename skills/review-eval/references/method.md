# Method notes

## Why incidents and outside findings

The test set must come from bugs that really existed and were verified by someone who understands the code, not from what the reviewer would think to look for. Incident-causing changes with their fix-forwards and reverts are the strongest source (the code was wrong in a way that cost something). Outside reviewers' comments, after a person confirmed them, are the cheapest source and come in volume. Add every verified finding, not a sample: the reviewer is judged on the misses, and a sample hides them.

## Blind means blind

A reviewer that has read the findings, the outside discussion, the fix commit or a rule written because of this very change will find it. The hold-out removes all four:

- the checkout is the change before the fix (a later commit would show the fix);
- no evals directory and no history after the tip;
- the lines of `REVIEW.md` that came from the case are dropped (tag them `case:<id>`);
- a fresh reader with an empty context, never the session that wrote the case.

If a case has been used to write a lens line, the case is no longer a fair test of that line. It still measures everything else.

## Recall without noise is meaningless

A reviewer that reports forty findings per change has high recall and costs the author a day. Count extras: confirm each in the code, mark it real or rejected, and report noise next to recall. Run the reviewer on changes known to be clean too (a commit that only renames, a docs fix) and count what it reports; each report there is noise by construction.

## Partial credit

Count `partial` as half in recall and report the strict number beside it. A partial usually means the reviewer saw the line and drew the wrong conclusion; that is a lens problem, not a coverage problem, and worth a note.

## Small numbers

A case has 5 to 15 findings. A single run on one case moves recall by 7 to 20 points; do not read a trend into one run. Compare runs on the same cases, over at least three cases, and look at which findings changed (`eval-report.sh diff`), not at the percentage.

## Stale cases

A case needs its tip to exist. Keep a tag per case (`eval/<id>`) in the repository so garbage collection and history rewrites do not take it. If code is later reformatted or moved, the case still works: it runs on the old tree.

## The loop

1. Outside review finds something the self-review missed.
2. Add it to the case for that change; add a class line to `REVIEW.md` tagged `case:<id>`; if it is greppable, add a sweep instead.
3. Rescore the cases that share the class, not the case the line came from.
4. If the same class is missed on a second case, stop writing lines: make it a script or a lint rule.
5. Every few rounds, run the whole set blind and record it.
