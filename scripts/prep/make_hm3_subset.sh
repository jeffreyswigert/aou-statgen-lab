#!/usr/bin/env bash
# =============================================================================
# prep/make_hm3_subset.sh -- INSTRUCTOR, once, before class.
# (Participants do not run this; step 01 copies its output.)
#
# What it makes: one chromosome of All of Us whole-genome genotypes,
# restricted to HapMap3 variants, with rsIDs as variant names:
#     $WORKSHOP_BUCKET/genotypes/chr22_hm3.{bed,bim,fam}
#
# Why it is needed: All of Us publishes whole-chromosome PLINK files (the
# "ACAF threshold" callset) but no HapMap3 subset. The chromosome-22 .bed
# alone is ~250 GB; the HapMap3 subset is ~2 GB, small enough for a class.
#
# Inputs:
#   1. The AoU ACAF PLINK files for one chromosome, from
#        $ACAF_DIR  (default below; requester-pays)
#      Their .bim names variants chr:pos:ref:alt (GRCh38 positions).
#   2. HM3_LIST: a tab-separated HapMap3 variant list with GRCh38
#      positions and a header line containing  rsid chr pos a1 a2
#      (LAB1_PREP.md says where to get one).
#
# Steps:
#   a. copy the small .bim and .fam; match HapMap3 variants to AoU IDs by
#      chromosome, position, and allele pair (either order)
#   b. copy the large .bed (needs ~300 GB free disk: create the VM with a
#      500 GB disk, the Workbench default)
#   c. plink2 --extract (keep matched variants), then --update-name
#      (rename chr:pos:ref:alt -> rsID) so rsID-keyed GWAS weights match
#   d. copy the three output files to the workshop bucket; delete the
#      large local copy
#
# Run:  HM3_LIST=hm3_hg38.tsv bash scripts/prep/make_hm3_subset.sh
# Runtime: dominated by step b (roughly 15-30 minutes for chr22).
# =============================================================================
source "$(dirname "$0")/../common.sh"
: "${HM3_LIST:?Set HM3_LIST to a HapMap3 list with GRCh38 positions (see LAB1_PREP.md)}"
: "${WORKSHOP_BUCKET:?Set WORKSHOP_BUCKET in config.sh}"
ACAF_DIR="${ACAF_DIR:-gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/acaf_threshold/plink_bed}"
OUT_URI="${OUT_URI:-${WORKSHOP_BUCKET%/}/genotypes}"
prep=lab_data/prep; mkdir -p "$prep"
gflags=(); [[ -z "${BILLING_PROJECT:-}" ]] || gflags=(--billing-project="$BILLING_PROJECT")

# The file-name stem in $ACAF_DIR has changed between releases
# (chr22.bim, acaf_threshold.chr22.bim), so find it from a listing.
bim_uri=$(gcloud "${gflags[@]}" storage ls "$ACAF_DIR/" | grep -E "(^|[/.])chr${CHROM}\.bim$" | head -n 1)
[[ -n "$bim_uri" ]] || { echo "No chr${CHROM}.bim under $ACAF_DIR" >&2; exit 1; }
stem_uri="${bim_uri%.bim}"
echo "Source: $stem_uri.{bed,bim,fam}"

# --- a. match HapMap3 variants to AoU variant IDs ----------------------------
gcloud "${gflags[@]}" storage cp "$stem_uri.bim" "$prep/acaf.bim"
gcloud "${gflags[@]}" storage cp "$stem_uri.fam" "$prep/acaf.fam"
python3 - "$HM3_LIST" "$prep" "$CHROM" <<'PY'
import sys, csv
hm3_path, prep, chrom = sys.argv[1], sys.argv[2], sys.argv[3]
want = {}                                      # (pos, {a1,a2}) -> rsid
with open(hm3_path) as f:
    for r in csv.DictReader(f, delimiter='\t'):
        if r['chr'].removeprefix('chr') == chrom:
            want[(r['pos'], frozenset((r['a1'].upper(), r['a2'].upper())))] = r['rsid']
seen, n = set(), 0
with open(f'{prep}/acaf.bim') as bim, open(f'{prep}/extract.txt', 'w') as ex, \
     open(f'{prep}/rename.txt', 'w') as rn:
    for line in bim:
        c, vid, _, pos, a1, a2 = line.split()
        rsid = want.get((pos, frozenset((a1.upper(), a2.upper()))))
        if rsid and rsid not in seen:          # one AoU variant per rsID
            seen.add(rsid); n += 1
            ex.write(vid + '\n'); rn.write(f'{vid}\t{rsid}\n')
print(f'HapMap3 variants on chr{chrom} in list: {len(want)}; matched in AoU .bim: {n}')
PY

# --- b. the large genotype file ----------------------------------------------
df -h lab_data
gcloud "${gflags[@]}" storage cp "$stem_uri.bed" "$prep/acaf.bed"

# --- c. subset, then rename ---------------------------------------------------
p2 --bfile "$prep/acaf" --extract "$prep/extract.txt" --make-bed --out "$prep/tmp_hm3"
p2 --bfile "$prep/tmp_hm3" --update-name "$prep/rename.txt" --make-bed \
   --out "lab_data/chr${CHROM}_hm3"
rm -f "$prep/acaf.bed" "$prep"/tmp_hm3.*
wc -l "lab_data/chr${CHROM}_hm3.bim"

# --- d. publish to the workshop bucket ---------------------------------------
for ext in bed bim fam; do
  gcloud "${gflags[@]}" storage cp "lab_data/chr${CHROM}_hm3.$ext" "$OUT_URI/"
done
gcloud "${gflags[@]}" storage ls -l "$OUT_URI/"
echo "Done. Participants' GENO_SRC should be $OUT_URI"
