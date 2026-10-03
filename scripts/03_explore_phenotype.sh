#!/usr/bin/env bash
# =============================================================================
# 03_explore_phenotype.sh -- look at the phenotype BEFORE any modeling.
#
# The habit this step teaches: never feed a variable into a model you have
# not looked at. A summary table and a picture catch most construction
# mistakes (wrong units, a stray spike, an implausible mean) before they
# become wrong results.
#
# This wrapper only checks that the input exists; the analysis is in
# scripts/pheno_eda.py. Read that file: it is the lesson.
# =============================================================================
source "$(dirname "$0")/common.sh"

# [[ -s FILE ]] is true when FILE exists and is not empty.
if [[ ! -s work/aou_pheno.tsv ]]; then
  echo 'No phenotype file yet. Run: bash scripts/02_build_phenotype.sh' >&2
  exit 1
fi
python3 scripts/pheno_eda.py
