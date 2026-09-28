#!/usr/bin/env bash
# =============================================================================
# 05_pgi_regression.sh -- the capstone: a basic regression that incorporates
# the PGI.
#
# Everything so far meets in one model: standardized height regressed on
# the standardized PGI, adjusting for age, sex, and five genetic principal
# components. The model, and the reasoning behind every piece of it, live
# in scripts/pgi_regression.py -- this wrapper only checks prerequisites.
# =============================================================================
source "$(dirname "$0")/common.sh"
[[ -s results/aou_pgi.sscore ]] || { echo 'No PGI yet. Run: bash scripts/04_build_pgi.sh' >&2; exit 1; }
[[ -s results/aou_pheno.tsv ]] || { echo 'No phenotype yet. Run: bash scripts/02_build_phenotype.sh' >&2; exit 1; }
python3 scripts/pgi_regression.py
