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
# A report with Open above 0 that covers a needed commit fails the gate. Exit 1 on any failure, 2 when a ref is not a commit.
#
# Required lines: a repo can demand a stated check when a commit touches some paths (an API surface, a spec, a migration, a
# security boundary). One per line in $REVIEW_GATE_FILE (default <repository root>/REVIEW.gate):
#   Name ## ERE of paths
# e.g.  Casing ## ^src/api/       Spec ## ^src/protocol/
# A commit that touches matching paths must also be covered by a report with a line "<Name>: checked ..." or "<Name>: n/a <reason>".
# (The older pair REVIEW_REQUIRE_PATHS + REVIEW_REQUIRE_LINE still works and counts as one more line.)
#
# Waiver: REVIEW_WAIVE="reason" prints the reason and passes. It is a decision for whoever owns the change; say so where the change is handed over.
set -u
base="${1:?usage: review-gate.sh <base-ref> <ref> [<ref> ...]}"; shift
top="$(git rev-parse --show-toplevel)"
dir="${REVIEWS_DIR:-$top/reviews}"

if [ -n "${REVIEW_WAIVE:-}" ]; then
  echo "review gate WAIVED: $REVIEW_WAIVE"
  exit 0
fi

for ref in "$base" "$@"; do
  git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || { echo "review gate: '$ref' is not a commit in this repository" >&2; exit 2; }
done

# Required lines: name and path pattern, side by side.
req_name=(); req_re=()
gatefile="${REVIEW_GATE_FILE:-$top/REVIEW.gate}"
if [ -f "$gatefile" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      *' ## '*) req_name+=("${line%% ## *}"); req_re+=("${line#* ## }") ;;
      *) echo "review gate: $gatefile: not 'Name ## path regex': $line" >&2; exit 2 ;;
    esac
  done < "$gatefile"
fi
if [ -n "${REVIEW_REQUIRE_PATHS:-}" ] && [ -n "${REVIEW_REQUIRE_LINE:-}" ]; then
  req_name+=("$REVIEW_REQUIRE_LINE"); req_re+=("$REVIEW_REQUIRE_PATHS")
fi
nreq=${#req_name[@]}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
need="$tmp/need"; have="$tmp/have"
: > "$have"
i=0; while [ "$i" -lt "$nreq" ]; do : > "$tmp/have_$i"; i=$((i + 1)); done

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
  i=0
  while [ "$i" -lt "$nreq" ]; do
    if grep -Eqi "^${req_name[$i]}:[[:space:]]*(checked|n/a)" "$f"; then git rev-list "$range" 2>/dev/null >> "$tmp/have_$i"; fi
    i=$((i + 1))
  done
done
sort -u "$have" -o "$have"

missing=$(comm -23 "$need" "$have")
if [ -n "$missing" ]; then
  echo "FAIL: $(printf '%s\n' "$missing" | wc -l | tr -d ' ') commit(s) are in no review report with Open: 0, for example:"
  printf '%s\n' "$missing" | head -5 | while read -r c; do git log -1 --format='  %h %s' "$c"; done
  bad=1
fi

i=0
while [ "$i" -lt "$nreq" ]; do
  name="${req_name[$i]}"; re="${req_re[$i]}"
  while read -r c; do
    git diff-tree --no-commit-id --name-only -r --root "$c" 2>/dev/null | grep -Eq "$re" && echo "$c"
  done < "$need" | sort -u > "$tmp/need_$i"
  sort -u "$tmp/have_$i" -o "$tmp/have_$i"
  short=$(comm -23 "$tmp/need_$i" "$tmp/have_$i")
  if [ -n "$short" ]; then
    echo "FAIL: $(printf '%s\n' "$short" | wc -l | tr -d ' ') commit(s) touch paths matching $re but no covering report has a '$name: checked' (or '$name: n/a <reason>') line, for example:"
    printf '%s\n' "$short" | head -5 | while read -r c; do git log -1 --format='  %h %s' "$c"; done
    bad=1
  fi
  i=$((i + 1))
done

if [ "$bad" -eq 0 ]; then
  echo "review gate: all $(wc -l < "$need" | tr -d ' ') commit(s) covered by reports"
else
  echo "STOP: run the multipass review and fix or explain every finding"
fi
exit "$bad"
