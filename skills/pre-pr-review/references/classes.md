# Finding classes that recur

Each class: the pattern, an example, how to spot it. These are generic; a repo's own list belongs in its `REVIEW.md`. When a class has been found twice, make it a script or a lint rule.

## One rule, several doors

A rule fixed in one route and not in its siblings: a name normalised in the registry but not in the client route, a limit applied to the top-level run but not the nested one, a policy read by exact name in one place and by alias in another. A scope check that treats "empty" as "everything" on a path that forgot to pass the scope.
*Spot it:* after any change to a lookup, normalisation or limit, search for the OLD form across every file and give each hit the rule. List the other paths that reach the protected thing.

## State captured at one time, used at another

A snapshot copied under a lock and used after a reset; a flag read before an await and acted on after it; a value validated at parse time and re-read from disk later; a decision made at creation that the world no longer matches at run time; an async result installed after a newer navigation.
*Spot it:* for each check, ask what can change before the use. For each async call, ask what a newer call does to its result (a generation counter).

## Missing is not unreadable

A damaged, locked or oversized file treated as "does not exist", so the next write replaces it; a failed read returned as empty or null; an error logged and then ignored; a `true` returned after a write failed.
*Spot it:* every read helper: does the caller distinguish absent from failed? Every write: is the result used before anything is deleted?

## Typed access to data you do not own

A typed getter or default-returning accessor on JSON from a client or a file throws on the wrong type; an `is_integer` check without a range check; unsigned values above the signed maximum; `+ 1` on a stored counter; a type that is a scalar where an object was expected.
*Spot it:* search for the getters over every input boundary; each must survive a missing key, the wrong type and an empty value, and the wrong type is an error, not an absent value.

## Boundaries and handles in C-level code

A handle used before its result is checked; a handle closed on the happy path only; a pipe or file inherited by a second child; a name resolved twice (once by the check, once by the user of the answer); a path checked and then opened by name.
*Spot it:* for every open or spawn, follow the handle to every exit path. For every check-then-use on a name, ask what the second resolution can return.

## Duplicated helpers without bounds

A second copy of a helper (a reader, a parser, a path join) that lacks the first copy's size limit or control-character check.
*Spot it:* search for a second implementation of anything that already has a shared one, and for "read the whole file" calls with no cap.

## A claim larger than the change

A comment, commit message or description that says "every route", "never" or "all backends" for a change that covers some. Docs that still describe the old model. A limit stated as "not done yet" that something already does.
*Spot it:* for each quantifier in new text, list what it covers and check each.

## Tests that cannot fail

A test that would pass with the fix reverted; a fixed temp path shared by parallel jobs; a skip that means the code never ran; an assertion about a helper's own output instead of the behaviour; appended tests merged without their closing brace.
*Spot it:* revert the fix in your head: does the test fail? Search tests for fixed temp names.

## UI and lifecycle (web front ends)

A listener added without its removal; a promise used as a value; state reset in one place and not its partner on reload or switch; DOM edited outside the framework's state; a "seen" flag resurrected by a replay; an MV3-style call that returns a promise but is neither awaited nor caught.
*Spot it:* for every added listener or subscription, find the matching teardown.

## Merge hygiene

Conflict markers, a stray closing brace or namespace, a test merged without its end, a file written to the wrong worktree, a cascade that silently skipped a branch because it was checked out elsewhere.
*Spot it:* after any rebase or cascade, scan every branch for markers, build it, and compare trees before and after.

## What a cheap reader still finds in a fix commit

A fix that is larger in the description than in the code; a new guard that does not cover the old route; a fix to a symptom on one path; a caller that ignores the new failure result.
*Spot it:* review a fix commit as new code, and ask what the fix does not cover.

## An existing function the new code now depends on

New code calls a function that was already there, and relies on its success: it returns true, it reports missing and damaged alike, it ignores the result of its own write. The defect is in code the change did not add, so a search over added lines cannot see it, and an outside reviewer reports it against the new caller.
*Spot it:* for every existing function the diff starts to call, read it once for its failure paths: what does it return when a read, a parse or a write inside it failed? A "pre-existing" label is a reason to mark the finding Pre-existing, not to skip it.
