#!/usr/bin/env bash
# =============================================================================
# prep/make_hm3_subset.sh -- INSTRUCTOR, once, before class.
#
# Builds the ready-made HapMap3 subset that participants copy in step 1
# (GENO_SOURCE=bucket), and posts it to the workshop bucket:
#     $WORKSHOP_BUCKET/genotypes/chr22_hm3.{bed,bim,fam}
#
# The actual work is scripts/subset_aou_genotypes.sh, the same script
# participants run in aou mode. This wrapper only sets SAMPLE_MOD=1 (the
# posted subset holds everyone; a participant's own SAMPLE_MOD is applied
# by step 02's query, and the joins take the people in both files) and uploads
# the result.
#
# Run (the HapMap3 list is the repository's data/hm3_chr22_hg38.tsv):
#     bash scripts/prep/make_hm3_subset.sh
# Optional: ACAF_FORMAT=bed, ACAF_DIR=<mounted folder>, HM3_LIST=<your list>.
# If the file has to be copied (ACAF_DIR not mounted), create the VM with a
# 500 GB disk and set autostop longer than the copy: the copy waits on
# the network and can look idle to autostop.
# =============================================================================
source "$(dirname "$0")/../common.sh"
: "${WORKSHOP_BUCKET:?Set WORKSHOP_BUCKET in config.sh}"
dest="${OUT_URI:-${WORKSHOP_BUCKET%/}/genotypes}"

SAMPLE_MOD=1 bash scripts/subset_aou_genotypes.sh

for ext in bed bim fam; do
  gcloud "${gflags[@]}" storage cp "lab_data/chr${CHROM}_hm3.$ext" "$dest/"
done
gcloud "${gflags[@]}" storage ls -l "$dest/"
echo "Done. Participants' config: GENO_SOURCE=bucket, GENO_SRC=$dest (the default)."
