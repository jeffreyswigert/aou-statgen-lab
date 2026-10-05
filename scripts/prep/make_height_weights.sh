#!/usr/bin/env bash
# =============================================================================
# prep/make_height_weights.sh -- INSTRUCTOR, once, before class.
#
# Turns a PGS Catalog scoring file into the three-column weights file that
# step 4 reads, keeps only the variants in our genotype subset, and posts
# it to the workshop bucket:
#     $WORKSHOP_BUCKET/pgi_workshop/height_weights.txt
#     rsid    effect_allele    weight
#
# The weights used for the workshop: PGS Catalog score PGS002802, the
# multi-ancestry height weights of Yengo et al. (2022), "A saturated map of
# common genetic variants associated with human height", Nature,
# doi:10.1038/s41586-022-05275-y. Public; cite the paper and the PGS
# Catalog when you use it.
#
# Run, after step 1 has put lab_data/chr22_hm3.bim on the VM:
#     curl -O https://ftp.ebi.ac.uk/pub/databases/spot/pgs/scores/PGS002802/ScoringFiles/Harmonized/PGS002802_hmPOS_GRCh38.txt.gz
#     bash scripts/prep/make_height_weights.sh PGS002802_hmPOS_GRCh38.txt.gz
#
# A PGS Catalog scoring file is tab-separated text: comment lines starting
# with #, one line of column names, then one line per variant. The columns
# are found by name, so any PGS Catalog score with rsIDs works. Where the
# harmonized column hm_rsID is present and filled, it is used in place of
# rsID (it holds the variant's current rsID).
# =============================================================================
source "$(dirname "$0")/../common.sh"
scoring_file="${1:?Give the PGS Catalog scoring file, for example PGS002802_hmPOS_GRCh38.txt.gz}"
: "${WORKSHOP_BUCKET:?Set WORKSHOP_BUCKET in config.sh}"
bim="lab_data/chr${CHROM}_hm3.bim"
if [[ ! -s "$bim" ]]; then
  echo "No $bim. Run scripts/01_fetch_genotypes.sh first." >&2
  exit 1
fi
out=lab_data/height_weights.txt

python3 - "$scoring_file" "$bim" "$out" <<'EOF'
import gzip
import sys

scoring_path, bim_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

# The rsIDs in our genotype subset (.bim column 2).
ours = set()
with open(bim_path) as f:
    for line in f:
        ours.add(line.split()[1])

# gzip.open reads a .gz file as text without unpacking it to disk first.
if scoring_path.endswith('.gz'):
    f = gzip.open(scoring_path, 'rt')
else:
    f = open(scoring_path)

columns = None
n_rows = 0
n_kept = 0
seen = set()
with f, open(out_path, 'w') as out:
    out.write('rsid\teffect_allele\tweight\n')
    for line in f:
        if line.startswith('#'):
            continue                                # comment lines
        fields = line.rstrip('\n').split('\t')
        if columns is None:                         # the line of column names
            columns = {name: i for i, name in enumerate(fields)}
            for needed in ('rsID', 'effect_allele', 'effect_weight'):
                if needed not in columns:
                    raise SystemExit(f'No column {needed} in {scoring_path}; columns are {fields}')
            continue
        n_rows += 1
        rsid = fields[columns['rsID']]
        if 'hm_rsID' in columns and fields[columns['hm_rsID']].startswith('rs'):
            rsid = fields[columns['hm_rsID']]
        if rsid in ours and rsid not in seen:
            seen.add(rsid)
            n_kept += 1
            out.write(f"{rsid}\t{fields[columns['effect_allele']]}\t{fields[columns['effect_weight']]}\n")

print(f'Variants in the scoring file:             {n_rows:,}')
print(f'Variants in our genotype subset:          {len(ours):,}')
print(f'In both (rows written to {out_path}): {n_kept:,}')
if n_kept == 0:
    raise SystemExit('No rsIDs matched. Is this the right scoring file?')
EOF

head -n 3 "$out"
dest="${WORKSHOP_BUCKET%/}/pgi_workshop/height_weights.txt"
gcloud "${gflags[@]}" storage cp "$out" "$dest"
gcloud "${gflags[@]}" storage ls -l "$dest"
echo "Done. Step 4 reads $dest (WEIGHTS_URI in config.sh, the default)."
echo "Now run: bash scripts/04_build_pgi.sh   and write down 'variants processed'."
