#!/usr/bin/env bash
# Create and list eval cases: a past change plus the findings that were raised on it.
#
#   eval-case.sh new <id> <base> <tip> [source]   create evals/<id>/case.md for the range <base>..<tip>
#   eval-case.sh list                             one line per case: id, range, number of findings
#
# <tip> is the change as it was reviewed, BEFORE any finding was fixed. <source> says where the findings came from
# (an outside reviewer, an incident, an audit). Cases live in $EVALS_DIR (default: <repository root>/evals).
# Fill in the Findings section by hand; the format is in skills/review-eval/SKILL.md.
set -eu
dir="${EVALS_DIR:-$(git rev-parse --show-toplevel)/evals}"
case "${1:-}" in
  new)
    [ $# -ge 4 ] || { echo "usage: eval-case.sh new <id> <base> <tip> [source]"; exit 2; }
    id="$2"
    case "$id" in ''|*[!A-Za-z0-9._-]*) echo "id must be letters, digits, . _ -"; exit 2 ;; esac
    base="$(git rev-parse --verify "$3^{commit}")"; tip="$(git rev-parse --verify "$4^{commit}")"
    git merge-base --is-ancestor "$base" "$tip" || { echo "$3 is not an ancestor of $4"; exit 2; }
    [ ! -e "$dir/$id" ] || { echo "case $id exists"; exit 2; }
    mkdir -p "$dir/$id"
    {
      echo "Case: $id"
      echo "Range: $base..$tip"
      echo "Source: ${5:-}"
      echo "Date: $(date +%Y-%m-%d)"
      echo
      echo "Findings (one per line: id | path:line | class | the defect, in a sentence):"
      echo
      echo "# F1 | path/to/file:123 | state | what is wrong and what input or state shows it"
    } > "$dir/$id/case.md"
    echo "created $dir/$id/case.md (add the findings below the heading, one per line, no leading #)" ;;
  list)
    for c in "$dir"/*/case.md; do
      [ -f "$c" ] || continue
      printf '%s\t%s\t%s findings\n' "$(sed -n 's/^Case:[[:space:]]*//p' "$c" | head -1)" \
        "$(sed -n 's/^Range:[[:space:]]*//p' "$c" | head -1 | cut -c1-21)..." "$(grep -Ec '^F[0-9]+ \|' "$c")"
    done ;;
  *) echo "usage: eval-case.sh new|list"; exit 2 ;;
esac
