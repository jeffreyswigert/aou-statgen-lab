#!/usr/bin/env bash
# =============================================================================
# prep/make_hm3_subset.sh -- INSTRUCTOR, once, before class.
#
# Builds the ready-made HapMap3 subset that participants copy in step 1
# (GENO_SOURCE=bucket), and posts it plus the HapMap3 list to the workshop
# bucket:
#     $WORKSHOP_BUCKET/genotypes/chr22_hm3.{bed,bim,fam}
#     $WORKSHOP_BUCKET/genotypes/hm3_hg38.tsv
#
# The actual work is scripts/subset_aou_genotypes.sh, the same script
# participants run in aou mode. This wrapper only sets SAMPLE_MOD=1 (the
# posted subset holds everyone; the 1-in-N rule is applied later by step
# 02's query, and the joins take the people in both files) and uploads
# the result.
#
# Run, with a local HapMap3 list (LAB1_PREP.md says where to get one):
#     HM3_LIST=hm3_hg38.tsv bash scripts/prep/make_hm3_subset.sh
# Optional: ACAF_FORMAT=bed, ACAF_DIR=<mounted folder>, CHROM=21.
# If the file has to be copied (ACAF_DIR not mounted), create the VM with a
# 500 GB disk and set autostop longer than the copy: the copy waits on
# the network and can look idle to autostop.
# =============================================================================
source "$(dirname "$0")/../common.sh"
: "${HM3_LIST:?Set HM3_LIST to a local HapMap3 list with GRCh38 positions (see LAB1_PREP.md)}"
: "${WORKSHOP_BUCKET:?Set WORKSHOP_BUCKET in config.sh}"
dest="${OUT_URI:-${WORKSHOP_BUCKET%/}/genotypes}"

SAMPLE_MOD=1 HM3_LIST="$HM3_LIST" bash scripts/subset_aou_genotypes.sh

for ext in bed bim fam; do
  gcloud "${gflags[@]}" storage cp "lab_data/chr${CHROM}_hm3.$ext" "$dest/"
done
gcloud "${gflags[@]}" storage cp "$HM3_LIST" "$dest/hm3_hg38.tsv"
gcloud "${gflags[@]}" storage ls -l "$dest/"
echo "Done. Participants' config: GENO_SOURCE=bucket, GENO_SRC=$dest (the default)."
