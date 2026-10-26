#!/usr/bin/env bash
# Tests for the scripts and the command: bash tests/run.sh
# Each test makes a scratch repository (and a scratch HOME), so nothing outside the temp directory is touched.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
pp="$here/skills/pre-pr-review/scripts"
ev="$here/skills/review-eval/scripts"
rl="$here/bin/review-loop"
fails=0; passes=0

pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1"; }
# expect <name> <expected-exit> <command...>: the command's exit status, output kept in $out
expect() {
  local name="$1" want="$2"; shift 2
  out="$("$@" 2>&1)"; local got=$?
  if [ "$got" -eq "$want" ]; then pass; else fail "$name: exit $got, wanted $want. Output: $(printf '%s' "$out" | tail -3)"; fi
}
contains() { # contains <name> <text>   (in $out)
  case "$out" in *"$2"*) pass ;; *) fail "$1: output lacks '$2'. Output: $(printf '%s' "$out" | tail -3)" ;; esac
}

newrepo() {
  tmp="$(mktemp -d)"; cd "$tmp" || exit 1
  git init -q -b main; git config user.email t@example.com; git config user.name t
  git config core.autocrlf false
  echo base > a.txt; git add .; git commit -qm base
}

# --- review-gate.sh
newrepo; export REVIEWS_DIR="$tmp/reviews"; mkdir -p "$REVIEWS_DIR"
echo change >> a.txt; git commit -qam change
expect "gate: a bad base ref fails (was: passed)" 2 bash "$pp/review-gate.sh" nope HEAD
contains "gate: says which ref" "'nope'"
expect "gate: a bad tip ref fails" 2 bash "$pp/review-gate.sh" HEAD~1 nope
expect "gate: no report fails" 1 bash "$pp/review-gate.sh" HEAD~1 HEAD
printf 'Reviewed-range: %s..%s\nOpen: 0\n' "$(git rev-parse HEAD~1)" "$(git rev-parse HEAD)" > "$REVIEWS_DIR/r.md"
expect "gate: a covering report passes" 0 bash "$pp/review-gate.sh" HEAD~1 HEAD
printf 'Reviewed-range: %s..%s\nOpen: 2\n' "$(git rev-parse HEAD~1)" "$(git rev-parse HEAD)" > "$REVIEWS_DIR/r.md"
expect "gate: open findings fail" 1 bash "$pp/review-gate.sh" HEAD~1 HEAD
printf 'Reviewed-range: %s..%s\nOpen: 0\n' "$(git rev-parse HEAD~1)" "$(git rev-parse HEAD)" > "$REVIEWS_DIR/r.md"
REVIEW_REQUIRE_PATHS='^a\.txt$' REVIEW_REQUIRE_LINE=Casing expect "gate: a required line is missing" 1 bash "$pp/review-gate.sh" HEAD~1 HEAD
echo "Casing: checked" >> "$REVIEWS_DIR/r.md"
REVIEW_REQUIRE_PATHS='^a\.txt$' REVIEW_REQUIRE_LINE=Casing expect "gate: the required line is there" 0 bash "$pp/review-gate.sh" HEAD~1 HEAD
# several required lines from a REVIEW.gate file
printf 'Reviewed-range: %s..%s\nOpen: 0\nCasing: checked\n' "$(git rev-parse HEAD~1)" "$(git rev-parse HEAD)" > "$REVIEWS_DIR/r.md"
printf '# comment\nCasing ## ^a\\.txt$\nSpec ## ^a\\.txt$\n' > "$tmp/REVIEW.gate"
REVIEW_GATE_FILE="$tmp/REVIEW.gate" expect "gate: a second required line (Spec) is missing" 1 bash "$pp/review-gate.sh" HEAD~1 HEAD
contains "gate: names the missing line" "'Spec: checked'"
if printf '%s' "$out" | grep -q "'Casing: checked'"; then fail "gate: the Casing line is there and must not be reported"; else pass; fi
echo "Spec: n/a, nothing in this change implements a spec" >> "$REVIEWS_DIR/r.md"
REVIEW_GATE_FILE="$tmp/REVIEW.gate" expect "gate: both required lines present" 0 bash "$pp/review-gate.sh" HEAD~1 HEAD
printf 'Casing without a separator\n' > "$tmp/bad.gate"
REVIEW_GATE_FILE="$tmp/bad.gate" expect "gate: a malformed gate file is refused" 2 bash "$pp/review-gate.sh" HEAD~1 HEAD
printf 'Spec ## ^other/\n' > "$tmp/other.gate"
REVIEW_GATE_FILE="$tmp/other.gate" expect "gate: a required line only applies to its paths" 0 bash "$pp/review-gate.sh" HEAD~1 HEAD
REVIEW_WAIVE="because" expect "gate: a waiver passes" 0 bash "$pp/review-gate.sh" nope HEAD
unset REVIEWS_DIR

