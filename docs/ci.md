# review-loop in CI (GitHub Actions)

What can run in CI, and what cannot.

**Runs in CI: the scripts.** `review-loop sweeps`, `review-loop gate` and `review-loop threads fetch` are plain scripts. They make no model call, need no API key and no allowance, and need only bash and git (node for `threads`). So they are safe to run on every pull request.

**Does not run in CI: the skills.** `/pre-pr-review`, `/retro` and `/review-eval` need an agent and its allowance, and `retro` and `review-eval` are meant to be started by a person. Run them where you work and commit what they produce (a report in `reviews/`); CI then checks that the report is there.

## 1. The sweeps, as warnings on the changed lines

`DIFF_SWEEPS_FORMAT=github` makes `diff-sweeps.sh` print GitHub workflow commands (`::warning file=...,line=...::...`) instead of the text report, so each hit shows on the changed line of the pull request. A hit is a question for the author, not a verdict: the step stays green. GitHub limits how many annotations a step shows (about ten of each kind), and the high-priority sweeps (names starting with `!`) are printed first, so what matters most is what is shown.

`DIFF_SWEEPS_STRICT=1` fails the step on any hit. Do not start there: the ordinary sweeps are noisy by design. If you want a hard check, put the sweeps you trust in a `REVIEW.sweeps` of their own and run those strictly.

## 2. The gate, as a required check

`review-loop gate <base> <head>` fails unless saved review reports with `Open: 0` cover every commit of `<base>..<head>`, and any required line (`REVIEW.gate`: for example `Casing` for an API surface, `Spec` for code that implements a specification) is stated. It checks that a review was written, not that it was good. Use it as a required status check (branch protection) only if your team commits the reports to the repository, and know that reports name commit ids: a rebase that changes the ids needs a report for the new range.

## 3. The threads of a round, on a schedule (optional)

`fetch-threads.mjs` reads `GH_TOKEN`, so a scheduled workflow can export the review threads and upload them as an artifact, which you then ingest where the ledger lives. The token of a workflow can read the pull requests of its own repository. The export contains review comments and code snippets: keep the artifact private.

## A workflow

See [`examples/github-actions/review-loop.yml`](../examples/github-actions/review-loop.yml). It is a sketch: it has not been run on GitHub from where it was written. Read it, pin the review-loop tag, and try it on a branch first.

Notes that matter:

- `actions/checkout` needs `fetch-depth: 0`, so the base and the head are both there.
- Use the pull request's head commit (`github.event.pull_request.head.sha`), not the merge commit, as `<head>`.
- Pin review-loop to a tag (the example uses `v0.6.0`). Do not run an unpinned clone in a check that can fail a pull request.
- Anything specific to your code (sweeps, required lines, the specs you implement) lives in your repository: `REVIEW.sweeps`, `REVIEW.gate`, `REVIEW.md`. `review-loop` finds them at the repository root.
