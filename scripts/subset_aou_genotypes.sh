#!/usr/bin/env bash
# =============================================================================
# subset_aou_genotypes.sh -- from All of Us's whole-genome files, make a
# small PLINK file set: one chromosome, HapMap3 variants only, a 1-in-N
# sample of people, variants named by rsID.
#
# Run by 01_fetch_genotypes.sh when GENO_SOURCE=aou, and by the
# instructor's scripts/prep/make_hm3_subset.sh (with SAMPLE_MOD=1, to
# build the version everyone copies). You can also run it on its own.
#
# Why this exists: All of Us publishes its genotypes as one huge file set
# per chromosome (the "ACAF threshold" callset: every variant that passed
# an allele-frequency filter, for every sequenced person). It does not
# publish a HapMap3 subset. Most PGI weights are for HapMap3 variants and
# are keyed by rsID, and All of Us variants are named chr:pos:ref:alt. So
# a PGI project on All of Us starts with exactly this step: keep the
# variants you need, rename them so they match the weights.
#
# Inputs (settings from config.sh, each can be overridden for one run):
#   CHROM         which chromosome (22)
#   ACAF_FORMAT   which All of Us format to read: pgen (PLINK 2, compressed,
#                 smaller) or bed (PLINK 1, ~250 GB for chr22)
#   ACAF_DIR      where the All of Us files are. Either a gs:// folder (the
#                 file is copied to this VM first) or a local folder where
#                 the bucket is mounted (the file is read in place, and only
#                 the parts PLINK needs are fetched). Empty = the standard
#                 gs:// folder for ACAF_FORMAT.
#   HM3_LIST      a local HapMap3 variant list (rsid, chr, pos, a1, a2;
#                 GRCh38 positions). If unset, the repository's own
#                 data/hm3_chr22_hg38.tsv is used; for a chromosome with
#                 no list in data/, one is copied from HM3_LIST_URI.
#   SAMPLE_MOD    keep people whose ID divides evenly by this (1 =
#                 everyone, the default; 10 = about 1 in 10). The same rule step 02 uses for
#                 the phenotype, so the two files cover the same people.
#
# Output: lab_data/chr${CHROM}_hm3.bed / .bim / .fam
#
# Steps, in order (each is marked below):
#   a. find All of Us's files for this chromosome
#   b. copy the two small text files (variants, people)
#   c. match the HapMap3 list against the variant file: which All of Us
#      variants to keep, and what rsID each gets (scripts/make_hm3_lists.py)
#   d. the people to keep (the 1-in-N rule)
#   e. the genotype file itself: copy it, or read it where it is
#   f. PLINK: keep the listed variants and people, write PLINK 1 files
#   g. PLINK: rename the variants to rsIDs
#   h. clean up
# =============================================================================
source "$(dirname "$0")/common.sh"

# ---- Settings and their defaults -------------------------------------------
ACAF_FORMAT="${ACAF_FORMAT:-pgen}"
# The two formats use different file extensions and a different PLINK flag
# to load them. Setting four variables once here keeps every command below
# free of if/else. (case is bash's "which of these values is it".)
case "$ACAF_FORMAT" in
  pgen) subfolder=pgen;      var_ext=pvar; sample_ext=psam; geno_ext=pgen ;;
  bed)  subfolder=plink_bed; var_ext=bim;  sample_ext=fam;  geno_ext=bed ;;
  *)    echo "ACAF_FORMAT must be pgen or bed (got '$ACAF_FORMAT')" >&2; exit 1 ;;