# --- diff-sweeps.sh
newrepo
printf 'int f(json j) { return 1; }\n' > a.cpp; git add .; git commit -qm one
printf 'std::string g(json j) { return j.value("x", std::string()); }\n' >> a.cpp; git commit -qam two
expect "sweeps: a bad ref fails (was: 0 questions)" 2 bash "$pp/diff-sweeps.sh" nope HEAD
expect "sweeps: finds a typed accessor on an added line" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
contains "sweeps: the hit is named" "a.cpp:2"
printf '<<<<<<< x\nfoo\n>>>>>>> y\n' > "with space.txt"; git add .; git commit -qm marker
expect "sweeps: a conflict marker in a file with a space in its name (was: missed)" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
contains "sweeps: the marker is found" "with space.txt"
# a normal sweep is capped, a high-priority one (name starting with !) is not and is listed first
for k in aa bb cc dd ee; do printf 'x = j["%s"].get<int>();\n' "$k" >> a.cpp; done
for k in aa bb cc dd ee; do printf 'y = j.value("%s", 0);\n' "$k" >> a.cpp; done
git commit -qam many
DIFF_SWEEPS_MAX=2 expect "sweeps: a normal sweep is capped" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
contains "sweeps: the rest of a capped sweep is counted" "... 5 hits"
if [ "$(printf '%s' "$out" | awk '/^\[json-default-accessor\]|^\[!json-default-accessor\]/{f=1;next} /^\[/{f=0} f && /a\.cpp:/' | wc -l | tr -d ' ')" = "5" ]; then pass; else fail "sweeps: a high-priority sweep shows all five hits even with DIFF_SWEEPS_MAX=2"; fi
contains "sweeps: a high-priority sweep is marked" "[!json-default-accessor]"
first="$(printf '%s' "$out" | grep -n '^\[' | head -1)"
case "$first" in *'[!'*) pass ;; *) fail "sweeps: high-priority sweeps come first (first header: $first)" ;; esac
DIFF_SWEEPS_MAX=0 expect "sweeps: 0 means no cap" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
if printf '%s' "$out" | grep -q "\.\.\. 5 hits"; then fail "sweeps: with no cap nothing is elided"; else pass; fi
git reset -q --hard HEAD~1
printf 'x = j.value("k", 0);\n' >> a.cpp; git commit -qam "github format"
DIFF_SWEEPS_FORMAT=github expect "sweeps: the github format prints a warning per hit on its file and line" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
contains "sweeps: a workflow command with file, line and title" "::warning file=a.cpp,line="
case "$out" in *"[!json-default-accessor]"*) fail "sweeps: the github format must not print the text report" ;; *) pass ;; esac
git reset -q --hard HEAD~1
DIFF_SWEEPS_STRICT=1 expect "sweeps: strict mode fails on a hit" 1 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
printf '%s\n' \
  'void h(json p) {' \
  '    std::string f = p.contains("focus") && p["focus"].is_string() ? p["focus"].get<std::string>() : std::string();' \
  '    WriteJsonFile(path, doc);' \
  '    for (const auto& x : p["items"]) use(x);' \
  '    bool ok = WriteJsonFile(path, doc);' \
  '}' >> a.cpp
