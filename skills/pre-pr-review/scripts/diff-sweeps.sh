#!/usr/bin/env bash
# Mechanical sweeps over the ADDED lines of a range: the classes of bug that a grep can point at.
#
#   diff-sweeps.sh <base-ref> <tip-ref> [sweep-file ...]
#
# Sweep files (default: every scripts/sweeps/*.sweeps next to this script, plus ./REVIEW.sweeps at the repository root if it exists).
# One sweep per line, fields separated by " ## ":
#
#   [!]name ## path globs (space separated, git pathspec) ## regex (POSIX ERE, awk dialect: [[:space:]], not \s) ## why it is a question
#
# Blank lines and lines starting with # are ignored.
#
# Warn-only: every hit is a question for the author ("why is this fine?"), not a verdict, and the exit status is 0.
# DIFF_SWEEPS_FORMAT=github prints GitHub Actions warnings (::warning file=,line=::) instead of the text report, for a CI step.
# DIFF_SWEEPS_STRICT=1 makes it exit 1 when there is any hit (for a repo that wants a CI check).
# DIFF_SWEEPS_MAX=<n> shows up to n hits per sweep (default 12; 0 = no cap). A sweep whose name starts with ! is high priority: it is
# listed first and never capped, because what it points at is what a cap must not hide.
# Also checked: conflict markers in the files the range touches.
set -u
base="${1:?usage: diff-sweeps.sh <base-ref> <tip-ref> [sweep-file ...]}"
tip="${2:?usage: diff-sweeps.sh <base-ref> <tip-ref> [sweep-file ...]}"
shift 2

for ref in "$base" "$tip"; do
  git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || { echo "diff-sweeps: '$ref' is not a commit in this repository" >&2; exit 2; }
done

here="$(cd "$(dirname "$0")" && pwd)"
top="$(git rev-parse --show-toplevel)"
files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
  for f in "$here"/sweeps/*.sweeps; do [ -f "$f" ] && files+=("$f"); done
  [ -f "$top/REVIEW.sweeps" ] && files+=("$top/REVIEW.sweeps")
fi

hits=0
max="${DIFF_SWEEPS_MAX:-12}"
sweep() {  # name, globs, regex, why, priority (high or normal)
  local name="$1" globs="$2" re="$3" why="$4" prio="$5" out n cap="$max" mark=""
  if [ "$prio" = "high" ]; then cap=0; mark="!"; fi   # a high-priority sweep is never capped
  set -f  # the globs are git pathspecs, not shell patterns
  # shellcheck disable=SC2086  # $globs is meant to split into several pathspecs
  out=$(git diff -U0 --no-color "$base..$tip" -- $globs 2>/dev/null | RE="$re" awk '
    /^\+\+\+ b\// { f = substr($0, 7); next }
    /^@@/ { match($0, /\+[0-9]+/); ln = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
    /^\+/ { line = substr($0, 2); if (line ~ ENVIRON["RE"]) printf "  %s:%d: %s\n", f, ln, substr(line, 1, 150); ln++ }')
  set +f
  [ -n "$out" ] || return 0
  n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  shown="$(if [ "$cap" -gt 0 ]; then printf '%s\n' "$out" | head -n "$cap"; else printf '%s\n' "$out"; fi)"
  if [ "$cap" -gt 0 ] && [ "$n" -gt "$cap" ]; then shown="$shown
  ... $n hits"; fi
  if [ "${DIFF_SWEEPS_FORMAT:-text}" = github ]; then
    # GitHub Actions workflow commands: one warning per hit, on the file and line, so it shows on the changed line of a pull request.
    printf '%s\n' "$shown" | NAME="$mark$name" WHY="$why" awk '
      { s = $0; sub(/^  /, "", s); p = match(s, /:[0-9]+: /)
        if (p == 0) { print; next }
        file = substr(s, 1, p - 1); ln = substr(s, p + 1); sub(/:.*/, "", ln)
        why = ENVIRON["WHY"]; gsub(/%/, "%25", why); gsub(/\r/, "%0D", why); gsub(/\n/, "%0A", why)
        printf "::warning file=%s,line=%s,title=%s::%s\n", file, ln, ENVIRON["NAME"], why }'
  else
    echo "[$mark$name] $why"
    printf '%s\n' "$shown"
  fi
  hits=$((hits + n))
}

# High-priority sweeps (names starting with !) first, then the rest.
for pass in high normal; do
  for file in ${files[@]+"${files[@]}"}; do  # (the guard keeps an empty list working under set -u in older bash)
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      case "$line" in
        *' ## '*' ## '*) ;;
        *) [ "$pass" = "high" ] && echo "diff-sweeps: $file: not 'name ## globs ## regex ## why': $line" >&2; continue ;;
      esac
      name="${line%% ## *}"; rest="${line#* ## }"
      globs="${rest%% ## *}"; rest="${rest#* ## }"
      re="${rest%% ## *}"; why="${rest#* ## }"
      [ "$why" = "$re" ] && why=""
      prio="normal"
      case "$name" in '!'*) prio="high"; name="${name#!}" ;; esac
      [ "$prio" = "$pass" ] || continue
      sweep "$name" "$globs" "$re" "$why" "$prio"
    done < "$file"
  done
done

# Merge hygiene in the files the range touches: conflict markers committed.
touched=$(git diff --name-only -z "$base..$tip" 2>/dev/null | tr '\0' '\n')
if [ -n "$touched" ]; then
  # NUL-separated, so a file name with a space is not split
  markers=$(git diff --name-only -z "$base..$tip" 2>/dev/null | xargs -0 git grep -l -E '^(<<<<<<< |>>>>>>> )' "$tip" -- 2>/dev/null | sed "s|^[^:]*:||")
  if [ -n "$markers" ]; then
    echo "[conflict-markers] committed conflict markers:"; printf '%s\n' "$markers" | sed 's/^/  /'
    hits=$((hits + 1))
  fi
fi

echo "diff-sweeps: $hits question(s) for the author (warn-only)"
[ "${DIFF_SWEEPS_STRICT:-0}" = "1" ] && [ "$hits" -gt 0 ] && exit 1
exit 0
