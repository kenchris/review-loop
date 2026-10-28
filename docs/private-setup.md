# Trying review-loop without adding files to a project

Use this when one or two developers want to try review-loop on a project before the team has agreed to it, or when the project does not want review files in its tree. Nothing is added to the project. Everything review-loop reads or writes besides the code lives in a separate folder, which can be its own private repository.

This is the same set of files as in the normal setup, only somewhere else. Moving in later is a copy (see the end).

## What lives where

| File | Default place | Setting |
|---|---|---|
| `REVIEW.md` (what failure means here, guards, what to ignore) | `<root>/REVIEW.md` | `REVIEW_FILE` |
| `REVIEW.sweeps` (your own search rules) | `<root>/REVIEW.sweeps` | `REVIEW_SWEEPS` |
| `REVIEW.gate` (guard paths, required report lines) | `<root>/REVIEW.gate` | `REVIEW_GATE_FILE` |
| Review reports, `score.tsv`, the threads ledger | `<root>/reviews/` | `REVIEWS_DIR` (ledger: `THREADS_LEDGER`) |
| Eval cases and runs | `<root>/evals/` | `EVALS_DIR` |

The skills themselves are installed in your user folder (`~/.claude/skills`), not in the project, unless you installed them with `--project`.

## Set up

1. **A private place.** For example a repository `review-loop-private` with one folder per project: `review-loop-private/neon-smash/`.

2. **The starting files.** Do not run `review-loop init` inside the project: it creates the files in the project root. Create them in the private folder instead:

        mkdir -p review-loop-private/neon-smash/reviews
        cp <review-loop checkout>/REVIEW.example.md review-loop-private/neon-smash/REVIEW.md
        touch review-loop-private/neon-smash/REVIEW.sweeps

   Edit `REVIEW.md` a little, as in the normal setup.

3. **A settings file** in the same folder, `config.env`. It is a file of shell variable assignments, so `$HOME` works. Use absolute paths: a relative one is relative to wherever you run the command.

        REVIEW_FILE=$HOME/review-loop-private/neon-smash/REVIEW.md
        REVIEW_SWEEPS=$HOME/review-loop-private/neon-smash/REVIEW.sweeps
        REVIEWS_DIR=$HOME/review-loop-private/neon-smash/reviews
        EVALS_DIR=$HOME/review-loop-private/neon-smash/evals

4. **Point review-loop at it.** In the terminal you work in (and the one you start the agent from, so the agent inherits it):

        export REVIEW_LOOP_CONFIG=$HOME/review-loop-private/neon-smash/config.env

   With several projects, a small function picks the folder by project name:

        rl() { REVIEW_LOOP_CONFIG="$HOME/review-loop-private/$(basename "$(git rev-parse --show-toplevel)")/config.env" review-loop "$@"; }

   Instead of the environment variable you can put a `.review-loop.env` at the project root. That is a file in the project, so keep it out of commits with a line in `.git/info/exclude` (local to your clone, never committed).

5. **Check.**

        review-loop doctor            # REVIEW.md should be listed with the private path
        git status --short            # in the project: nothing

## What works the same

`review-loop sweeps`, `depth`, `gate`, `score`, `eval` and `threads` all follow these settings: the sweeps come from `REVIEW_SWEEPS`, the guard paths for `depth` and `gate` from `REVIEW_GATE_FILE`, reports and the threads ledger from `REVIEWS_DIR`, eval cases from `EVALS_DIR`. A real run: on a clean clone of a small game with the files in a separate folder, a sweep defined only in the private `REVIEW.sweeps` fired on the added lines, and `git status` in the project stayed empty.

## What to know

- **The reviewer finds `REVIEW.md` through `review-loop doctor`.** The scripts honour `REVIEW_FILE` themselves. The `/pre-pr-review` skill tells the agent to run `review-loop doctor`, which prints the path in use. That works only if the agent was started from a terminal where `REVIEW_LOOP_CONFIG` is set (step 4). If it was not, say where the file is in the request ("REVIEW.md is at `~/review-loop-private/neon-smash/REVIEW.md`").
- **CI and the gate.** CI cannot read files that are not in the repository, so it cannot run the sweeps or the gate from them. `review-loop gate` still works on your machine, against the private reports.
- **Nothing is shared.** Teammates review with their own settings, and a review report for a hand-over stays in the private folder; the pull request does not carry it.
- **This setup is not tested in CI.** It was run by hand on Windows with Git Bash.

## Moving in later

When the team says yes, copy the files to the project root and stop pointing at the private folder:

    cp review-loop-private/neon-smash/REVIEW.md  neon-smash/
    cp review-loop-private/neon-smash/REVIEW.sweeps neon-smash/
    cp -r review-loop-private/neon-smash/reviews  neon-smash/
    unset REVIEW_LOOP_CONFIG

The root is the default place for all of them, so nothing else changes. Then go on with level 3 of the [README](../README.md): commit a report and make the gate a rule.
