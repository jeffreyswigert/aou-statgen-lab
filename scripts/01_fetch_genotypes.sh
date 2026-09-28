#!/usr/bin/env bash
# =============================================================================
# 01_fetch_genotypes.sh -- copy REAL genotype data onto this VM.
#
# The idea: genotype files live in cloud storage (addresses that start with
# gs://). Programs like PLINK can only read ordinary files on this
# computer's disk, so step one of any analysis is COPYING what you need
# down. Nothing "streams" from the cloud by itself.
#
# We copy two things:
#   1. one chromosome of genotypes -- a trio of files that travel together:
#        .bed  the genotypes themselves (binary -- never open it as text)
#        .bim  one line per genetic variant (which variants, which alleles)
#        .fam  one line per person (who is in the file)
#      This is the "HapMap3-filtered" set: ~1-2 GB instead of the full
#      callset's tens of GB, so class stays fast -- but it is real data.
#   2. All of Us's genetic-ancestry predictions (used later for a figure
#      and for the regression's control variables).
# =============================================================================
source "$(dirname "$0")/common.sh"
mkdir -p lab_data     # downloaded inputs live here (git ignores this folder)

# Some AoU buckets are "requester pays": they refuse downloads unless you
# say which project pays the (small) transfer bill. We build that flag once
# here. The () syntax makes a LIST, so the flag can be inserted into
# commands below -- or be nothing at all if BILLING_PROJECT is empty.
gflags=()
[[ -z "${BILLING_PROJECT:-}" ]] || gflags=(--billing-project="$BILLING_PROJECT")

echo "Copying chr${CHROM} genotypes from $GENO_SRC ..."
# A for-loop: run the copy once for each of the three extensions.
for ext in bed bim fam; do
  gcloud "${gflags[@]}" storage cp "$GENO_SRC/chr${CHROM}_filtered.$ext" "lab_data/" \
    || { echo "Download failed. Check GENO_SRC and BILLING_PROJECT in config.sh, and bucket access." >&2; exit 1; }
done

echo "Copying ancestry predictions from $ANC_SRC ..."
gcloud "${gflags[@]}" storage cp "$ANC_SRC" "lab_data/ancestry_preds.tsv" \
  || { echo 'Ancestry download failed (this bucket is requester-pays: BILLING_PROJECT must be set).' >&2; exit 1; }

# NEVER trust a download you haven't counted. Cloud copies can fail in
# quiet ways (cut short, wrong path matching nothing). Ten seconds of
# counting is the insurance:
#   ls -lh          shows each file and its size
#   wc -l < FILE    counts the lines in FILE (one line per person / variant)
ls -lh lab_data/chr${CHROM}_filtered.* lab_data/ancestry_preds.tsv
n_samples=$(wc -l < "lab_data/chr${CHROM}_filtered.fam")
n_variants=$(wc -l < "lab_data/chr${CHROM}_filtered.bim")
echo "chr${CHROM}: $n_samples people x $n_variants variants staged."

# Look at two lines of each text file BEFORE trusting it -- different AoU
# resources use different ID conventions, and mismatches fail silently:
#   head -n 2 lab_data/chr${CHROM}_filtered.fam    # how are people keyed?
#   head -n 2 lab_data/chr${CHROM}_filtered.bim    # how are variants named?
printf 'Staged. Next: bash scripts/02_build_phenotype.sh\n'
