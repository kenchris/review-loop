#!/usr/bin/env bash
# Report the recorded runs.
#
#   eval-report.sh                  recall and noise per run, and per case within each run
#   eval-report.sh diff <runA> <runB>   the findings whose verdict changed between two runs (a lens change that helped or hurt)
#
# recall = (found + partial/2) / findings recorded;  strict recall counts only "found".
# noise  = rejected extras / everything the reviewer reported (found + partial + extras).
# Findings with no verdict in a run are not counted for that run; record all of a case's findings before comparing runs.
set -eu
dir="${EVALS_DIR:-$(git rev-parse --show-toplevel)/evals}"
f="$dir/runs.tsv"
[ -f "$f" ] || { echo "no runs recorded ($f)"; exit 0; }
case "${1:-}" in
  diff)
    [ $# -eq 3 ] || { echo "usage: eval-report.sh diff <runA> <runB>"; exit 2; }
    awk -F'\t' -v a="$2" -v b="$3" '
      NR > 1 && $4 != "extra" { if ($2 == a) va[$3 " " $4] = $5; if ($2 == b) vb[$3 " " $4] = $5 }
      END {
        for (k in vb) if ((k in va) && va[k] != vb[k]) printf "%s: %s -> %s\n", k, va[k], vb[k]
        for (k in vb) if (!(k in va)) printf "%s: (not in %s) -> %s\n", k, a, vb[k]
      }' "$f" | sort ;;
  "")
    awk -F'\t' '
      NR == 1 { next }
      {
        run = $2; c = $3
        if (!(run in seen)) { seen[run] = 1; runs[++nr] = run }
        if (!((run, c) in cseen)) { cseen[run, c] = 1; nc[run]++; cl[run, nc[run]] = c }
        if ($4 == "extra") { if ($5 == "real") { xr[run, c]++; XR[run]++ } else { xj[run, c]++; XJ[run]++ } }
        else { n[run, c]++; v[run, c, $5]++; N[run]++; F[run] += ($5 == "found"); P[run] += ($5 == "partial") }
      }
      END {
        for (i = 1; i <= nr; i++) {
          r = runs[i]
          rep = F[r] + P[r] + XR[r] + XJ[r]
          printf "run %s: %d findings, found %d, partial %d, missed %d, extras real %d rejected %d\n", r, N[r], F[r], P[r], N[r] - F[r] - P[r], XR[r], XJ[r]
          if (N[r] > 0) printf "  recall %.0f%% (strict %.0f%%)", 100 * (F[r] + P[r] / 2) / N[r], 100 * F[r] / N[r]
          if (rep > 0) printf ", noise %.0f%%", 100 * XJ[r] / rep
          print ""
          for (j = 1; j <= nc[r]; j++) { c = cl[r, j]
            printf "    %s: found %d/%d, partial %d, extras real %d rejected %d\n", c, v[r, c, "found"], n[r, c], v[r, c, "partial"], xr[r, c], xj[r, c] }
        }
      }' "$f" ;;
  *) echo "usage: eval-report.sh [diff <runA> <runB>]"; exit 2 ;;
esac