git commit -qam "patterns for the cpp sweeps"
expect "sweeps: the new patterns run" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
contains "sweeps: a wrong type becoming the default is named" "wrong-type-becomes-default] "
contains "sweeps: a dropped write result is named" "ignored-write-result] "
contains "sweeps: a loop over a client member is named" "[loop-over-client-member]"
if printf '%s' "$out" | awk '/ignored-write-result\]/{f=1;next} /^\[/{f=0} f' | grep -q "WriteJsonFile"; then pass; else fail "sweeps: the dropped write is listed under ignored-write-result"; fi
if printf '%s' "$out" | awk '/ignored-write-result\]/{f=1;next} /^\[/{f=0} f' | grep -q "bool ok = WriteJsonFile"; then fail "sweeps: a write whose result is kept is not a hit"; else pass; fi
git reset -q --hard HEAD~1
printf 'one ## *.txt ## foo ## why\nbad line\n' > own.sweeps
expect "sweeps: an own sweep file, a malformed line is reported" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD own.sweeps
contains "sweeps: malformed line named" "not 'name ## globs ## regex ## why'"

# --- review-score.sh
newrepo; export REVIEWS_DIR="$tmp/reviews"
expect "score: add" 0 bash "$pp/review-score.sh" add 1 pr1 6 2 1
expect "score: a non-number is refused" 2 bash "$pp/review-score.sh" add 1 pr1 x 2 1
expect "score: show" 0 bash "$pp/review-score.sh" show
contains "score: recall 75%" "recall 75%"
unset REVIEWS_DIR

# --- eval scripts
newrepo; export EVALS_DIR="$tmp/evals"
echo two >> a.txt; git commit -qam two
expect "eval: new case" 0 bash "$ev/eval-case.sh" new c1 HEAD~1 HEAD "test"
expect "eval: the same id twice is refused" 2 bash "$ev/eval-case.sh" new c1 HEAD~1 HEAD
expect "eval: the tip must descend from the base" 2 bash "$ev/eval-case.sh" new c2 HEAD HEAD~1
printf 'F1 | a.txt:1 | state | one\nF2 | a.txt:2 | claim | two\n' >> "$EVALS_DIR/c1/case.md"
expect "eval: list" 0 bash "$ev/eval-case.sh" list
contains "eval: the example line is not counted, the two findings are" "2 findings"
expect "eval: record a finding" 0 bash "$ev/eval-record.sh" finding v1 c1 F1 found
expect "eval: a finding that is not in the case is refused" 2 bash "$ev/eval-record.sh" finding v1 c1 F9 found
expect "eval: record the other as missed" 0 bash "$ev/eval-record.sh" finding v1 c1 F2 missed
expect "eval: record an extra" 0 bash "$ev/eval-record.sh" extra v1 c1 rejected
expect "eval: report" 0 bash "$ev/eval-report.sh"
contains "eval: recall 50%" "recall 50%"
contains "eval: noise 50% (1 rejected of 2 reported)" "noise 50%"
printf '# R\n- keep this\n- drop this case:c1\n' > "$tmp/REVIEW.md"
REVIEW_FILE="$tmp/REVIEW.md" expect "eval: blind checkout" 0 bash "$ev/eval-blind.sh" c1 "$tmp/blind"
if [ -f "$tmp/blind/REVIEW.md" ] && grep -q "keep this" "$tmp/blind/REVIEW.md" && ! grep -q "drop this" "$tmp/blind/REVIEW.md" && [ ! -e "$tmp/blind/evals" ]; then pass; else fail "eval: the blind REVIEW.md keeps the other lines, drops the case's, and has no evals dir"; fi
git worktree remove --force "$tmp/blind" 2>/dev/null
# archive mode, and a group tag in a case
printf 'Groups: g1\n' >> "$EVALS_DIR/c1/case.md"
printf '# R\n- keep this\n- drop one case:c1\n- drop two case:g1\n- keep three case:c10\n' > "$tmp/REVIEW.md"
REVIEW_FILE="$tmp/REVIEW.md" expect "eval: archive blind export" 0 bash "$ev/eval-blind.sh" --archive c1 "$tmp/arch"
if [ -f "$tmp/arch/range.diff" ] && [ -f "$tmp/arch/changed-files.txt" ] && [ -f "$tmp/arch/_skill/SKILL.md" ] && [ -f "$tmp/arch/_sweep-hits.txt" ] && [ ! -e "$tmp/arch/.git" ] && [ ! -e "$tmp/arch/evals" ]; then pass; else fail "eval: an archive has the patch, the file list, the skill text and the sweep hits, and no history"; fi
if grep -q "keep this" "$tmp/arch/REVIEW.md" && grep -q "keep three" "$tmp/arch/REVIEW.md" && ! grep -q "drop one" "$tmp/arch/REVIEW.md" && ! grep -q "drop two" "$tmp/arch/REVIEW.md"; then pass; else fail "eval: case tags and group tags are dropped, a longer id that merely starts with the case id (c10) is kept"; fi
unset EVALS_DIR

