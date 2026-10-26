# REVIEW.md

Read by the review skills before they look at a change. Keep it short: a reviewer that has to read a long file reads it badly.

## What a failure is here

- The docs must not say something the code does not do.
- A config value must not silently route to a different behaviour.
- (One line per thing that would make this project wrong, not merely untidy.)

## Guards: read these in full and attack them

- `src/auth/` (every route that checks a token)
- `installer/` (runs with elevated rights)
- (Each path where a check protects a resource. For each, name the other doors to the same resource: redirects, retries, the second backend, a nested or scripted caller.)

## Specs we implement

A plan is not a spec. List only external specifications the code must conform to. When you are handed a spec to implement, add or refresh its entry as part of the work, so the next review knows it.

- **Name and version:** ExampleProtocol 2025-06-18. For a stable spec pin a version or a date. For one that is still emerging write `latest`: the code follows the newest revision, so a review checks against it.
- **Text:** `docs/specs/example-protocol-2025-06-18.md` (a local copy) or a URL. With `latest`, give the URL where the newest revision is published; the reviewer fetches it at review time, and the report states the revision and date it read. A local copy of a moving spec goes stale and must not be used for `latest`.
- **Implemented by:** `src/protocol/session.cpp` (sections 3 and 4), `src/protocol/auth.cpp` (section 5)
- **Deliberately not implemented:** (parts the spec has deprecated, or that are out of scope for this repo: a review does not report their absence, and does report code that adds one back)
- **Not yet implemented:** (known gaps with a plan; a review does not report these again, but keep the list short and current: a stale list hides real findings)

## Ignore

- `third_party/`, generated files, lock files, `dist/`.

## Conventions a change must follow

- API keys and error codes are `snake_case`; enum values are hyphenated.
- (Anything a lint cannot check yet.)

## Extra sweeps for this repo

- `grep -n "old_helper(" -r src/`: the old helper is being removed; every hit is a finding.

## Finding classes raised here before

One line each: the pattern, an example, how to spot it. Add a line whenever a reviewer finds something this review did not.

- A damaged file read as a missing one (session store).
