#!/usr/bin/env bash
# Gate: every commit of a change must be covered by a saved review report with no open finding.
#
#   review-gate.sh <base-ref> <ref> [<ref> ...]
#
# Reports are the files written by the multipass mode (references/multipass.md), one per reviewed range, in $REVIEWS_DIR
# (default: <repository root>/reviews). Each has
#   Reviewed-range: <base sha>..<tip sha>
#   Open: <n>
# The union of the ranges of the reports with "Open: 0" must contain every commit in <base-ref>..<ref> for each ref given.
# A report with Open above 0 that covers a needed commit fails the gate. Exit 1 on any failure.
#
# Optional extra requirement, for a repo that wants a stated check on some paths (an API surface, a migration, a security boundary):
#   REVIEW_REQUIRE_PATHS='<ERE of paths>'   REVIEW_REQUIRE_LINE='<Name>'
# A commit that touches those paths must also be covered by a report with a line "<Name>: checked" or "<Name>: n/a <reason>".
#
# Waiver: REVIEW_WAIVE="reason" prints the reason and passes. It is a decision for whoever owns the change; say so where the change is handed over.
set -u
base="${1:?usage: review-gate.sh <base-ref> <ref> [<ref> ...]}"; shift
dir="${REVIEWS_DIR:-$(git rev-parse --show-toplevel)/reviews}"

if [ -n "${REVIEW_WAIVE:-}" ]; then
  echo "review gate WAIVED: $REVIEW_WAIVE"
  exit 0
fi

for ref in "$base" "$@"; do
  git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || { echo "review gate: '$ref' is not a commit in this repository" >&2; exit 2; }
done

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
need="$tmp/need"; have="$tmp/have"; need_extra="$tmp/need_extra"; have_extra="$tmp/have_extra"
: > "$have"; : > "$have_extra"

for r in "$@"; do git rev-list "$base..$r" 2>/dev/null; done | sort -u > "$need"
[ -s "$need" ] || { echo "review gate: no commits to cover"; exit 0; }

bad=0
shopt -s nullglob
for f in "$dir"/*.md; do
  range=$(sed -n 's/^Reviewed-range:[[:space:]]*//p' "$f" | head -1)
  open=$(sed -n 's/^Open:[[:space:]]*//p' "$f" | head -1)
  [ -n "$range" ] || continue
  if [ "${open:-x}" != "0" ]; then
    # only a problem if this report covers something we need
    if git rev-list "$range" 2>/dev/null | sort -u | comm -12 - "$need" | grep -q .; then
      echo "FAIL $(basename "$f"): Open: ${open:-missing} (must be 0)"; bad=1
    fi
    continue
  fi
  git rev-list "$range" 2>/dev/null >> "$have" || echo "warning: $(basename "$f"): range not found: $range"
  if [ -n "${REVIEW_REQUIRE_LINE:-}" ] && grep -Eqi "^${REVIEW_REQUIRE_LINE}:[[:space:]]*(checked|n/a)" "$f"; then
    git rev-list "$range" 2>/dev/null >> "$have_extra"
  fi
done
sort -u "$have" -o "$have"

missing=$(comm -23 "$need" "$have")
if [ -n "$missing" ]; then
  echo "FAIL: $(printf '%s\n' "$missing" | wc -l | tr -d ' ') commit(s) are in no review report with Open: 0, for example:"
  printf '%s\n' "$missing" | head -5 | while read -r c; do git log -1 --format='  %h %s' "$c"; done
  bad=1
fi

if [ -n "${REVIEW_REQUIRE_PATHS:-}" ] && [ -n "${REVIEW_REQUIRE_LINE:-}" ]; then
  while read -r c; do
    git diff-tree --no-commit-id --name-only -r --root "$c" 2>/dev/null | grep -Eq "$REVIEW_REQUIRE_PATHS" && echo "$c"
  done < "$need" | sort -u > "$need_extra"
  sort -u "$have_extra" -o "$have_extra"
  no_extra=$(comm -23 "$need_extra" "$have_extra")
  if [ -n "$no_extra" ]; then
    echo "FAIL: $(printf '%s\n' "$no_extra" | wc -l | tr -d ' ') commit(s) touch ${REVIEW_REQUIRE_PATHS} but no covering report has a '${REVIEW_REQUIRE_LINE}: checked' (or '${REVIEW_REQUIRE_LINE}: n/a <reason>') line, for example:"
    printf '%s\n' "$no_extra" | head -5 | while read -r c; do git log -1 --format='  %h %s' "$c"; done
    bad=1
  fi
fi

if [ "$bad" -eq 0 ]; then
  echo "review gate: all $(wc -l < "$need" | tr -d ' ') commit(s) covered by reports"
else
  echo "STOP: run the multipass review and fix or explain every finding"
fi
exit "$bad"
