#!/usr/bin/env bash
# =============================================================================
# 01_fetch_genotypes.sh -- copy REAL genotype data onto this VM.
#
# The idea: genotype files live in cloud storage (addresses that start with
# gs://). Programs like PLINK can only read ordinary files on this
# computer's disk, so step one of any analysis is COPYING what you need
# down.
#
# We copy two things:
#   1. One chromosome of genotypes -- a trio of files that travel together:
#        .bed  the genotypes themselves (binary -- never open it as text)
#        .bim  one line per genetic variant (which variants, which alleles)
#        .fam  one line per person (who is in the file)
#      These are All of Us's own whole-genome-sequencing genotypes (the
#      "ACAF threshold" callset), restricted to the ~17,000 HapMap3
#      variants on the chromosome. All of Us does not publish a HapMap3
#      subset, so the instructor made this one before class with
#      scripts/prep/make_hm3_subset.sh and put it in the workshop bucket.
#      The full chromosome-22 file is ~250 GB; the subset is ~2 GB.
#   2. All of Us's genetic-ancestry predictions (the regression uses the
#      principal components stored in this file).
# =============================================================================
source "$(dirname "$0")/common.sh"
mkdir -p lab_data     # downloaded inputs live here (git ignores this folder)

# Some AoU buckets are "requester pays": they refuse downloads unless you
# say which project pays the (small) transfer bill. We build that flag once
# here. The () syntax makes a LIST, so the flag can be inserted into
# commands below -- or be nothing at all if BILLING_PROJECT is empty.
gflags=()
[[ -z "${BILLING_PROJECT:-}" ]] || gflags=(--billing-project="$BILLING_PROJECT")

echo "Copying chr${CHROM} HapMap3 genotypes from $GENO_SRC ..."
# A for-loop: run the copy once for each of the three extensions.
for ext in bed bim fam; do
  gcloud "${gflags[@]}" storage cp "$GENO_SRC/chr${CHROM}_hm3.$ext" "lab_data/" \
    || { echo "Copy failed. Check GENO_SRC and BILLING_PROJECT in config.sh." >&2; exit 1; }
done

echo "Copying ancestry predictions from $ANC_SRC ..."
gcloud "${gflags[@]}" storage cp "$ANC_SRC" "lab_data/ancestry_preds.tsv" \
  || { echo 'Ancestry copy failed (this bucket is requester-pays: BILLING_PROJECT must be set).' >&2; exit 1; }

# Check every copy: cloud copies can fail in quiet ways (cut short, a path
# that matched nothing). Two commands do it:
#   ls -lh          shows each file and its size
#   wc -l < FILE    counts the lines in FILE (one line per person / variant)
ls -lh lab_data/chr${CHROM}_hm3.* lab_data/ancestry_preds.tsv
n_samples=$(wc -l < "lab_data/chr${CHROM}_hm3.fam")
n_variants=$(wc -l < "lab_data/chr${CHROM}_hm3.bim")
echo "chr${CHROM}: $n_variants variants staged (people in file: ~$(( (n_samples + 50) / 100 * 100 )))."

# Look at two lines of each text file before using it. Different AoU
# resources use different ID conventions:
#   head -n 2 lab_data/chr${CHROM}_hm3.fam       # FID is 0; IID is the person ID
#   head -n 2 lab_data/chr${CHROM}_hm3.bim       # variant IDs are rsIDs
#   head -n 2 lab_data/ancestry_preds.tsv | cut -c1-200   # person ID is 'research_id'
printf 'Staged. Next: bash scripts/02_build_phenotype.sh\n'
