#!/usr/bin/env bash
# Set up a blind run of the reviewer on an eval case.
#
#   eval-blind.sh <id> <dest>
#
# Checks out the case's tip (the change before any finding was fixed) as a detached worktree at <dest>, without the evals
# directory, and puts a REVIEW.md in it: the repository's current one (or $REVIEW_FILE, for a REVIEW.md kept elsewhere) with
# every line that carries the tag "case:<id>" removed (a line the repo wrote down because of that very change would give the
# answer away). Prints the instructions to hand to the reviewer.
# Remove the worktree afterwards with: git worktree remove --force <dest>
set -eu
[ $# -eq 2 ] || { echo "usage: eval-blind.sh <id> <dest>"; exit 2; }
id="$1"; dest="$2"
top="$(git rev-parse --show-toplevel)"
dir="${EVALS_DIR:-$top/evals}"
case_file="$dir/$id/case.md"
[ -f "$case_file" ] || { echo "no such case: $id"; exit 2; }
range="$(sed -n 's/^Range:[[:space:]]*//p' "$case_file" | head -1)"
base="${range%%..*}"; tip="${range##*..}"
[ ! -e "$dest" ] || { echo "$dest exists"; exit 2; }

git worktree add -q --detach "$dest" "$tip"
rm -rf "$dest/evals"
# The repo's REVIEW.md of today (or $REVIEW_FILE) is what the reviewer would have now, so that is the one it gets: an old tip has none,
# or an older one. Lines tagged with this case are left out.
review_file="${REVIEW_FILE:-$top/REVIEW.md}"
if [ -f "$review_file" ]; then
  grep -v "case:$id" "$review_file" > "$dest/REVIEW.md" || true
  echo "REVIEW.md: $(grep -c "case:$id" "$review_file" || true) line(s) tagged case:$id left out" >&2
else
  rm -f "$dest/REVIEW.md"
  echo "no REVIEW.md ($review_file): the reviewer gets the skills only" >&2
fi

cat <<EOF
Blind review of the change $base..$tip, checked out at $dest.

Rules for the reviewer:
- Work read-only in $dest. Do not edit, commit or post anything.
- Review the range with the pre-pr-review skill (multipass if you were asked to).
- Do not read anything outside $dest, do not look at history after $tip (no later commits, no other branches, no pull request
  discussion), and do not look for an evals directory.
- Write the report in the pre-pr-review format, and list what you read in full and what you skimmed.
EOF
