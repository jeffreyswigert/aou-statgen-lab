#!/usr/bin/env bash
# =============================================================================
# 03_explore_phenotype.sh -- look at the phenotype BEFORE any modeling.
#
# The habit this step teaches: never feed a variable into a model you have
# not looked at. A summary table and a picture catch most construction
# mistakes -- wrong units, a stray spike, an implausible mean -- for
# pennies, before they become wrong results.
#
# This wrapper only checks prerequisites; the actual analysis is in
# scripts/pheno_eda.py -- read that file, it is the lesson.
# =============================================================================
source "$(dirname "$0")/common.sh"
[[ -s results/aou_pheno.tsv ]] || { echo 'No phenotype yet. Run: bash scripts/02_build_phenotype.sh' >&2; exit 1; }
python3 scripts/pheno_eda.py
