#!/usr/bin/env bash
# Record how a run of the reviewer did on an eval case.
#
#   eval-record.sh finding <run> <case> <Fn> found|partial|missed [note]
#   eval-record.sh extra   <run> <case> real|rejected [note]
#
# <run> labels one run of the reviewer (a date, or the version of the lenses it used). For each finding of the case,
# record whether the report had it (found), had part of it or the same line with the opposite conclusion (partial), or not (missed).
# Findings in the report that are not in the case are "extras": real if you confirm them in the code, rejected if they are wrong or noise.
# Writes to $EVALS_DIR/runs.tsv (default: <repository root>/evals/runs.tsv).
set -eu
dir="${EVALS_DIR:-$(git rev-parse --show-toplevel)/evals}"
f="$dir/runs.tsv"
mkdir -p "$dir"
[ -f "$f" ] || printf 'date\trun\tcase\tfinding\tverdict\tnote\n' > "$f"
now="$(date +%Y-%m-%d)"
case "${1:-}" in
  finding)
    [ $# -ge 5 ] || { echo "usage: eval-record.sh finding <run> <case> <Fn> found|partial|missed [note]"; exit 2; }
    case "$5" in found|partial|missed) ;; *) echo "verdict is found, partial or missed"; exit 2 ;; esac
    grep -Eq "^$4 \|" "$dir/$3/case.md" 2>/dev/null || { echo "case $3 has no finding $4"; exit 2; }
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$2" "$3" "$4" "$5" "${6:-}" >> "$f" ;;
  extra)
    [ $# -ge 4 ] || { echo "usage: eval-record.sh extra <run> <case> real|rejected [note]"; exit 2; }
    case "$4" in real|rejected) ;; *) echo "verdict is real or rejected"; exit 2 ;; esac
    printf '%s\t%s\t%s\textra\t%s\t%s\n' "$now" "$2" "$3" "$4" "${5:-}" >> "$f" ;;
  *) echo "usage: eval-record.sh finding|extra"; exit 2 ;;
esac
