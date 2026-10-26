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
for k in aa bb cc dd ee; do printf 'x = j.value("%s", 0);\n' "$k" >> a.cpp; done; git commit -qam many
DIFF_SWEEPS_MAX=2 expect "sweeps: the cap is respected" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
contains "sweeps: ... and the rest is counted" "... 5 hits"
DIFF_SWEEPS_MAX=100 expect "sweeps: a high cap shows every hit" 0 bash "$pp/diff-sweeps.sh" HEAD~1 HEAD
if ! printf '%s' "$out" | grep -q "\.\.\. 5 hits" && printf '%s' "$out" | grep -q "a.cpp:6"; then pass; else fail "sweeps: with a high cap all five hits are listed and none is elided"; fi
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
contains "sweeps: a wrong type becoming the default is named" "[wrong-type-becomes-default]"
contains "sweeps: a dropped write result is named" "[ignored-write-result]"
contains "sweeps: a loop over a client member is named" "[loop-over-client-member]"
if printf '%s' "$out" | grep -A3 "\[ignored-write-result\]" | grep -q "bool ok = WriteJsonFile"; then fail "sweeps: a write whose result is kept is not a hit"; else pass; fi
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
unset EVALS_DIR

# --- install.sh and the command
newrepo; home="$tmp/home"; mkdir -p "$home"
HOME="$home" expect "install: both targets, command" 0 bash "$here/install.sh" --for all
for d in .claude/skills .copilot/skills; do
  if [ -f "$home/$d/pre-pr-review/SKILL.md" ] && [ -f "$home/$d/review-eval/SKILL.md" ]; then pass; else fail "install: skills in $d"; fi
done
if [ -x "$home/.local/bin/review-loop" ]; then pass; else fail "install: the command is executable"; fi
expect "command: version" 0 env HOME="$home" bash "$home/.local/bin/review-loop" version
expect "command: init" 0 env HOME="$home" bash "$rl" init --vscode
for f in REVIEW.md REVIEW.sweeps .review-loop.env .vscode/tasks.json; do
  if [ -e "$tmp/$f" ]; then pass; else fail "init: created $f"; fi
done
echo mine > REVIEW.md
expect "command: init does not overwrite" 0 env HOME="$home" bash "$rl" init --vscode
if [ "$(cat REVIEW.md)" = "mine" ]; then pass; else fail "init: REVIEW.md was overwritten"; fi
if [ -e .vscode/review-loop.tasks.json ]; then pass; else fail "init: a second --vscode writes the tasks beside an existing tasks.json"; fi
expect "command: doctor" 0 env HOME="$home" bash "$rl" doctor
expect "command: an unknown command" 2 env HOME="$home" bash "$rl" nonsense
expect "command: sweeps, a bad ref" 2 env HOME="$home" bash "$rl" sweeps nope HEAD
HOME="$home" expect "install: uninstall" 0 bash "$here/install.sh" --for all --uninstall
if [ ! -e "$home/.claude/skills/pre-pr-review" ] && [ ! -e "$home/.local/bin/review-loop" ]; then pass; else fail "uninstall: everything removed"; fi

# --- the multipass table assigns every lens and sweep to a reader
table="$here/skills/pre-pr-review/references/multipass.md"
lens_text="$(grep -E '^\| [123]\.' "$table" | sed -E 's/;.*//; s/^\|[^|]*\|//')"
sweep_text="$(grep -E '^\| [123]\.' "$table" | sed -E 's/^[^;]*;//')"
for n in $(seq 1 18); do
  if printf '%s\n' "$lens_text" | grep -Eq "(^|[^0-9])$n([^0-9]|$)"; then pass; else fail "multipass: lens $n belongs to no reader"; fi
done
for n in $(seq 1 12); do
  if printf '%s\n' "$sweep_text" | grep -Eq "(^|[^0-9])$n([^0-9]|$)"; then pass; else fail "multipass: sweep $n belongs to no reader"; fi
done

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
