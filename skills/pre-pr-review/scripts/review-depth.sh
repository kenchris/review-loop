#!/usr/bin/env bash
# Suggest how deep to review a range: one reader, or the multi-pass review. A suggestion from the shape of the change, not a verdict.
#
#   review-depth.sh <base> <tip>
#
# Prints, first line "depth: single" or "depth: multipass", then the reasons, then the model to use for the readers.
#   documentation only, tests only, or documentation and tests         single (cheaper model)
#   a small change (<= DEPTH_SMALL_LINES code lines, default 60)        single
#   anything else, or any file under a guard path                      multipass
# Guard paths: the path patterns of $REVIEW_GATE_FILE (default <repository root>/REVIEW.gate, the lines "Name ## ERE", which is where
# a repository says which paths carry a contract) and $REVIEW_GUARD_PATHS (an ERE, for example '^src/auth/|installer'). A change that
# touches one is always multipass, however small: a guard is where one reader's miss costs the most.
# Skipped as noise: lock files, generated bundles, vendored code (assets/*.bundle.js, third_party, vendor).
set -eu
[ $# -eq 2 ] || { echo "usage: review-depth.sh <base> <tip>"; exit 2; }
base="$1"; tip="$2"
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "review-depth: not a commit: $base" >&2; exit 2; }
git rev-parse --verify -q "$tip^{commit}" >/dev/null || { echo "review-depth: not a commit: $tip" >&2; exit 2; }
top="$(git rev-parse --show-toplevel)"
small="${DEPTH_SMALL_LINES:-60}"
guards="${REVIEW_GUARD_PATHS:-}"
gatefile="${REVIEW_GATE_FILE:-$top/REVIEW.gate}"
if [ -f "$gatefile" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; *' ## '*) guards="${guards:+$guards|}${line#* ## }" ;; esac
  done < "$gatefile"
fi
docs_re='(\.(md|markdown|rst|txt|adoc)$)|(^|/)docs?/'
tests_re='(^|/)(tests?|spec|__tests__|e2e)/|[._-](test|spec)\.|_test\.'
skip_re='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|third_party|vendor)(/|$)|\.bundle\.js$|\.min\.js$'
code=0; docs=0; tests=0; guarded=""
while IFS=$'\t' read -r add del path; do
  [ -n "$path" ] || continue
  [ "$add" = "-" ] && { add=0; del=0; }   # a binary file
  if printf '%s' "$path" | grep -Eq "$skip_re"; then continue; fi
  n=$((add + del))
  if [ -n "$guards" ] && printf '%s' "$path" | grep -Eq "$guards"; then guarded="${guarded:+$guarded, }$path"; fi
  if printf '%s' "$path" | grep -Eq "$docs_re"; then docs=$((docs + n))
  elif printf '%s' "$path" | grep -Eq "$tests_re"; then tests=$((tests + n))
  else code=$((code + n)); fi
done < <(git diff --numstat --no-renames "$base...$tip" 2>/dev/null || git diff --numstat --no-renames "$base" "$tip")

if [ -n "$guarded" ]; then depth=multipass; reason="touches a guard path: $guarded"
elif [ "$code" -eq 0 ]; then depth=single; reason="documentation and tests only ($docs doc lines, $tests test lines)"
elif [ "$code" -le "$small" ]; then depth=single; reason="small: $code code lines (limit $small)"
else depth=multipass; reason="$code code lines (a small change is up to $small)"; fi
echo "depth: $depth"
echo "why: $reason"
echo "size: code $code, tests $tests, docs $docs (lines added and deleted)"
if [ "$code" -eq 0 ]; then echo "model: haiku or sonnet for the readers (documentation and tests)"
elif [ "$depth" = single ]; then echo "model: sonnet"
else echo "model: sonnet for ordinary code, the strongest model for guards, concurrency, parsers, handles and the Spec reader"; fi
echo "note: write the report with 'Depth: $depth ($reason)'; the gate accepts a report of either depth that has Open: 0"