# --- review threads: the fetcher (PowerShell, test mode) and threads.mjs (Node)
thr="$here/skills/retro/scripts"
if command -v node >/dev/null 2>&1; then
  newrepo
  A="$(git rev-parse HEAD)"; echo change >> a.txt; git commit -qam change; B="$(git rev-parse HEAD)"
  node_json() { # id resolved outdated path line author body commit
    printf '{"id":"%s","isResolved":%s,"isOutdated":%s,"path":"%s","line":%s,"originalLine":%s,"startLine":null,"originalStartLine":null,"comments":{"nodes":[{"databaseId":1,"body":"%s","author":{"login":"%s"},"createdAt":"2026-10-01T00:00:00Z","commit":{"oid":"%s"},"originalCommit":{"oid":"%s"},"replyTo":null}]}}' "$1" "$2" "$3" "$4" "$5" "$5" "$7" "$6" "$8" "$8"
  }
  {
    printf '{"pulls":[{"number":7,"title":"Seven","user":{"login":"alice"},"head":{"ref":"feat","sha":"%s"},"base":{"ref":"main","sha":"%s"}},' "$B" "$A"
    printf '{"number":8,"title":"Eight","user":{"login":"bob"},"head":{"ref":"other","sha":"%s"},"base":{"ref":"main","sha":"%s"}}],"threads":{' "$B" "$A"
    printf '"7":[%s,%s,%s],' "$(node_json T-open-1111 false false a.txt 1 copilot-pull-request-reviewer 'This throws on a wrong type. Check it first.' "$B")" \
      "$(node_json T-done-2222 true false a.txt 1 copilot-pull-request-reviewer 'Already resolved one.' "$B")" \
      "$(node_json T-human-3333 false true b.txt 40 riju 'Why is this guard missing on the other path?' "$B")"
    printf '"8":[%s]}}' "$(node_json T-bob-4444 false false c.txt 9 copilot-pull-request-reviewer 'Another one.' "$B")"
  } > "$tmp/response.json"
  expect "threads: the fetcher converts a response (test mode), one author" 0 node "$thr/fetch-threads.mjs" --repo o/r --author alice --response-file "$tmp/response.json" --out "$tmp/t1.jsonl"
  if [ "$(wc -l < "$tmp/t1.jsonl" | tr -d ' ')" = "2" ] && grep -q '"status":"outdated"' "$tmp/t1.jsonl" && grep -q "\"commit_reviewed\":\"$B\"" "$tmp/t1.jsonl"; then pass; else fail "threads: two threads for alice, resolved one left out, status and reviewed commit present"; fi
  expect "threads: --all-threads keeps resolved ones" 0 node "$thr/fetch-threads.mjs" --repo o/r --all-threads --response-file "$tmp/response.json" --out "$tmp/t2.jsonl"
  if [ "$(wc -l < "$tmp/t2.jsonl" | tr -d ' ')" = "4" ]; then pass; else fail "threads: all four threads with -AllThreads and no author filter"; fi
  expect "threads: --repo is required and validated" 2 node "$thr/fetch-threads.mjs" --repo nonsense --response-file "$tmp/response.json" --out "$tmp/x.jsonl"
  expect "threads: --repo missing" 2 node "$thr/fetch-threads.mjs" --out "$tmp/y.jsonl"
  expect "threads: the fetcher reports progress on stderr" 0 node "$thr/fetch-threads.mjs" --repo o/r --response-file "$tmp/response.json" --out "$tmp/p.jsonl"
  contains "threads: a progress line per pull request" "[1/2] #7 feat: 3 thread(s) on the pull request"
  contains "threads: and how many were kept" "kept 2"
  expect "threads: --quiet silences the progress" 0 node "$thr/fetch-threads.mjs" --repo o/r --response-file "$tmp/response.json" --out "$tmp/q.jsonl" --quiet
  case "$out" in *"[1/"*) fail "threads: --quiet still printed progress" ;; *) pass ;; esac
  out="$(timeout 60 node "$here/tests/fake-proxy-check.mjs" "$thr/fetch-threads.mjs" 2>&1)"
  contains "threads: the fetcher asks the proxy to CONNECT" "CONNECT api.github.com:443"
  contains "threads: and then talks TLS through the tunnel, not straight to GitHub (was: dialled GitHub directly)" "TLS HANDSHAKE THROUGH THE TUNNEL: yes"

  export THREADS_LEDGER="$tmp/ledger.json" REVIEWS_DIR="$tmp/reviews"; mkdir -p "$REVIEWS_DIR"
  # the older markdown export (Windows line endings) is read into the same records
  printf '| [#5](https://github.com/o/r/pull/5) | `feat` | `main` | `abc1234` ("base subject") | `def5678` | PASSED | +1 / -0 | Title five |\r\n\r\n### F1 - PR #5 - A title\r\n\r\n- **PR / branch:** feat (PR #5)\r\n- **Commit reviewed:** abc1234abc1234abc1234abc1234abc1234abc12\r\n- **File:** src/a.cpp\r\n- **Line(s):** 10-12\r\n- **Author:** copilot-pull-request-reviewer\r\n- **Status:** open\r\n- **Thread:** PRRT_abc123\r\n- **Comment (verbatim):**\r\n> First line of the comment.\r\n>\r\n> Second paragraph.\r\n- **Code at that location:**\r\n  ```cpp\r\n  int x;\r\n  ```\r\n' > "$tmp/export.md"
  expect "threads: import-md" 0 node "$thr/threads.mjs" import-md "$tmp/export.md" --out "$tmp/md.jsonl"
  if grep -q '"thread_id":"PRRT_abc123"' "$tmp/md.jsonl" && grep -q '"path":"src/a.cpp"' "$tmp/md.jsonl" && grep -q '"line":12' "$tmp/md.jsonl" && grep -q '"base_sha":"abc1234"' "$tmp/md.jsonl" && grep -q 'Second paragraph' "$tmp/md.jsonl" && grep -q '"repo":"o/r"' "$tmp/md.jsonl"; then pass; else fail "threads: import-md reads the thread id, path, last line, base from the table, the whole comment and the repo"; fi
  expect "threads: ingest" 0 node "$thr/threads.mjs" ingest "$tmp/t1.jsonl"
  contains "threads: two new threads" "2 new"
  expect "threads: ingesting the same export again adds nothing" 0 node "$thr/threads.mjs" ingest "$tmp/t1.jsonl"
  contains "threads: nothing new the second time" "0 new"
  grep 3333 "$tmp/t1.jsonl" > "$tmp/one.jsonl"
  expect "threads: --full marks threads missing from a complete export as gone" 0 node "$thr/threads.mjs" ingest "$tmp/one.jsonl" --full
  contains "threads: one thread is no longer exported" "1 no longer exported"
  expect "threads: it comes back when it is exported again" 0 node "$thr/threads.mjs" ingest "$tmp/t1.jsonl"
  printf '# Review of x\nReviewed-range: a..b\nOpen: 0\n\n## F1  a.txt:3  [state]  confirmed\n' > "$REVIEWS_DIR/r.md"
  expect "threads: worksheet" 0 node "$thr/threads.mjs" worksheet
  contains "threads: a human comment is marked" "(human)"
  contains "threads: a nearby report entry is a hint" "r.md F1"
  contains "threads: the other thread is a candidate miss" "1 have none"
  expect "threads: a verdict needs a known value" 2 node "$thr/threads.mjs" verdict 1111 maybe
  expect "threads: record a verdict by a piece of the id" 0 node "$thr/threads.mjs" verdict 1111 fixed --commit "$B" --note "done"
  expect "threads: an ambiguous or unknown id is refused" 2 node "$thr/threads.mjs" verdict nothing-like-it fixed
  expect "threads: list by verdict" 0 node "$thr/threads.mjs" list --verdict fixed
  contains "threads: one fixed thread listed" "1 thread(s)"
  expect "threads: cases from verified threads" 0 node "$thr/threads.mjs" cases --evals "$tmp/ev" --repo-dir "$tmp" --prefix t-
  case_dir="$(ls -d "$tmp"/ev/t-7-* 2>/dev/null | head -1)"
  if [ -n "$case_dir" ] && grep -q "^Range: $A\.\.$B$" "$case_dir/case.md" && grep -q '^F1 | a.txt:1 | ? | This throws on a wrong type.' "$case_dir/case.md" && ! grep -q "Already resolved" "$case_dir/case.md" && ! grep -q "b.txt" "$case_dir/case.md"; then pass; else fail "threads: a case with the range base..reviewed commit and only the verified finding (not the resolved one, not the undecided one)"; fi
  expect "threads: an existing case is not overwritten" 0 node "$thr/threads.mjs" cases --evals "$tmp/ev" --repo-dir "$tmp" --prefix t-
  contains "threads: the existing case is skipped" "exists"
  unset THREADS_LEDGER REVIEWS_DIR
