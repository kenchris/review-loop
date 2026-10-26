#!/usr/bin/env bash
# Mechanical sweeps over the ADDED lines of a range: the classes of bug that a grep can point at.
#
#   diff-sweeps.sh <base-ref> <tip-ref> [sweep-file ...]
#
# Sweep files (default: every scripts/sweeps/*.sweeps next to this script, plus ./REVIEW.sweeps at the repository root if it exists).
# One sweep per line, fields separated by " ## ":
#
#   name ## path globs (space separated, git pathspec) ## regex (POSIX ERE, awk dialect: [[:space:]], not \s) ## why it is a question
#
# Blank lines and lines starting with # are ignored.
#
# Warn-only: every hit is a question for the author ("why is this fine?"), not a verdict, and the exit status is 0.
# DIFF_SWEEPS_STRICT=1 makes it exit 1 when there is any hit (for a repo that wants a CI check).
# Also checked: conflict markers in the files the range touches.
set -u
base="${1:?usage: diff-sweeps.sh <base-ref> <tip-ref> [sweep-file ...]}"
tip="${2:?usage: diff-sweeps.sh <base-ref> <tip-ref> [sweep-file ...]}"
shift 2

here="$(cd "$(dirname "$0")" && pwd)"
top="$(git rev-parse --show-toplevel)"
files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
  for f in "$here"/sweeps/*.sweeps; do [ -f "$f" ] && files+=("$f"); done
  [ -f "$top/REVIEW.sweeps" ] && files+=("$top/REVIEW.sweeps")
fi

hits=0
sweep() {  # name, globs, regex, why
  local name="$1" globs="$2" re="$3" why="$4" out n
  set -f  # the globs are git pathspecs, not shell patterns
  # shellcheck disable=SC2086  # $globs is meant to split into several pathspecs
  out=$(git diff -U0 --no-color "$base..$tip" -- $globs 2>/dev/null | RE="$re" awk '
    /^\+\+\+ b\// { f = substr($0, 7); next }
    /^@@/ { match($0, /\+[0-9]+/); ln = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
    /^\+/ { line = substr($0, 2); if (line ~ ENVIRON["RE"]) printf "  %s:%d: %s\n", f, ln, substr(line, 1, 150); ln++ }')
  set +f
  [ -n "$out" ] || return 0
  n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  echo "[$name] $why"
  printf '%s\n' "$out" | head -12
  [ "$n" -gt 12 ] && echo "  ... $n hits"
  hits=$((hits + n))
}

for file in "${files[@]}"; do
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *' ## '*' ## '*) ;; *) echo "diff-sweeps: $file: not 'name ## globs ## regex ## why': $line" >&2; continue ;; esac
    name="${line%% ## *}"; rest="${line#* ## }"
    globs="${rest%% ## *}"; rest="${rest#* ## }"
    re="${rest%% ## *}"; why="${rest#* ## }"
    [ "$why" = "$re" ] && why=""
    sweep "$name" "$globs" "$re" "$why"
  done < "$file"
done

# Merge hygiene in the files the range touches: conflict markers committed.
touched=$(git diff --name-only "$base..$tip" 2>/dev/null)
if [ -n "$touched" ]; then
  markers=$(printf '%s\n' "$touched" | xargs git grep -l -E '^(<<<<<<< |>>>>>>> )' "$tip" -- 2>/dev/null | sed "s|^[^:]*:||")
  if [ -n "$markers" ]; then
    echo "[conflict-markers] committed conflict markers:"; printf '%s\n' "$markers" | sed 's/^/  /'
    hits=$((hits + 1))
  fi
fi

echo "diff-sweeps: $hits question(s) for the author (warn-only)"
[ "${DIFF_SWEEPS_STRICT:-0}" = "1" ] && [ "$hits" -gt 0 ] && exit 1
exit 0
