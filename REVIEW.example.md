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
