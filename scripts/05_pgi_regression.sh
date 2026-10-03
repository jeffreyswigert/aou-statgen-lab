#!/usr/bin/env bash
# =============================================================================
# 05_pgi_regression.sh -- a basic regression that includes the PGI.
#
# Everything so far meets in one model: the standardized phenotype
# regressed on the standardized PGI, adjusting for age, sex, and five
# genetic principal components. The model, and the reasoning behind each
# piece of it, are in scripts/pgi_regression.py. This wrapper only checks
# that the inputs exist.
# =============================================================================
source "$(dirname "$0")/common.sh"
if [[ ! -s work/aou_pgi.sscore ]]; then
  echo 'No PGI yet. Run: bash scripts/04_build_pgi.sh' >&2
  exit 1
fi
if [[ ! -s work/aou_pheno.tsv ]]; then
  echo 'No phenotype yet. Run: bash scripts/02_build_phenotype.sh' >&2
  exit 1
fi
python3 scripts/pgi_regression.py
