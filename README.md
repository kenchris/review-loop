# review-loop

Skills for coding agents, for the review loop: check a change before it goes out, measure how well the check works, and turn recurring findings into checks that run. They are plain `SKILL.md` skills, so they work wherever an agent loads that format: Claude Code, VS Code (GitHub Copilot's agent mode and the Claude Code extension), and other agents that read skills from a folder. The scripts need only bash and git, so they also run on their own, from a terminal or an editor task.

| Skill | What it does |
|---|---|
| `pre-pr-review` | Reviews a branch or range through a fixed set of lenses and mechanical sweeps, verifies every finding before reporting it, and writes a report. Single pass for a small change, multi-pass (up to three readers) before handing something over, plus a spec-conformance reader when the change implements an external specification listed in `REVIEW.md`. |
| `review-eval` | Keeps verified past findings as test cases, runs the reviewer blind on them, and records recall and noise, so a change to the lenses is kept only if it measurably helped. You invoke it yourself (`disable-model-invocation`): it spawns readers and costs allowance. |
| `retro` | After a round of outside review, works out why each miss happened and proposes changes to the review setup, ranked by severity: a sweep or lint rule for what is mechanical, a `REVIEW.md` line only for judgement calls, deletion of lines that change nothing. You invoke it yourself; it proposes before it changes anything. |
| `triage` | After `review-loop threads sync`, reads every undecided review thread (from Copilot, CI bots or people) against the code, proposes a verdict for each with the evidence, and records the ones you confirm in a single call: one confirmation for a round instead of one command per thread. You invoke it yourself; it never posts to GitHub or changes code. |

More are planned, see [PLAN.md](PLAN.md).

## What a good review loop has, and where it lives here

| Piece | Where |
|---|---|
| Verify before asking for review: show a runnable result, review the diff with a fresh reader | `pre-pr-review`, sections 2 and 4 (read whole functions, confirm each finding in code) |
| A per-repo file that says what failure means, what to ignore and what to require | `REVIEW.md` ([example](REVIEW.example.md)) |
| Several reviewers in parallel, a vote on each finding, style filtered out, severity marked | `pre-pr-review` multipass (`references/multipass.md`) |
| Every finding fixed or closed with a reason; nothing merges with an open one | `scripts/review-gate.sh` |
| Fix what the reviewer keeps flagging at the source: a lint rule, a sweep, a doc line | `scripts/diff-sweeps.sh`, `REVIEW.sweeps`, "Keep it learning" |
| A review that converges: capped cycles, re-review the diff only, fix the class | `pre-pr-review` section 1 and multipass section 6 |
| Past incidents and findings are the eval; every change to the reviewer is rescored; noise is measured | `review-eval`, `scripts/review-score.sh` |
| After each round, turn what the reviewers found into a check, a pointer or a deletion, ranked by what it would have caught | `retro` |
| Risk decides how much review a change gets | not yet (planned) |
| Explainers, so reading diffs is not the only way to learn the code | not yet (`explain-slice`, planned) |

## Install

    git clone <this repository> && cd review-loop
    ./install.sh              # skills into ~/.claude/skills, the `review-loop` command into ~/.local/bin
    ./install.sh --link       # the same, but linked to this checkout, so git pull updates them
    ./install.sh --for all    # also ~/.copilot/skills
    ./install.sh --project .  # into a project's .claude/skills (and .github/skills with --for all), shared through its repository

Needs bash and git (written to avoid bash 4 features, tested on bash 5 only). `./install.sh --uninstall` removes what it installed.

**Windows (PowerShell or cmd):** run `.\install.cmd --for all --add-to-path` (keep the `.\`: another `install.cmd` on your PATH may win without it). Do not run `./install.sh` in PowerShell (Windows opens the file in an editor), and do not run `bash install.sh` when `bash` is WSL's: that installs into the Linux home. `install.cmd` finds the bash of Git for Windows through `git`, not through the PATH, and the `review-loop.cmd` it installs does the same, so `review-loop` works in PowerShell, cmd and VS Code's terminal. Git Bash users can run `./install.sh` as on Linux.

If the folder with the `review-loop` command (`~/.local/bin`) is not on your PATH, the installer says so and, in a terminal, offers to add it; `--add-to-path` does it without asking, `--no-path` never does. Open a new terminal afterwards. Check with `review-loop doctor`.

## Start here: four levels

You do not need all of this. Start at level 1 and stop whenever it is enough. Each level adds one thing; nothing at a higher level is needed for a lower one.

Two places to type. **The agent** is the chat in Claude Code or VS Code: lines starting with `/`. **A terminal** is a shell: lines starting with `review-loop`. A terminal command never calls a model; the agent can also run one for you if you ask.

### Level 1: ask for a review (one command, no setup)

After `install`, open your agent in any git repository, on a branch with changes, and type:

    /pre-pr-review

That reviews the current branch against its base and prints findings, each confirmed in the code. Variations:

    /pre-pr-review 123                  a pull request number
    /pre-pr-review main..my-branch      a range
    /pre-pr-review multipass            three independent readers and a vote: use before handing over anything that is not small

Three readers cost about three times one. To see whether a change needs them, ask first (terminal, no model): `review-loop depth main HEAD` says `single` for documentation, tests and small code changes, and `multipass` for larger ones and always for a path you have marked as a guard (see `REVIEW.gate`).

That is the whole of level 1. Fix what it finds, run it again.

### Level 2: tell it about your repository (two minutes, once)

In a terminal, in the repository:

    review-loop init
    review-loop doctor

`init` creates `REVIEW.md` (what failure means here, what to ignore, what guards something), `REVIEW.sweeps` (your own search rules) and `reviews/` (saved reports). It never overwrites. Edit `REVIEW.md` a little: the reviewer reads it first. Add `--vscode` to also get editor tasks. To try this on a project without adding any file to it, keep these files in a separate folder: [docs/private-setup.md](docs/private-setup.md).

You can now also run the mechanical checks alone, without an agent and without cost:

    review-loop sweeps main HEAD        every added line run through the sweeps; each hit is a question

### Level 3: make "reviewed" a rule (for teams)

Save the multipass report (`/pre-pr-review multipass my-branch` writes it to `reviews/`), commit it, and check before a hand-over or merge:

    review-loop gate main HEAD          fails unless a report with Open: 0 covers every commit

This checks that a review was written, not that it was good. In CI see [docs/ci.md](docs/ci.md).

### Level 4: let the reviews you get make the next review better (optional)

Every outside comment on your pull requests is a check you did not have. This level turns them into one.

    review-loop threads sync --repo owner/name                 download your open review threads
    /triage                                                    in the agent: a proposed verdict for every thread, you confirm once
    /retro round 26                                            in the agent: what would have caught these?

To decide by hand instead: `review-loop threads worksheet` lists what is undecided and `review-loop threads verdict <id> fixed --commit <sha>` (or `rejected`, `deferred`) records one thread.

[What you get from it](#what-you-get-from-outside-review), and the [full walkthrough](docs/learning-from-reviews.md).

## What you get from outside review

Without this, the same thing happens every round: a reviewer finds things you missed, you fix them, and the next change gets the same kind of comment. If Copilot or CI review runs on every push, it happens on every push: you fix, you push, and the next round finds something else, which feels like a loop with no end. The aim of this level is fewer findings after each push. The fixes disappear into the pull request and nothing stops the next miss.

With it, each round leaves something behind:

- **A record, not a pile of comments.** Every thread is decided once (fixed, wrong, not now) and never asked twice. A round of a hundred threads does not start from a hundred undecided ones; it starts from what is new.
- **Misses turn into checks that run for free.** `/retro` asks, for each real miss, what the cheapest check would have been, and ranks the answers by how many misses each would have caught. Typically a one-line search rule that flags the pattern on every future change (no model, no allowance), a single line in `REVIEW.md` for a judgement call, or deleting a line that never helped. You choose which to apply.
- **You find out which checks pay.** Fixed findings can become test cases, so `/review-eval` can tell you whether a change to the review setup caught more or only added noise.
- **Wrong comments are remembered too.** A rejected thread keeps your reason, so the reviewer's noise is measured and not fixed twice.

A real round: nine Copilot comments on three pull requests, eight of them right. `/retro` sorted them by cause. Three were things the review lenses already covered but a reader skipped; one was a pattern a one-line search would have found (a pointer cast with no family check); one was a deleted test file nobody had noticed. It came back with a short ranked list of changes to the review setup, instead of nine fixes that teach the next review nothing.

It pays off after a few rounds; with one or two comments there is nothing to learn from yet. Start with `review-loop threads sync`.

**Full guide:** [docs/learning-from-reviews.md](docs/learning-from-reviews.md): setup, each command, what every verdict means, what `/retro` does with them, and what to do when the fetch fails. File formats: [skills/retro/references/threads.md](skills/retro/references/threads.md).

## Reference: every command

A repository can keep its review files elsewhere through `.review-loop.env` (see `review-loop help`); [docs/private-setup.md](docs/private-setup.md) shows how to try review-loop on a project without adding any file to it. The commands and the skills use the same scripts.

There are two kinds of thing to type, and they run in different places. **Slash commands** (`/pre-pr-review`, `/retro`, `/review-eval`) are typed to the agent: they start a skill, where the agent reads and reasons. **Terminal commands** (`review-loop ...`, `fetch-threads.bat`) are typed in a shell: they are plain scripts that make no model call, and the agent can run them for you if you ask ("run the gate for sched-7 to sched-9").

`/retro`, `/triage` and `/review-eval` are user-invoked only (they spend allowance, and `retro` proposes changes to the review setup and `triage` writes decisions to the ledger), so in Claude Code type the slash command; the agent will not start them on its own. Asking in plain words ("run a retro on round 26 from the ledger") also works if the agent is told to follow the skill, but the slash form is the reliable one.

| You want | Where | Type | What happens |
|---|---|---|---|
| A review of a change before it goes out | agent | `/pre-pr-review <branch, PR number or base..head>` | one pass through the lenses, sweeps and verification; a report |
| The same, before a hand-over | agent | `/pre-pr-review multipass <branch>` | up to three independent readers (a fourth for a spec), a vote, a report in `reviews/` |
| Whether a change needs one reader or three | terminal | `review-loop depth <base> <tip>` | `single` or `multipass`, the reason and a model; a guard path is always multipass; no model |
| The mechanical checks alone | terminal | `review-loop sweeps <base> <tip>` | the added lines run through the sweeps; each hit is a question; no model |
| To check a hand-over is covered | terminal | `review-loop gate <base> <ref>` | fails unless a report with `Open: 0` covers every commit (and any required line); not a slash command, and it does not review anything: it checks that a review was written |
| The threads of a round, and your decisions | terminal | `review-loop threads fetch / ingest / worksheet / verdict` | the export, the ledger and the worksheet (see below); no model |
| To decide a round's threads without one command each | agent | `/triage [PR numbers]` (after `threads sync`) | a proposed verdict per thread with the evidence; you confirm once; recorded with `review-loop threads verdict --batch`; nothing is posted or changed |
| To learn from a round of outside review | agent | `/retro round 26` (after the threads steps below) | ranked proposals for the review setup; nothing is changed until you agree (`--apply` after) |
| To measure the reviewer | agent | `/review-eval report`, `/review-eval run <case>` | recall and noise per run, from past findings as test cases |
| To record and read the scores | terminal | `review-loop score add ...`, `review-loop eval report` | the numbers only |

**A round of outside review, start to finish** (steps 1 to 3 and 5 are terminal commands; step 4 is the only slash command)

1. On a machine that can reach GitHub: `review-loop threads fetch --repo owner/name --out threads.jsonl` (progress and the proxy in use are printed; `HTTPS_PROXY` if needed).
2. On the machine you work on: `review-loop threads ingest threads.jsonl --full`, then `review-loop threads worksheet` for what is undecided, each with the nearest self-review report entry.
3. Decide each thread. In the agent, `/triage` proposes a verdict for every one with the evidence and records the ones you confirm. By hand: `review-loop threads verdict <id> fixed --commit <sha>` (or `rejected`, `caught`, `missed`, `deferred`).
4. In the agent: `/retro round 26`. It sorts the misses by cause, and proposes the cheapest change that would have caught each: a sweep, a pointer, a lens change, or a deletion. Read the list, say which to apply.
5. Optional: `review-loop threads cases --evals evals --repo-dir . --tag` turns the threads you verified and fixed into eval cases, and `/review-eval` rescoring shows whether a change helped.

Arguments: `/pre-pr-review [PR number | branch | base..head | stack] [multipass] [--fix]`, `/retro [round | PR numbers | path to the findings] [--apply]`, `/triage [PR numbers]`, `/review-eval [new-case | run <case> | report | diff <runA> <runB>]`.

## CI (GitHub Actions)

The scripts run in CI; the skills do not (they need an agent). `DIFF_SWEEPS_FORMAT=github` prints the sweep hits as warnings on the changed lines of a pull request, and `review-loop gate` can be a required check when reports are committed. See [docs/ci.md](docs/ci.md) and the sample workflow [examples/github-actions/review-loop.yml](examples/github-actions/review-loop.yml) (a sketch, not yet run on GitHub).

## VS Code

- **Skills.** VS Code reads [agent skills](https://code.visualstudio.com/docs/agent-customization/agent-skills) from `~/.claude/skills`, `~/.copilot/skills`, `~/.agents/skills`, and from `.claude/skills`, `.github/skills` and `.agents/skills` in the workspace. The default install therefore works in VS Code (Copilot agent mode, and the Claude Code extension, which uses the same folder); `--for copilot` is for a setup without a `.claude` folder, and `chat.agentSkillsLocations` can point VS Code at another folder. Skill names match their folder names, as VS Code requires.
- **Tasks.** `review-loop init --vscode` writes `.vscode/tasks.json` (or `.vscode/review-loop.tasks.json` to merge by hand, if you have one). Terminal > Run Task offers sweeps, gate, score, eval report and doctor, and asks for the base and tip refs. The sweep hits are reported to the Problems panel as warnings on the added lines, so they show in the editor.
- The command must be on the PATH of VS Code's terminal (`~/.local/bin` is not on it by default on Windows).

## Per-repo knowledge: `REVIEW.md`

The skills carry the method. What your repo specifically needs a reviewer to know goes in a `REVIEW.md` at its root, which the skills read first: what counts as a failure here, the paths that guard something (auth, installers, sandboxes, billing), paths to ignore, naming and API conventions, extra sweeps, and the finding classes your reviewers have raised before. [REVIEW.example.md](REVIEW.example.md) shows the shape. Keep it short.

## Background

- [Solving code review at Anthropic](https://claude.dev/blog/solving-code-review-at-anthropic/) (Addy Osmani, Morgan Westlee Lunt and Qing Wang, October 2026): how the Claude Code team reviews code that an agent mostly writes. Review in layers; verify before a pull request; an AI review on every pull request, with findings checked by other agents; a `REVIEW.md` that says what matters in each part of the code; past incidents kept as the test set the reviewer is scored against; a review that converges (capped rounds, re-review only the new diff). `review-loop` is a small, generic version of several of these pieces: the lenses and `REVIEW.md`, the multi-reader pass with a vote, verification before a finding is reported, the cycle cap, the eval, and `retro`. It does not cover the parts that belong to a hosting platform (merge queues, feature flags, staged rollout, risk-tiered approval).
- [Rewilding software engineering](https://medium.com/feenk/rewilding-software-engineering-900ca95ebc8c) (Tudor Gîrba and Simon Wardley, feenk, 2025; a book of six chapters, Creative Commons Share-Alike). Chapter 1 frames software engineering as decision making about systems too large to read in full: most of our time goes on reading, how we read is almost never discussed, and so it is never improved. [Chapter 3, Questions and answers](https://medium.com/feenk/rewilding-software-engineering-f758ec97ddb2) puts a number on it, the time to ask a question plus the time to answer it, and proposes moldable development for the case where no fitting tool exists: stop and build a small tool for the question, when the cost of building and using it, set against the speed gained, beats doing it by hand. The part we borrow is the direction of the sweeps and `retro`: a finding that keeps coming back becomes a small check written for this codebase (`REVIEW.sweeps`) that answers the question every time, not a longer list for a reader to remember, and `retro` asks for the cheapest such change first. [Chapter 4](https://medium.com/feenk/rewilding-software-engineering-a3601a066e50) argues that what makes a system understandable is that it can explain itself through the tools built for it, and that the useful role of an LLM is to help build those tools: which is how the sweeps and checks here are meant to be written.

## License

Apache-2.0, see [LICENSE](LICENSE).

## Tests

    bash tests/run.sh

Scratch repositories and a scratch `HOME` only; nothing outside the temp directory is touched. It covers the gate, the sweeps, the score log, the eval scripts, the installer and the command, and checks that every lens and sweep is assigned to a reader in the multipass table. It also lints the skills against the [Agent Skills specification](https://agentskills.io/specification): a valid name that matches the folder, a description of at most 1024 characters, a `SKILL.md` of at most 500 lines, and no named `references/` or `scripts/` file that is missing.