esac
aou_root=gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/acaf_threshold
ACAF_DIR="${ACAF_DIR:-$aou_root/$subfolder}"
ACAF_DIR="${ACAF_DIR%/}"             # %/ removes one trailing slash, if any
# Is ACAF_DIR a cloud address or a local (mounted) folder? A cloud address
# starts with gs://. [[ ... == gs://* ]] is a pattern match: * means
# "anything after".
if [[ "$ACAF_DIR" == gs://* ]]; then in_cloud=yes; else in_cloud=no; fi
out_prefix="lab_data/chr${CHROM}_hm3"
tmp=lab_data/aou_tmp                 # scratch folder for the pieces
# Start with an empty scratch folder. Files copied from a mounted bucket
# arrive read-only, so leftovers from an earlier run could not be
# overwritten; rm -rf removes them (-r: the folder and its contents,
# -f: without asking, and without complaint if it is not there).
rm -rf "$tmp"
mkdir -p lab_data "$tmp"

# ---- The HapMap3 list ------------------------------------------------------
# Public reference data (rsID, chromosome, GRCh38 position, two alleles);
# no participant data. The repository carries the chromosome-22 list in
# data/ (source: README, "Where the genotypes come from"). For another
# chromosome, name a file with HM3_LIST or a gs:// address with HM3_LIST_URI.
if [[ -z "${HM3_LIST:-}" ]]; then
  HM3_LIST="data/hm3_chr${CHROM}_hg38.tsv"
  if [[ ! -s "$HM3_LIST" ]]; then         # -s: exists and is not empty
    HM3_LIST=lab_data/hm3_hg38.tsv
    : "${HM3_LIST_URI:?No data/hm3_chr${CHROM}_hg38.tsv. Set HM3_LIST to a local list, or HM3_LIST_URI}"
    echo "Copying the HapMap3 list from $HM3_LIST_URI ..."
    gcloud "${gflags[@]}" storage cp "$HM3_LIST_URI" "$HM3_LIST"
  fi
fi
head -n 2 "$HM3_LIST"                       # always look at a file before using it

# ---- a. find All of Us's files for this chromosome -------------------------
# The file names have differed between releases (chr22.pgen in one,
# acaf_threshold.chr22.pgen in another), and the variant file may be
# compressed (.pvar.zst). So instead of guessing a name, list the folder
# and pick the line that ends in chr22.pvar or chr22.pvar.zst.
if [[ "$in_cloud" == yes ]]; then
  listing=$(gcloud "${gflags[@]}" storage ls "$ACAF_DIR/")
else
  listing=$(ls -1 "$ACAF_DIR" | sed "s|^|$ACAF_DIR/|")    # full paths, one per line
fi
# grep -E finds lines matching a pattern. Read this one as: "chr22." at
# the start of the name or after a dot or slash, then the extension, then
# optionally .zst, then the end of the line ($).
var_file=$(grep -E "(^|[/.])chr${CHROM}\.${var_ext}(\.zst)?$" <<<"$listing" | head -n 1)
if [[ -z "$var_file" ]]; then
  echo "No chr${CHROM}.${var_ext} file found in $ACAF_DIR" >&2
  exit 1
fi
# The shared file-name stem: strip .zst (if present), then the extension.
stem="${var_file%.zst}"
stem="${stem%.$var_ext}"
echo "All of Us files: $stem.{$geno_ext,$var_ext,$sample_ext}"

# ---- b. the two small text files -------------------------------------------
# The variant file and the sample file are text and small enough to copy
# whatever ACAF_DIR is (a few hundred MB at most). The command to copy
# depends on where they are: gcloud for the cloud, cp for a local folder.
if [[ "$in_cloud" == yes ]]; then
  gcloud "${gflags[@]}" storage cp "$var_file" "$tmp/"
  gcloud "${gflags[@]}" storage cp "$stem.$sample_ext" "$tmp/acaf.$sample_ext"
else
  cp "$var_file" "$tmp/"
  cp "$stem.$sample_ext" "$tmp/acaf.$sample_ext"
fi
# Give the variant file the fixed name acaf.pvar (or acaf.bim), decompressing
# it if it arrived as .zst. basename is the file name without its folder.
local_var="$tmp/$(basename "$var_file")"
if [[ "$local_var" == *.zst ]]; then
  "$PLINK2" --zst-decompress "$local_var" > "$tmp/acaf.$var_ext"
  rm -f "$local_var"
else
  mv "$local_var" "$tmp/acaf.$var_ext"
fi
# Look at both files before using them, but print only what is safe to
# show on a shared screen: the sample file's column names (its rows are
# person IDs), and the first five columns of the first variants (a .pvar's
# sixth column, INFO, holds allele counts, some of them small).
# awk does the job of "grep | head" in one program: skip the ## comment
# lines, print three lines, stop. (With "grep ... | head -n 3" on a big
# file, head quits after three lines while grep is still writing, and
# "set -o pipefail" in common.sh treats that as a failure.)
head -n 1 "$tmp/acaf.$sample_ext"
awk -F'\t' -v OFS='\t' '!/^##/ { print $1, $2, $3, $4, $5; if (++n == 3) exit }' "$tmp/acaf.$var_ext"

# ---- c. and d. the lists: which variants, which names, which people --------
# A Python script does the matching (it is easier to read than the same
# logic in awk). It writes three files into $tmp:
#   extract.txt   All of Us variant IDs (chr22:pos:ref:alt) that are on
#                 the HapMap3 list
#   rename.txt    two columns: that ID, and the rsID it becomes
#   keep.txt      the person IDs to keep (the 1-in-N rule)
python3 scripts/make_hm3_lists.py \
  --hm3 "$HM3_LIST" --variants "$tmp/acaf.$var_ext" --samples "$tmp/acaf.$sample_ext" \
  --chrom "$CHROM" --sample-mod "$SAMPLE_MOD" --out-dir "$tmp"

# ---- e. the genotype file --------------------------------------------------
# This is the large one. Two cases:
#   in the cloud   copy it to this VM's disk first (check the disk has
#                  room: df shows free space, ls -l shows the file size)
#   mounted        leave it where it is; PLINK reads it through the mount
#                  and fetches only the parts it needs
if [[ "$in_cloud" == yes ]]; then
  df -h lab_data
  gcloud "${gflags[@]}" storage ls -l "$stem.$geno_ext"
  echo "Copy started $(date +%H:%M:%S)"
  gcloud "${gflags[@]}" storage cp "$stem.$geno_ext" "$tmp/acaf.$geno_ext"
  echo "Copy finished $(date +%H:%M:%S)"
  geno_file="$tmp/acaf.$geno_ext"
else
  ls -lh "$stem.$geno_ext"
  geno_file="$stem.$geno_ext"
fi

# ---- f. PLINK: keep the listed variants and people -------------------------
# PLINK 2 can be told each of the three input files by name:
#   --pgen/--pvar/--psam  (PLINK 2 format)   or   --bed/--bim/--fam
# so the genotype file can be wherever it is while the small files are in
# $tmp. Then:
#   --set-all-var-ids 'chr@:#:$r:$a'   name every variant chr22:pos:ref:alt
#                                      (@ = chromosome, # = position,
#                                      $r/$a = the two alleles). The
#                                      All of Us IDs already look like
#                                      this; setting them ourselves means
#                                      the names in extract.txt match
#                                      exactly, whatever the file had.
#   --new-id-max-allele-len 1000       do not refuse long indel alleles
#   --extract FILE                     keep only the variants listed
#   --keep FILE                        keep only the people listed
#   --make-bed                         write PLINK 1 files (.bed/.bim/.fam)
#   --out PREFIX                       name for the output files
echo "PLINK subset started $(date +%H:%M:%S)"
if [[ "$ACAF_FORMAT" == pgen ]]; then
  p2 --pgen "$geno_file" --pvar "$tmp/acaf.pvar" --psam "$tmp/acaf.psam" \
     --set-all-var-ids 'chr@:#:$r:$a' --new-id-max-allele-len 1000 \
     --extract "$tmp/extract.txt" --keep "$tmp/keep.txt" \
     --make-bed --out "$tmp/hm3_aouids"
else
  p2 --bed "$geno_file" --bim "$tmp/acaf.bim" --fam "$tmp/acaf.fam" \
     --set-all-var-ids 'chr@:#:$r:$a' --new-id-max-allele-len 1000 \
     --extract "$tmp/extract.txt" --keep "$tmp/keep.txt" \
     --make-bed --out "$tmp/hm3_aouids"
fi

# ---- g. PLINK: rename the variants to rsIDs ---------------------------------
#   --update-name FILE   two columns per line: old ID, new ID
# After this the .bim carries rsIDs, so an rsID-keyed weights file matches.
p2 --bfile "$tmp/hm3_aouids" --update-name "$tmp/rename.txt" \
   --make-bed --out "$out_prefix"
echo "PLINK finished $(date +%H:%M:%S)"

# ---- h. clean up -------------------------------------------------------------
# Remove the large copy (if one was made) and the intermediate file set.
# The three small lists stay in $tmp so you can look at them.
rm -f "$tmp/acaf.$geno_ext" "$tmp"/hm3_aouids.*
echo "Wrote $out_prefix.bed/.bim/.fam: $(wc -l < "$out_prefix.bim") variants."
head -n 2 "$out_prefix.bim"
