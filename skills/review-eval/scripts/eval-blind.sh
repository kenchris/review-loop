#!/usr/bin/env bash
# Set up a blind run of the reviewer on an eval case.
#
#   eval-blind.sh [--archive] <id> <dest>
#
# Without --archive: checks out the case's tip (the change before any finding was fixed) as a detached worktree at <dest>.
# With --archive: exports the tip as a plain tree with no git history (stricter: the reviewer cannot look at later commits), plus
#   range.diff (the patch of the range), changed-files.txt, _skill/ (the review skill's text and class list, to read from inside
#   the tree), and _sweep-hits.txt (the mechanical sweeps over the range, every hit listed).
# Either way <dest> has no evals directory, and a REVIEW.md: the repository's current one (or $REVIEW_FILE, for a REVIEW.md kept
# elsewhere) with every line removed that carries the tag "case:<id>", or "case:<group>" for a group the case lists on its
# "Groups:" line (a line the repo wrote down because of that very change, or of its round, would give the answer away).
# Prints the instructions to hand to the reviewer.
# Remove a worktree afterwards with: git worktree remove --force <dest>   (an archive is just a directory)
set -eu
archive=0
if [ "${1:-}" = "--archive" ]; then archive=1; shift; fi
[ $# -eq 2 ] || { echo "usage: eval-blind.sh [--archive] <id> <dest>"; exit 2; }
id="$1"; dest="$2"
here="$(cd "$(dirname "$0")" && pwd)"
top="$(git rev-parse --show-toplevel)"
dir="${EVALS_DIR:-$top/evals}"
case_file="$dir/$id/case.md"
[ -f "$case_file" ] || { echo "no such case: $id"; exit 2; }
range="$(sed -n 's/^Range:[[:space:]]*//p' "$case_file" | head -1)"
base="${range%%..*}"; tip="${range##*..}"
groups="$(sed -n 's/^Groups:[[:space:]]*//p' "$case_file" | head -1)"
[ ! -e "$dest" ] || { echo "$dest exists"; exit 2; }

if [ "$archive" -eq 1 ]; then
  mkdir -p "$dest"
  git archive "$tip" | tar -x -C "$dest"
  git diff "$base..$tip" > "$dest/range.diff"
  git diff --name-only "$base..$tip" > "$dest/changed-files.txt"
  mkdir -p "$dest/_skill"
  cp "$here/../../pre-pr-review/SKILL.md" "$dest/_skill/SKILL.md"
  cp "$here/../../pre-pr-review/references/classes.md" "$dest/_skill/classes.md"
  sweeps=("$here/../../pre-pr-review/scripts/sweeps/"*.sweeps)
  [ -f "$top/REVIEW.sweeps" ] && sweeps+=("$top/REVIEW.sweeps")
  [ -n "${REVIEW_SWEEPS:-}" ] && [ -f "$REVIEW_SWEEPS" ] && sweeps+=("$REVIEW_SWEEPS")
  DIFF_SWEEPS_MAX=0 bash "$here/../../pre-pr-review/scripts/diff-sweeps.sh" "$base" "$tip" "${sweeps[@]}" > "$dest/_sweep-hits.txt" 2>&1 || true
else
  git worktree add -q --detach "$dest" "$tip"
fi
rm -rf "$dest/evals"

# The repo's REVIEW.md of today (or $REVIEW_FILE) is what the reviewer would have now, so that is the one it gets: an old tip has none,
# or an older one. Lines tagged with this case, or a group of it, are left out.
review_file="${REVIEW_FILE:-$top/REVIEW.md}"
if [ -f "$review_file" ]; then
  cp "$review_file" "$dest/REVIEW.md"
  dropped=0
  for tag in "$id" $groups; do
    n="$(grep -c "case:$tag\([^A-Za-z0-9._-]\|\$\)" "$dest/REVIEW.md" || true)"
    dropped=$((dropped + n))
    grep -v "case:$tag\([^A-Za-z0-9._-]\|\$\)" "$dest/REVIEW.md" > "$dest/REVIEW.md.blind" || true
    mv "$dest/REVIEW.md.blind" "$dest/REVIEW.md"
  done
  echo "REVIEW.md: $dropped line(s) left out (tags: $id $groups)" >&2
else
  rm -f "$dest/REVIEW.md"
  echo "no REVIEW.md ($review_file): the reviewer gets the skills only" >&2
fi

cat <<EOF
Blind review of the change $base..$tip, at $dest.

Rules for the reviewer:
- Work read-only in $dest. Do not edit, commit or post anything.
- Review the range with the pre-pr-review skill (multipass if you were asked to).
- Do not read anything outside $dest, do not look at history after $tip (no later commits, no other branches, no pull request
  discussion), and do not look for an evals directory.
- Write the report in the pre-pr-review format, and list what you read in full and what you skimmed.
EOF
