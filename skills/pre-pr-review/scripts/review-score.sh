#!/usr/bin/env bash
# Score of the self-review against what outside reviewers (people, bots, CI) raised afterwards.
#
#   review-score.sh add <round> <change> <found> <outside-new> <rejected> [note]
#   review-score.sh show
#
#   round         a label for the round (a number, a date)
#   change        the PR or branch
#   found         findings of the self-review that were real and fixed before the change went out
#   outside-new   findings the outside reviewers raised that the self-review had NOT reported
#   rejected      findings of the self-review that the outside reviewers or the author rejected (noise)
#
# recall = found / (found + outside-new)       noise = rejected / (found + rejected)
# File: $REVIEWS_DIR/score.tsv (default: <repository root>/reviews/score.tsv)
set -eu
f="${REVIEWS_DIR:-$(git rev-parse --show-toplevel)/reviews}/score.tsv"
mkdir -p "$(dirname "$f")"
[ -f "$f" ] || printf 'round\tchange\tfound\toutside_new\trejected\tnote\n' > "$f"
case "${1:-show}" in
  add)
    [ $# -ge 6 ] || { echo "usage: review-score.sh add <round> <change> <found> <outside-new> <rejected> [note]"; exit 2; }
    for n in "$4" "$5" "$6"; do case "$n" in ''|*[!0-9]*) echo "not a number: $n"; exit 2 ;; esac; done
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "$6" "${7:-}" >> "$f" ;;
  show)
    awk -F'\t' '
      NR == 1 { print; next }
      { print; found += $3; out += $4; rej += $5; r[$1] += $3; o[$1] += $4 }
      END {
        if (found + out > 0) printf "\ntotal: found %d, outside new %d, rejected %d\nrecall %.0f%%", found, out, rej, 100 * found / (found + out)
        if (found + rej > 0) printf ", noise %.0f%%", 100 * rej / (found + rej)
        print ""
        n = 0; for (k in r) if (r[k] + o[k] > 0) printf "round %s: recall %.0f%%\n", k, 100 * r[k] / (r[k] + o[k])
        if (found + out == 0) print "\n(no rounds recorded)"
      }' "$f" ;;
  *) echo "usage: review-score.sh add|show"; exit 2 ;;
esac
