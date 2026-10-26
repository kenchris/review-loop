# review-loop

Claude Code skills for the review loop: check a change before it goes out, measure how well the check works, and turn recurring findings into checks that run.

| Skill | What it does |
|---|---|
| `pre-pr-review` | Reviews a branch or range through a fixed set of lenses and mechanical sweeps, verifies every finding before reporting it, and writes a report. Single pass for a small change, multi-pass (up to three readers) before handing something over, plus a spec-conformance reader when the change implements an external specification listed in `REVIEW.md`. |
| `review-eval` | Keeps verified past findings as test cases, runs the reviewer blind on them, and records recall and noise, so a change to the lenses is kept only if it measurably helped. You invoke it yourself (`disable-model-invocation`): it spawns readers and costs allowance. |
| `retro` | After a round of outside review, works out why each miss happened and proposes changes to the review setup, ranked by severity: a sweep or lint rule for what is mechanical, a `REVIEW.md` line only for judgement calls, deletion of lines that change nothing. You invoke it yourself; it proposes before it changes anything. |

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

Needs bash and git (written to avoid bash 4 features, tested on bash 5 only); on Windows use Git Bash (the installer adds a `review-loop.cmd` for cmd.exe and PowerShell). `./install.sh --uninstall` removes what it installed.

## Use

In a repository:

    review-loop init           # REVIEW.md, REVIEW.sweeps, reviews/ and a config file; never overwrites
    review-loop doctor         # tools, skills and this repository's setup
    review-loop sweeps <base> <tip>
    review-loop gate <base> <ref>
    review-loop score add <round> <change> <found> <outside-new> <rejected>
    review-loop eval case new <id> <base> <tip> | blind <id> <dest> | record ... | report

Then ask for a review of a branch, a PR or a range from the agent: `/pre-pr-review feature-branch` (add `multipass` before a hand-over). The command and the skills use the same scripts; a repository can keep its review files elsewhere through `.review-loop.env` (see `review-loop help`).

## VS Code

- **Skills.** VS Code reads [agent skills](https://code.visualstudio.com/docs/agent-customization/agent-skills) from `~/.claude/skills`, `~/.copilot/skills`, `~/.agents/skills`, and from `.claude/skills`, `.github/skills` and `.agents/skills` in the workspace. The default install therefore works in VS Code (Copilot agent mode, and the Claude Code extension, which uses the same folder); `--for copilot` is for a setup without a `.claude` folder, and `chat.agentSkillsLocations` can point VS Code at another folder. Skill names match their folder names, as VS Code requires.
- **Tasks.** `review-loop init --vscode` writes `.vscode/tasks.json` (or `.vscode/review-loop.tasks.json` to merge by hand, if you have one). Terminal > Run Task offers sweeps, gate, score, eval report and doctor, and asks for the base and tip refs. The sweep hits are reported to the Problems panel as warnings on the added lines, so they show in the editor.
- The command must be on the PATH of VS Code's terminal (`~/.local/bin` is not on it by default on Windows).

## Per-repo knowledge: `REVIEW.md`

The skills carry the method. What your repo specifically needs a reviewer to know goes in a `REVIEW.md` at its root, which the skills read first: what counts as a failure here, the paths that guard something (auth, installers, sandboxes, billing), paths to ignore, naming and API conventions, extra sweeps, and the finding classes your reviewers have raised before. [REVIEW.example.md](REVIEW.example.md) shows the shape. Keep it short.

## License

Apache-2.0, see [LICENSE](LICENSE).

## Tests

    bash tests/run.sh

Scratch repositories and a scratch `HOME` only; nothing outside the temp directory is touched. It covers the gate, the sweeps, the score log, the eval scripts, the installer and the command, and checks that every lens and sweep is assigned to a reader in the multipass table.
