#!/usr/bin/env bash
# =============================================================================
# 04_build_pgi.sh -- build a polygenic index (PGI) from the real genotypes.
#
# What a PGI is, in one line: for each person, walk through thousands of
# genetic variants, multiply the person's allele count (0, 1, or 2 copies)
# at each variant by that variant's WEIGHT, and add it all up. One number
# per person. The weights come from someone else's large "discovery" study
# (GWAS summary statistics) -- for this lab, posted to our shared USC pod
# bucket.
#
# PLINK does the arithmetic. Our job is the honest bookkeeping around it:
# fetch the weights, tell PLINK exactly which column is which, and then
# READ THE MATCH COUNT -- how many weight rows actually found their variant
# in our data. Rows that don't match don't error; they silently sit out.
# Counting is how you notice.
# =============================================================================
source "$(dirname "$0")/common.sh"
[[ -s "lab_data/chr${CHROM}_filtered.bed" ]] || { echo 'No genotypes yet. Run: bash scripts/01_fetch_genotypes.sh' >&2; exit 1; }
[[ -s results/aou_pheno.tsv ]] || { echo 'No phenotype yet. Run: bash scripts/02_build_phenotype.sh' >&2; exit 1; }

# --- Get the weight file ----------------------------------------------------
# Expected format: a header line, then three columns per row:
#     rsid    effect_allele    weight
# The rsid names the variant; the EFFECT ALLELE says which of the two
# alleles the weight refers to (naming it is what makes the bookkeeping
# unambiguous); the weight is the per-copy effect from the discovery GWAS.
weights=lab_data/height_weights.txt
if [[ ! -s "$weights" ]]; then
  if [[ "${DEMO_WEIGHTS:-}" == 1 ]]; then
    # Rehearsal-only escape hatch: invent random weights from our own
    # variant list so the plumbing can be tested when the posted file is
    # not reachable. The results are NOISE, clearly labeled.
    echo 'DEMO_WEIGHTS=1: fabricating STUB weights (plumbing test only -- results are noise).'
    awk 'BEGIN{print "rsid\teffect_allele\tweight"; srand(20260921)}
         {printf "%s\t%s\t%.5f\n", $2, $5, (rand()-0.5)/50}' \
        "lab_data/chr${CHROM}_filtered.bim" > "$weights"
  elif [[ -n "${WEIGHTS_URI:-}" ]]; then
    gflags=(); [[ -z "${BILLING_PROJECT:-}" ]] || gflags=(--billing-project="$BILLING_PROJECT")
    gcloud "${gflags[@]}" storage cp "$WEIGHTS_URI" "$weights" \
      || { echo "Could not fetch $WEIGHTS_URI -- ask the instructor." >&2; exit 1; }
  else
    echo 'No weights: set WEIGHTS_URI in config.sh to the posted file.' >&2; exit 1
  fi
fi
head -n 2 "$weights"     # always look at a file before using it

# --- The scoring command ----------------------------------------------------
#   --bfile PREFIX        read the genotype trio PREFIX.bed/.bim/.fam
#   --score FILE 1 2 3    read weights from FILE; the three numbers are
#                         COLUMN POSITIONS: variant name in column 1,
#                         effect allele in column 2, weight in column 3.
#                         Count the columns yourself with the head command
#                         above -- pointing at the wrong column is the
#                         classic error, and PLINK cannot always tell.
#   header                first line of FILE is column names, not data
#   cols=+scoresums       also report each person's raw SUM
#   list-variants         write the exact list of variants used (kept as
#                         provenance: proof of what went into the score)
#   --out results/aou_pgi outputs: .sscore (the scores), .log, .sscore.vars
p2 --bfile "lab_data/chr${CHROM}_filtered" \
  --score "$weights" 1 2 3 header cols=+scoresums list-variants \
  --out results/aou_pgi

# The match count -- read it every time. "processed" = weight rows that
# found their variant; "skipped" = rows that matched nothing (wrong name
# scheme, or variants our file doesn't carry). grep pulls those lines out
# of the log for you.
grep -E 'variants processed|skipped' results/aou_pgi.log || true

# One quiet PLINK default worth knowing: if a person's genotype is MISSING
# at some variant, PLINK fills in the average allele count instead of
# skipping. Reasonable at low missingness -- but it is a choice, and
# published work states it.

# Make the summary table and the ancestry figure for the score.
python3 scripts/pgi_eda.py

printf 'Next: bash scripts/05_pgi_regression.sh\n'

# TRY IT (after the lab): a one-chromosome PGI is deliberately partial.
# Real studies run this same command for all 22 chromosomes and add the
# per-person SUM columns together. Try chromosome 21:
#     CHROM=21 bash scripts/01_fetch_genotypes.sh
#     CHROM=21 bash scripts/04_build_pgi.sh
