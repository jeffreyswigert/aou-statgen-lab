#!/usr/bin/env bash
# =============================================================================
# prep/make_hm3_subset.sh -- INSTRUCTOR, once, before class.
# (Participants do not run this; step 01 copies its output.)
#
# What it makes: one chromosome of All of Us whole-genome genotypes,
# restricted to HapMap3 variants, with rsIDs as variant names:
#     $WORKSHOP_BUCKET/genotypes/chr22_hm3.{bed,bim,fam}
#
# Where the pieces come from:
#   * The genotypes: All of Us's own v9 "ACAF threshold" callset, one file
#     set per chromosome, in the controlled bucket (requester-pays):
#       .../v9/wgs/short_read/snpindel/acaf_threshold/pgen/        (default)
#       .../v9/wgs/short_read/snpindel/acaf_threshold/plink_bed/   (ACAF_FORMAT=bed)
#     All of Us publishes no HapMap3 subset, which is why this script exists.
#     The PGEN files are compressed and much smaller than the .bed files
#     (chr22 .bed is ~250 GB), so PGEN is the default.
#   * The HapMap3 variant LIST (no genotypes, public reference data):
#     HM3_LIST, tab-separated with a header containing  rsid chr pos a1 a2,
#     positions on GRCh38. LAB1_PREP.md says where to get one.
#
# Steps:
#   a. copy the variant file (.pvar / .bim) and sample file; match HapMap3
#      variants by chromosome, position, and allele pair (either order)
#   b. copy the genotype file (.pgen / .bed); create the VM with a 500 GB
#      disk (the Workbench default)
#   c. plink2: name every variant chr:pos:ref:alt, keep the matched ones,
#      write PLINK 1 files; then rename them to rsIDs so rsID-keyed GWAS
#      weights match
#   d. copy the three output files to the workshop bucket; delete the
#      large local copy
#
# Run:  HM3_LIST=hm3_hg38.tsv bash scripts/prep/make_hm3_subset.sh
# Run with autostop set longer than the job (or off): the copy in step b
# waits on the network and can look idle to autostop.
# =============================================================================
source "$(dirname "$0")/../common.sh"
: "${HM3_LIST:?Set HM3_LIST to a HapMap3 list with GRCh38 positions (see LAB1_PREP.md)}"
: "${WORKSHOP_BUCKET:?Set WORKSHOP_BUCKET in config.sh}"
ACAF_FORMAT="${ACAF_FORMAT:-pgen}"                  # pgen or bed
case "$ACAF_FORMAT" in
  pgen) sub=pgen;      varext=pvar; smpext=psam; genext=pgen; load=--pfile ;;
  bed)  sub=plink_bed; varext=bim;  smpext=fam;  genext=bed;  load=--bfile ;;
  *) echo "ACAF_FORMAT must be pgen or bed" >&2; exit 1 ;;
esac
ACAF_DIR="${ACAF_DIR:-gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/acaf_threshold/$sub}"
OUT_URI="${OUT_URI:-${WORKSHOP_BUCKET%/}/genotypes}"
prep=lab_data/prep; mkdir -p "$prep"
gflags=(); [[ -z "${BILLING_PROJECT:-}" ]] || gflags=(--billing-project="$BILLING_PROJECT")

# The file-name stem has differed between releases (chr22.*,
# acaf_threshold.chr22.*), and a .pvar may be compressed (.pvar.zst), so
# find the variant file from a listing.
var_uri=$(gcloud "${gflags[@]}" storage ls "$ACAF_DIR/" | grep -E "(^|[/.])chr${CHROM}\.${varext}(\.zst)?$" | head -n 1)
[[ -n "$var_uri" ]] || { echo "No chr${CHROM}.${varext} under $ACAF_DIR" >&2; exit 1; }
stem_uri="${var_uri%.zst}"; stem_uri="${stem_uri%.$varext}"
echo "Source: $stem_uri.{$genext,$varext,$smpext}"

# --- a. match HapMap3 variants ----------------------------------------------
gcloud "${gflags[@]}" storage cp "$var_uri" "$prep/"
gcloud "${gflags[@]}" storage cp "$stem_uri.$smpext" "$prep/acaf.$smpext"
local_var="$prep/$(basename "$var_uri")"
if [[ "$local_var" == *.zst ]]; then
  "$PLINK2" --zst-decompress "$local_var" > "$prep/acaf.$varext"; rm -f "$local_var"
elif [[ "$local_var" != "$prep/acaf.$varext" ]]; then
  mv "$local_var" "$prep/acaf.$varext"
fi
python3 - "$HM3_LIST" "$prep" "$CHROM" "$varext" <<'PY'
import sys, csv
hm3_path, prep, chrom, varext = sys.argv[1:5]
want = {}                                      # (pos, {a1,a2}) -> rsid
with open(hm3_path) as f:
    for r in csv.DictReader(f, delimiter='\t'):
        if r['chr'].removeprefix('chr') == chrom:
            want[(r['pos'], frozenset((r['a1'].upper(), r['a2'].upper())))] = r['rsid']
seen, n = set(), 0
with open(f'{prep}/acaf.{varext}') as vf, open(f'{prep}/extract.txt', 'w') as ex, \
     open(f'{prep}/rename.txt', 'w') as rn:
    for line in vf:
        if line.startswith('#'):
            continue                           # .pvar header lines
        f = line.split()
        if varext == 'bim':                    # chr id cM pos a1(alt) a2(ref)
            c, pos, ref, alt = f[0], f[3], f[5], f[4]
        else:                                  # #CHROM POS ID REF ALT ...
            c, pos, ref, alt = f[0], f[1], f[3], f[4]
        if ',' in alt:
            continue                           # multiallelic: skip
        rsid = want.get((pos, frozenset((ref.upper(), alt.upper()))))
        if rsid and rsid not in seen:          # one AoU variant per rsID
            seen.add(rsid); n += 1
            vid = f"chr{c.removeprefix('chr')}:{pos}:{ref}:{alt}"  # = plink2's ID below
            ex.write(vid + '\n'); rn.write(f'{vid}\t{rsid}\n')
print(f'HapMap3 variants on chr{chrom} in list: {len(want)}; matched in AoU file: {n}')
PY

# --- b. the large genotype file ----------------------------------------------
df -h lab_data
gcloud "${gflags[@]}" storage ls -l "$stem_uri.$genext"
gcloud "${gflags[@]}" storage cp "$stem_uri.$genext" "$prep/acaf.$genext"

# --- c. name, subset, convert; then rename to rsIDs ---------------------------
# 'chr@' writes chr22 whether the file says 22 or chr22.
p2 $load "$prep/acaf" --set-all-var-ids 'chr@:#:$r:$a' --new-id-max-allele-len 1000 \
   --extract "$prep/extract.txt" --make-bed --out "$prep/tmp_hm3"
p2 --bfile "$prep/tmp_hm3" --update-name "$prep/rename.txt" --make-bed \
   --out "lab_data/chr${CHROM}_hm3"
rm -f "$prep/acaf.$genext" "$prep"/tmp_hm3.*
wc -l "lab_data/chr${CHROM}_hm3.bim"

# --- d. publish to the workshop bucket ---------------------------------------
for ext in bed bim fam; do
  gcloud "${gflags[@]}" storage cp "lab_data/chr${CHROM}_hm3.$ext" "$OUT_URI/"
done
gcloud "${gflags[@]}" storage ls -l "$OUT_URI/"
echo "Done. Participants' GENO_SRC should be $OUT_URI"
