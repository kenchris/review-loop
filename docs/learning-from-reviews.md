# Learning from outside review

This is the optional fourth level of review-loop. Use it once you get review comments from someone else (a teammate, Copilot, a maintainer) and want fewer of them next time.

## What problem it solves

You review your change, then someone else reviews it and finds more. You fix those, and the next change gets the same kind of comment. The fixes never turn into anything that stops the next miss.

This level does three things:

1. **Collects** the outside comments (GitHub review threads) in one place, so none is lost or handled twice.
2. **Records your decision** on each thread: fixed, wrong, not now. That record is the useful part: it says which outside findings were real.
3. **Asks `/retro`** what the cheapest check would have been to catch each real miss. The answer is usually a one-line search rule in `REVIEW.sweeps`, sometimes a line in `REVIEW.md`, and sometimes "delete this line, it never helped". Nothing is changed until you agree.

It pays off after a few rounds. With one or two comments there is nothing to learn from yet.

## The loop in one picture

    GitHub review threads
          |  threads sync            (download + record)
          v
    ledger: one row per thread, "undecided"
          |  threads worksheet       (what is undecided, with your own report next to it)
          |  threads verdict ...     (you decide each one)
          v
    ledger: fixed / rejected / deferred ...
          |  /retro round N          (in the agent)
          v
    proposals: "add this sweep", "add this line", "delete that line"
          |  you say which to apply
          v
    the next review catches that class

## Step by step

### 0. What you need

- `node` 18 or newer (the only extra requirement).
- A token that can read the repository's pull requests: set `GH_TOKEN` (or `GITHUB_TOKEN`), or be signed in to git for github.com. The `gh` CLI is not needed.
- Behind a proxy: set `HTTPS_PROXY` (and `NO_PROXY`). The fetch tunnels through it itself; a system-wide proxy that is not in the environment is not read.

### 1. Get the threads

If this machine can reach GitHub:

    review-loop threads sync --repo owner/name

It downloads the unresolved and outdated threads of your open pull requests and records them. Add `--author login` to keep only the pull requests of one author, `--all-threads` to include resolved ones, `--quiet` to silence the progress lines. Running it again only adds what is new.

If the machine you work on cannot reach GitHub, do it in two parts. On a machine that can:

    review-loop threads fetch --repo owner/name --out threads.jsonl

Copy `threads.jsonl` over, then where the work is:

    review-loop threads ingest threads.jsonl --full

(`--full` says the export is the complete set of open threads, so anything missing from it is marked gone.) That split is the only difference between `sync` and `fetch` plus `ingest`.

### 2. See what is undecided

    review-loop threads worksheet

One row per undecided thread: the pull request, file and line, what the reviewer said, and, if one exists, the entry of your own review report that sits near that spot. That entry is a hint that you had already seen the problem; it is never a verdict. `review-loop threads list` shows the whole ledger, and `--verdict`, `--pr` and `--status` filter it.

### 3. Decide each thread (the verdict)

A verdict is your decision about one thread, saved so it is never asked twice. Refer to a thread by the first characters of its id, as the worksheet shows it.

    review-loop threads verdict <id> fixed --commit <sha>
    review-loop threads verdict <id> rejected --note "the kind is read as a string first"
    review-loop threads verdict <id> deferred

| Verdict | Use it when | What happens with it |
|---|---|---|
| `fixed` | the comment was right and you fixed it (give the fixing commit) | the normal case for a real finding; `/retro` compares it with your own report to see whether you missed it; it can become an eval case |
| `rejected` | the comment was wrong or does not apply | remembered with your reason, so it is not fixed twice; counts as reviewer noise |
| `caught` | your own review had already reported it | not a miss, so nothing to learn |
| `missed` | real, and your review did not report it | a miss to learn from, when you did not fix it right away |
| `deferred` | real, but not now | stays on the list, out of the undecided ones |
| `new` | not decided yet | what every thread starts as |

Be honest with `rejected`: a thread you reject without a reason teaches nothing. And decide the whole round before running `/retro`; it learns from the decisions, not from the raw comments.

### 4. Run the retro (in the agent)

    /retro round 26

Replace `26` with whatever names the round (or give PR numbers, or the path of a findings file). `/retro` takes the real findings, sorts the misses by cause (a sweep could have found it, a lens covered it but was skipped, no guidance existed, the test did not reach it), and proposes the cheapest change for each, ranked by how many misses it would have caught. It does not change anything until you tell it which to apply (`--apply` after you agree). You start it yourself, because it spends allowance and proposes changes to your review setup.

### 5. Optional: measure the reviewer

    review-loop threads cases --evals evals --repo-dir . --tag

turns the threads you marked `fixed` into eval cases: a commit range and the finding it should contain. Then in the agent `/review-eval` replays the reviewer on those cases and records how many it finds (recall) and how many extra claims were wrong (noise). Use it to check that a change to the review setup helped. It costs allowance and you start it yourself. See [`skills/review-eval/SKILL.md`](../skills/review-eval/SKILL.md).

## Where things are kept

- The **ledger** is `reviews/threads-ledger.json` in your repository, or the file named by `THREADS_LEDGER` or `--ledger`. It has one entry per thread.
- The ledger, exports and eval cases contain review comments and code from your repository. Keep them with your repository's private notes. review-loop's own scripts hold none of it.

## When something goes wrong

- **A timeout or `connect ETIMEOUT`.** You are behind a proxy that is not in `HTTPS_PROXY`. Set it (the fetch prints the proxy it uses, host and port only) and run again.
- **Authentication error.** No token found: set `GH_TOKEN`, or sign in to git for github.com. The fetch prints where the token came from.
- **Nothing new.** Expected on a second run; only unseen threads are added.
- **No `node`.** Only the `threads` commands need it; everything else is bash and git.

The fetch has been tested against a recorded response and against a proxy, and has been run once live. Treat the first runs on your repository as the real test.

For the exact fields of the export and the ledger, see [`skills/retro/references/threads.md`](../skills/retro/references/threads.md).
