# Learning from review threads on GitHub

The retro needs the outside findings of a round. When they are review threads on open pull requests, three small tools get them into a form the retro and the eval can use. Node 18+ is the only requirement; the rest of review-loop is bash and git.

```
where GitHub is reachable                 anywhere (offline)
fetch-threads.mjs  ->  threads.jsonl  ->  threads.mjs ingest  ->  ledger
                                           threads.mjs worksheet -> retro
                                           threads.mjs verdict   -> (a decision per thread)
                                           threads.mjs cases     -> eval cases
```

With the command: `review-loop threads fetch|ingest|list|verdict|worksheet|cases`.

## 1. Fetch (a machine that can reach GitHub)

    node fetch-threads.mjs --repo owner/name [--author login] [--out threads.jsonl] [--all-threads]

- `--repo` is required; there is no default repository, organisation or author.
- The token is `GH_TOKEN` or `GITHUB_TOKEN`, else the one git holds for github.com (`git credential fill`). No `gh` CLI is needed.
- Behind a proxy set `HTTPS_PROXY` (and `NO_PROXY`). Node's built-in fetch ignores proxy settings, so the script tunnels through an HTTP proxy itself with `CONNECT`. A system-wide proxy that is not in the environment is not read: copy it into `HTTPS_PROXY`.
- Default: unresolved and outdated threads of open pull requests. `--all-threads` adds resolved ones.
- Progress goes to stderr: the repository, the proxy in use (host and port only), where the token came from, then one line per pull request (`[3/12] #898 branch: 5 thread(s)`, and how many were kept) and the elapsed time. `--quiet` turns it off. A request that gets no answer for 30 seconds fails with a message that names the route it used (the proxy, or a direct connection), so a blocked connection does not just hang.
- Not tested against the live API (only against a recorded response with `--response-file`, which is also how to try the converter without a network). The first live run is the test; the GraphQL query is the `reviewThreads` query from the exporter this replaces.

### The export (`threads.jsonl`, one JSON object per line)

| Field | Meaning |
|---|---|
| `repo`, `pr`, `pr_title`, `pr_author`, `branch`, `base_ref` | where the thread is |
| `head_sha`, `base_sha` | the pull request's head and base at fetch time |
| `thread_id` | GitHub's id, the key of the ledger |
| `status` | `open`, `outdated` (the code moved) or `resolved` |
| `path`, `line`, `start_line` | where the comment is |
| `commit_reviewed` | the commit the first comment was written on: the code the reviewer saw |
| `author`, `created_at`, `body` | the first comment |
| `comments` | every comment of the thread (`id`, `author`, `body`, `created_at`, `commit`) |

## 2. The ledger

`threads.mjs ingest threads.jsonl` adds the threads it has not seen, updates the status of known ones, and marks threads that are no longer exported. Pass `--full` when the export is the complete set of open threads (the default fetch): everything missing from it is then marked gone at once; without it a thread first seen today is kept. The ledger is `$THREADS_LEDGER`, `--ledger`, or `$REVIEWS_DIR/threads-ledger.json`. Each thread has a verdict:

| Verdict | Meaning |
|---|---|
| `new` | not decided yet |
| `fixed` | confirmed in the code and fixed (record the fixing commit with `--commit`) |
| `rejected` | the outside comment was wrong or does not apply (say why with `--note`) |
| `caught` | the self-review had already reported it |
| `missed` | real, and the self-review did not report it |
| `deferred` | real, decided not now |

`threads.mjs verdict <piece of the id> <verdict> [--commit sha] [--note text]` records one. Because the ledger remembers, a later export shows only what is new, and a round does not start from 100 undecided threads.

## 3. The worksheet and the cases

- `threads.mjs import-md <export.md>` reads the older markdown export (the one with ` [--reports reviews]` lists the undecided and missed threads. Each row shows a self-review report entry within 15 lines of the comment, if there is one: a hint that it was caught, never a verdict. Human comments are marked: they usually carry design-level points.
- `threads.mjs cases --evals <dir> [--prefix p] [--group g] [--repo-dir d] [--tag]` writes an eval case for every pull request and reviewed commit that has threads with the verdict `fixed`: the tip is the commit reviewed, the base is the merge base with the pull request's base. Threads with the verdict `rejected` become comments in the case, never findings. Commits that are not in the repository are skipped with a message. `--tag` tags each tip `eval/<id>` so a history rewrite cannot take it. Only verified threads become findings: that is the rule that keeps a wrong comment from entering the eval.

## What goes where

The export, the ledger and the cases hold review comments and code from the repository. Keep them with the repository's private notes. This tool and its scripts hold none of it.
