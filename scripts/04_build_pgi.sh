#!/usr/bin/env bash
# =============================================================================
# 04_build_pgi.sh -- build a polygenic index (PGI) from the genotypes.
#
# What a PGI is, in one line: for each person, go through thousands of
# genetic variants, multiply the person's allele count at each variant
# (0, 1, or 2 copies) by that variant's WEIGHT, and add it all up. One
# number per person. The weights come from a large published study (GWAS
# summary statistics). For this lab the instructor converted a published
# height GWAS into a three-column weight file in the workshop bucket;
# WEIGHTS_URI in config.sh points at it.
#
# PLINK does the arithmetic. This script does three things around it:
# gets the weight file, tells PLINK which column is which, and prints the
# MATCH COUNT: how many weight rows found their variant in our data.
# Weight rows that match no variant are not an error; PLINK skips them,
# and the match count is the only place that shows.
# =============================================================================
source "$(dirname "$0")/common.sh"
if [[ ! -s "lab_data/chr${CHROM}_hm3.bed" ]]; then
  echo 'No genotypes yet. Run: bash scripts/01_fetch_genotypes.sh' >&2
  exit 1
fi
if [[ ! -s work/aou_pheno.tsv ]]; then
  echo 'No phenotype yet. Run: bash scripts/02_build_phenotype.sh' >&2
  exit 1
fi

# ---- Get the weight file ------------------------------------------------------
# Expected format: a header line, then three columns per row:
#     rsid    effect_allele    weight
# The rsid names the variant; the EFFECT ALLELE says which of the two
# alleles the weight refers to (naming it is what makes the bookkeeping
# unambiguous); the weight is the per-copy effect from the GWAS.
weights=lab_data/height_weights.txt
if [[ ! -s "$weights" ]]; then
  if [[ "${DEMO_WEIGHTS:-}" == 1 ]]; then
    # Rehearsal-only escape hatch: invent random weights from our own
    # variant list so the plumbing can be tested when the posted file is
    # not reachable. The results are NOISE, and labeled as such.
    echo 'DEMO_WEIGHTS=1: making STUB weights (plumbing test only; results are noise).'
    awk 'BEGIN { print "rsid\teffect_allele\tweight"; srand(20260921) }
         { printf "%s\t%s\t%.5f\n", $2, $5, (rand() - 0.5) / 50 }' \
        "lab_data/chr${CHROM}_hm3.bim" > "$weights"
  elif [[ -n "${WEIGHTS_URI:-}" ]]; then
    if ! gcloud "${gflags[@]}" storage cp "$WEIGHTS_URI" "$weights"; then
      echo "Could not copy $WEIGHTS_URI. Ask the instructor." >&2
      exit 1
    fi
  else
    echo 'No weights: set WEIGHTS_URI in config.sh to the posted file.' >&2
    exit 1
  fi
fi
head -n 2 "$weights"     # always look at a file before using it

# ---- The scoring command --------------------------------------------------------
#   p2                    plink2 with our thread and memory settings (common.sh)
#   --bfile PREFIX        read PREFIX.bed, PREFIX.bim, PREFIX.fam
#   --score FILE 1 2 3    read weights from FILE; the three numbers are
#                         COLUMN POSITIONS: variant ID in column 1, effect
#                         allele in column 2, weight in column 3. Count the
#                         columns yourself with the head command above:
#                         pointing at the wrong column is the classic
#                         error, and PLINK cannot always tell.
#   header                the first line of FILE is column names, not data
#   cols=+scoresums       also report each person's raw SUM (SCORE1_SUM)
#   list-variants         write the exact list of variants used (kept as
#                         provenance: proof of what went into the score)
#   --out work/aou_pgi    outputs: .sscore (one score per person, so it
#                         goes in work/), .log, .sscore.vars
p2 --bfile "lab_data/chr${CHROM}_hm3" \
  --score "$weights" 1 2 3 header cols=+scoresums list-variants \
  --out work/aou_pgi

# ---- The match count: read it every time ----------------------------------------
# "processed" = weight rows that found their variant; "skipped" = rows
# that matched nothing (a different naming scheme, or variants our file
# does not carry). grep pulls those lines out of the log.
# (|| true: if grep finds nothing it "fails", and set -e would stop the
# script; "or true" turns that into "carry on".)
grep -E 'variants processed|skipped' work/aou_pgi.log || true

# One quiet PLINK default worth knowing: where a person's genotype is
# MISSING at a variant, PLINK fills in the variant's average allele count
# instead of skipping. Reasonable at low missingness, but it is a choice,
# and published work states it.

# ---- QC on the PGI: a summary table and a histogram of the standardized score
python3 scripts/pgi_eda.py

printf 'Next: bash scripts/05_pgi_regression.sh\n'

# TRY IT (after the lab): a one-chromosome PGI is deliberately partial.
# Real studies run this same command for all 22 chromosomes and add the
# per-person SUM columns together. Try chromosome 21:
#     CHROM=21 bash scripts/01_fetch_genotypes.sh
#     CHROM=21 bash scripts/04_build_pgi.sh