else
  echo "skipping the threads tests: node is needed"
fi

# --- install.sh and the command
newrepo; home="$tmp/home"; mkdir -p "$home"
HOME="$home" expect "install: both targets, command" 0 bash "$here/install.sh" --for all
for d in .claude/skills .copilot/skills; do
  if [ -f "$home/$d/pre-pr-review/SKILL.md" ] && [ -f "$home/$d/review-eval/SKILL.md" ]; then pass; else fail "install: skills in $d"; fi
done
if [ -x "$home/.local/bin/review-loop" ]; then pass; else fail "install: the command is executable"; fi
expect "command: version" 0 env HOME="$home" bash "$home/.local/bin/review-loop" version
expect "command: init" 0 env HOME="$home" bash "$rl" init --vscode
for f in REVIEW.md REVIEW.sweeps REVIEW.gate .review-loop.env .vscode/tasks.json; do
  if [ -e "$tmp/$f" ]; then pass; else fail "init: created $f"; fi
done
echo mine > REVIEW.md
expect "command: init does not overwrite" 0 env HOME="$home" bash "$rl" init --vscode
if [ "$(cat REVIEW.md)" = "mine" ]; then pass; else fail "init: REVIEW.md was overwritten"; fi
if [ -e .vscode/review-loop.tasks.json ]; then pass; else fail "init: a second --vscode writes the tasks beside an existing tasks.json"; fi
expect "command: doctor" 0 env HOME="$home" bash "$rl" doctor
expect "command: help ends with the configuration, not code" 0 env HOME="$home" bash "$rl" help
case "$out" in *"set -u"*) fail "help: the output includes a line of code" ;; *) pass ;; esac
expect "command: an unknown command" 2 env HOME="$home" bash "$rl" nonsense
expect "command: sweeps, a bad ref" 2 env HOME="$home" bash "$rl" sweeps nope HEAD
expect "command: threads, an unknown subcommand" 2 env HOME="$home" bash "$rl" threads nonsense
expect "command: threads fetch needs --repo" 2 env HOME="$home" bash "$rl" threads fetch --out "$tmp/none.jsonl"
HOME="$home" expect "install: uninstall" 0 bash "$here/install.sh" --for all --uninstall
if [ ! -e "$home/.claude/skills/pre-pr-review" ] && [ ! -e "$home/.local/bin/review-loop" ]; then pass; else fail "uninstall: everything removed"; fi
# --- the installer puts the launcher folder on the PATH only when asked (scratch HOME; the Windows user PATH is never touched here)
home2="$tmp/home2"; mkdir -p "$home2"
HOME="$home2" REVIEW_LOOP_SKIP_WINDOWS_PATH=1 expect "install: --add-to-path edits the profile" 0 bash "$here/install.sh" --add-to-path
contains "install: it says where it added the line" "added to $home2/.bashrc"
HOME="$home2" REVIEW_LOOP_SKIP_WINDOWS_PATH=1 expect "install: a second run does not add it again" 0 bash "$here/install.sh" --add-to-path
if [ "$(grep -c '# review-loop' "$home2/.bashrc")" = "1" ]; then pass; else fail "install: the profile line is there exactly once"; fi
home3="$tmp/home3"; mkdir -p "$home3"
HOME="$home3" expect "install: --no-path never touches a profile" 0 bash "$here/install.sh" --no-path
if [ ! -e "$home3/.bashrc" ]; then pass; else fail "install: --no-path left a profile behind"; fi
HOME="$tmp/home4" expect "install: with no terminal and no flag it does not ask or edit" 0 bash "$here/install.sh"
if [ ! -e "$tmp/home4/.bashrc" ]; then pass; else fail "install: it edited a profile without being asked"; fi

