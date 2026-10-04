#!/usr/bin/env bash
# =============================================================================
# 01_fetch_genotypes.sh -- put one chromosome of genotypes, and the ancestry
# file, on this VM's disk.
#
# The idea: genotype files live in cloud storage (addresses that start
# with gs://). PLINK can only read ordinary files on this computer's disk,
# so the first step of any genotype analysis is getting the files here.
#
# What ends up in lab_data/ (git ignores this folder):
#   chr22_hm3.bed / .bim / .fam    one chromosome of All of Us genotypes,
#                                  HapMap3 variants only, named by rsID.
#                                  Three files that travel together:
#                                    .bed  the genotypes (binary; never
#                                          open it as text)
#                                    .bim  one line per variant
#                                    .fam  one line per person
#   ancestry_preds.tsv             All of Us's genetic-ancestry predictions
#                                  and principal components, one line per
#                                  person (the regression uses the PCs).
#
# Two ways to get the genotype files, chosen by GENO_SOURCE in config.sh:
#   bucket   copy a ready-made subset from the workshop bucket (the
#            instructor built it before class). Three small copies.
#   aou      build the subset yourself from All of Us's own chromosome
#            file, as you would for your own project. This runs
#            scripts/subset_aou_genotypes.sh; read that file for the steps.
# Either way the output files are the same, and every later step is the
# same.
# =============================================================================
source "$(dirname "$0")/common.sh"
mkdir -p lab_data

# ---- The genotype files ----------------------------------------------------
# GENO_SOURCE is a setting in config.sh. ${GENO_SOURCE:-bucket} means "use
# GENO_SOURCE, or 'bucket' if it is not set".
if [[ "${GENO_SOURCE:-bucket}" == aou ]]; then

  echo "Building the chr${CHROM} HapMap3 subset from All of Us's own files ..."
  bash scripts/subset_aou_genotypes.sh

else

  echo "Copying the chr${CHROM} HapMap3 subset from $GENO_SRC ..."
  # A for-loop: the three lines inside run once with ext=bed, once with
  # ext=bim, once with ext=fam. Writing the copy three times would work
  # too; the loop makes it impossible to copy two and forget the third.
  #   gcloud storage cp SOURCE DESTINATION     copy one file
  #   "${gflags[@]}"                            the billing flag from
  #                                             common.sh (empty if unset)
  # Whatever the files are called in the bucket ($GENO_STEM), the copies
  # are named chr22_hm3.* here, so every later step finds them.
  for ext in bed bim fam; do
    if ! gcloud "${gflags[@]}" storage cp "$GENO_SRC/$GENO_STEM.$ext" "lab_data/chr${CHROM}_hm3.$ext"; then
      echo "Copy failed. Check GENO_SRC and BILLING_PROJECT in config.sh." >&2
      exit 1
    fi
  done

fi

# ---- The ancestry file -----------------------------------------------------
# This one comes straight from the All of Us controlled bucket, which is
# requester-pays: the copy is refused unless the billing flag names who
# pays. (The flag goes BEFORE "storage": it is a setting for gcloud as a
# whole, not for the cp command.)
echo "Copying ancestry predictions from $ANC_SRC ..."
if ! gcloud "${gflags[@]}" storage cp "$ANC_SRC" "lab_data/ancestry_preds.tsv"; then
  echo 'Ancestry copy failed. This bucket is requester-pays: BILLING_PROJECT must be set in config.sh.' >&2
  exit 1
fi

# ---- Check what arrived ----------------------------------------------------
# Cloud copies can fail quietly (cut short, or a path that matched
# nothing). Two commands tell you what you actually have:
#   ls -lh FILES     each file with its size (h = human units)
#   wc -l < FILE     the number of lines in FILE (one line per person in
#                    the .fam, one per variant in the .bim). The < feeds
#                    the file in so that wc prints only the number.
ls -lh lab_data/chr${CHROM}_hm3.* lab_data/ancestry_preds.tsv
n_variants=$(wc -l < "lab_data/chr${CHROM}_hm3.bim")
n_people=$(wc -l < "lab_data/chr${CHROM}_hm3.fam")
# The count of people is printed exactly, or rounded to the nearest
# hundred with COUNTS=rounded in config.sh (scripts/counts.py explains
# the two). Arithmetic in bash goes inside $(( ... )).
n_people_rounded=$(( (n_people + 50) / 100 * 100 ))
if [[ "${COUNTS:-exact}" == exact ]] && (( n_people > 20 )); then
  people_text="$n_people"
elif (( n_people_rounded == 0 )); then
  people_text="under 100"
else
  people_text="about $n_people_rounded"
fi
echo "chr${CHROM}: $n_variants variants staged; $people_text people in the file."

# Look at the first lines of each text file before using it. Different
# All of Us resources name the person ID differently:
#   head -n 2 lab_data/chr${CHROM}_hm3.fam       # column 1 (FID) is 0; column 2 (IID) is the person ID
#   head -n 2 lab_data/chr${CHROM}_hm3.bim       # column 2 is the variant ID (an rsID here)
#   head -n 1 lab_data/ancestry_preds.tsv | tr '\t' '\n'    # the header, one column name per line
printf 'Staged. Next: bash scripts/02_build_phenotype.sh\n'
