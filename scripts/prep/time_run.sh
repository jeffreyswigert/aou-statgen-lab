#!/usr/bin/env bash
# =============================================================================
# prep/time_run.sh -- INSTRUCTOR rehearsal tool: run steps 00-06 in order and
# record how long each one takes on the real platform.
#
# Run:   bash scripts/prep/time_run.sh
#        STEPS="02 03" bash scripts/prep/time_run.sh     # only some steps
# Output: each step's normal output, then a table of wall-clock times, also
#         written to results/step_times.txt (times only -- no data).
#
# Rehearsing before the workshop files exist: point config.sh at genotypes
# you can already read (GENO_SRC, GENO_STEM) and, if there are no weights
# yet, run with DEMO_WEIGHTS=1 (random stub weights; the timings are real,
# the PGI results are noise).
# =============================================================================
source "$(dirname "$0")/../common.sh"
set +e      # keep going long enough to report the time of a failing step

steps=(${STEPS:-00 01 02 03 04 05 06})
names=(00_setup 01_fetch_genotypes 02_build_phenotype 03_explore_phenotype
       04_build_pgi 05_pgi_regression 06_save_run)
rows=(); total=0
for s in "${steps[@]}"; do
  n=${names[$((10#$s))]}; script="scripts/$n.sh"
  printf '\n===== %s  (started %s) =====\n' "$script" "$(date +%H:%M:%S)"
  t0=$(date +%s)
  bash "$script"; rc=$?
  dt=$(( $(date +%s) - t0 )); total=$(( total + dt ))
  rows+=("$(printf '%-24s %4dm %02ds   %s' "$n" $((dt / 60)) $((dt % 60)) \
            "$([[ $rc == 0 ]] && echo ok || echo "FAILED (exit $rc)")")")
  [[ $rc == 0 ]] || break
done

{
  printf 'Step timings, %s (SAMPLE_MOD=%s, CHROM=%s, DEMO_WEIGHTS=%s)\n' \
         "$(date '+%Y-%m-%d %H:%M')" "$SAMPLE_MOD" "$CHROM" "${DEMO_WEIGHTS:-0}"
  printf '%s\n' "${rows[@]}"
  printf '%-24s %4dm %02ds\n' total $((total / 60)) $((total % 60))
} | tee results/step_times.txt