# --- the plugin manifest and VERSION agree
if [ "$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$here/.claude-plugin/plugin.json")" = "$(tr -d '[:space:]' < "$here/VERSION")" ]; then pass; else fail "plugin.json version must equal VERSION"; fi

# --- every skill is well formed: the name matches the folder (VS Code requires it), a description, a file for every reference named
for d in "$here"/skills/*/; do
  n="$(basename "$d")"
  if [ "$(sed -n 's/^name:[[:space:]]*//p' "$d/SKILL.md" | head -1)" = "$n" ]; then pass; else fail "skill $n: the name in SKILL.md must equal the folder name"; fi
  if sed -n '1,/^---$/p;' "$d/SKILL.md" | grep -q '^description: .\{40,\}'; then pass; else fail "skill $n: needs a description of some length"; fi
  for ref in $(grep -o 'references/[A-Za-z0-9._-]*\.md' "$d/SKILL.md" | sort -u); do
    if [ -f "$d/$ref" ]; then pass; else fail "skill $n: SKILL.md names $ref, which does not exist"; fi
  done
done

# --- the multipass table assigns every lens and sweep to a reader
table="$here/skills/pre-pr-review/references/multipass.md"
lens_text="$(grep -E '^\| [1234]\.' "$table" | sed -E 's/;.*//; s/^\|[^|]*\|//')"
sweep_text="$(grep -E '^\| [123]\.' "$table" | sed -E 's/^[^;]*;//')"
for n in $(seq 1 19); do
  if printf '%s\n' "$lens_text" | grep -Eq "(^|[^0-9])$n([^0-9]|$)"; then pass; else fail "multipass: lens $n belongs to no reader"; fi
done
for n in $(seq 1 12); do
  if printf '%s\n' "$sweep_text" | grep -Eq "(^|[^0-9])$n([^0-9]|$)"; then pass; else fail "multipass: sweep $n belongs to no reader"; fi
done

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
