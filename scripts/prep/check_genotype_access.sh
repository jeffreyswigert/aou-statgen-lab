#!/usr/bin/env bash
# =============================================================================
# prep/check_genotype_access.sh -- INSTRUCTOR, in a real workspace: answer
# "can participants pull the genotypes from All of Us themselves in class?"
#
# It reads nothing person-level and prints only file sizes and paths:
#   1. the size of All of Us's chromosome files (PGEN and PLINK 1 .bed), so
#      we know what a full copy would cost in time and disk;
#   2. whether the controlled dataset bucket is mounted under ~/workspace/
#      (Cloud Storage FUSE), which would let plink2 read it in place.
#
# Run:  bash scripts/prep/check_genotype_access.sh
# Then, if a mounted folder is found, time an in-place build:
#   time ACAF_DIR=<that folder> bash scripts/prep/make_hm3_subset.sh
# =============================================================================
source "$(dirname "$0")/../common.sh"
set +e
gflags=(); [[ -z "${BILLING_PROJECT:-}" ]] || gflags=(--billing-project="$BILLING_PROJECT")
base=gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/acaf_threshold

echo "== 1. chr${CHROM} file sizes in the All of Us controlled bucket"
for sub in pgen plink_bed; do
  echo "-- $base/$sub/"
  gcloud "${gflags[@]}" storage ls -l "$base/$sub/" 2>&1 | grep -E "chr${CHROM}\\.|ERROR" \
    | awk '{ if ($1 ~ /^[0-9]+$/) printf "   %8.1f GB  %s\n", $1/1e9, $3; else print "   " $0 }'
done
df -h . | awk 'NR==1 || NR==2 {print "   " $0}'

echo
echo "== 2. Is the controlled dataset mounted under ~/workspace/ ?"
ls -1 ~/workspace 2>/dev/null | sed 's/^/   ~\/workspace\//' || echo "   ~/workspace does not exist"
# Try the usual place first (the mount holds one folder per release: v7, v8,
# v9, ...). Searching a mounted bucket with find is slow, so that is only
# the fallback.
hits=""
for d in ~/workspace/*/v9/wgs/short_read/snpindel/acaf_threshold/pgen; do
  if [[ -d "$d" ]]; then hits="$d"; break; fi
done
if [[ -z "$hits" ]]; then
  echo "   Not at the usual path; searching ~/workspace (can take several minutes) ..."
  hits=$(find -L ~/workspace -maxdepth 9 -type d -path '*acaf_threshold/pgen' 2>/dev/null | head -n 3)
fi
if [[ -n "$hits" ]]; then
  echo "   Found mounted ACAF PGEN folder(s):"; sed 's/^/     /' <<<"$hits"
  first=$(head -n 1 <<<"$hits")
  echo "   chr${CHROM} files there:"; ls -lh "$first" | grep "chr${CHROM}\\." | sed 's/^/     /'
  echo
  echo "Next: time an in-place build (reads only the HapMap3 variants):"
  echo "  time ACAF_DIR=\"$first\" bash scripts/prep/make_hm3_subset.sh"
else
  echo "   No mounted acaf_threshold/pgen folder found (searched 9 levels deep)."
  echo "   If the All of Us data collection is not added to this workspace, adding it"
  echo "   should mount it (Verily docs: 'Access workspace files and folders from"
  echo "   your cloud environment'). Otherwise the build has to copy the full file."
fi
