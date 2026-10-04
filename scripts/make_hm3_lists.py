#!/usr/bin/env python3
"""Match a HapMap3 variant list against an All of Us variant file, and pick
the people to keep. Writes three small text files for PLINK.

Run by scripts/subset_aou_genotypes.sh. Usage:
    python3 scripts/make_hm3_lists.py --hm3 hm3_hg38.tsv \
        --variants acaf.pvar --samples acaf.psam --chrom 22 \
        --sample-mod 10 --out-dir lab_data/aou_tmp

Inputs
  --hm3        the HapMap3 list: tab-separated, with a header line naming
               the columns rsid, chr, pos, a1, a2. Positions on GRCh38.
  --variants   All of Us's variant file for one chromosome: a .pvar
               (columns #CHROM POS ID REF ALT, after any ## comment lines)
               or a .bim (columns chr id cM pos a1 a2, no header)
  --samples    All of Us's sample file: a .psam (header line starts with #,
               has an IID column) or a .fam (no header; IID is column 2)
  --chrom      which chromosome the variant file holds (22)
  --sample-mod keep people whose ID divides evenly by this (1 = everyone)

Outputs, in --out-dir
  extract.txt  one All of Us variant ID per line (chr22:pos:ref:alt) that
               matches a HapMap3 variant; PLINK's --extract reads it
  rename.txt   two columns: that ID, then the rsID; PLINK's --update-name
  keep.txt     one person ID per line (header #IID); PLINK's --keep

How the matching works. All of Us names variants chr22:pos:ref:alt, and
the HapMap3 list names them by rsID. The two can only be matched on what
they share: the position and the pair of alleles. So the HapMap3 list is
turned into a lookup table keyed by (position, allele pair), and each
All of Us variant is looked up in it. The allele pair is stored as a SET,
so that {A, G} and {G, A} count as the same pair: which allele a list
calls "a1" is a convention that differs between sources.

Why Python rather than a one-line awk command: the logic has three
special cases (comment lines, allele order, multiallelic sites), and a
file you can read top to bottom is easier to check than a dense
one-liner. The same job in R or pandas would look much the same.
"""
import argparse
import csv
import os

parser = argparse.ArgumentParser()
parser.add_argument('--hm3', required=True)
parser.add_argument('--variants', required=True)
parser.add_argument('--samples', required=True)
parser.add_argument('--chrom', required=True)
parser.add_argument('--sample-mod', type=int, default=1)
parser.add_argument('--out-dir', required=True)
args = parser.parse_args()

# ---- 1. Read the HapMap3 list into a lookup table --------------------------
# wanted[(position, {allele1, allele2})] = rsid
# A DICT is Python's lookup table: put a value in under a key, get it back
# by that key. frozenset makes an unordered, unchangeable set that can be
# used as part of a key. (A plain set cannot be a dict key.)
wanted = {}
with open(args.hm3) as f:
    for row in csv.DictReader(f, delimiter='\t'):   # each row becomes a dict keyed by the header
        chrom = row['chr']
        if chrom.startswith('chr'):              # accept "22" and "chr22"
            chrom = chrom[3:]
        if chrom != args.chrom:
            continue                             # a different chromosome: skip this row
        alleles = frozenset([row['a1'].upper(), row['a2'].upper()])
        wanted[(row['pos'], alleles)] = row['rsid']
print(f'HapMap3 variants on chr{args.chrom} in the list: {len(wanted)}')

# ---- 2. Walk the All of Us variant file, keeping the matches ---------------
is_bim = args.variants.endswith('.bim')
n_matched = 0
n_multiallelic = 0
rsids_used = set()          # so that one rsID is never given to two variants
extract = open(os.path.join(args.out_dir, 'extract.txt'), 'w')
rename = open(os.path.join(args.out_dir, 'rename.txt'), 'w')
with open(args.variants) as f:
    for line in f:
        if line.startswith('#'):
            continue                             # .pvar header and comment lines
        fields = line.split()
        if is_bim:
            # .bim columns: chr, id, cM, pos, allele1 (alt), allele2 (ref)
            chrom, pos, ref, alt = fields[0], fields[3], fields[5], fields[4]
        else:
            # .pvar columns: #CHROM, POS, ID, REF, ALT
            chrom, pos, ref, alt = fields[0], fields[1], fields[3], fields[4]
        if ',' in alt:
            # More than one alternate allele at this position (multiallelic).
            # PGI weights assume two alleles, so these are skipped.
            n_multiallelic += 1
            continue
        if chrom.startswith('chr'):
            chrom = chrom[3:]
        rsid = wanted.get((pos, frozenset([ref.upper(), alt.upper()])))
        if rsid is None:
            continue                             # not a HapMap3 variant
        if rsid in rsids_used:
            continue                             # a second All of Us variant for the same rsID
        rsids_used.add(rsid)
        n_matched += 1
        # The ID PLINK will give this variant (--set-all-var-ids 'chr@:#:$r:$a').
        variant_id = f'chr{chrom}:{pos}:{ref}:{alt}'
        extract.write(variant_id + '\n')
        rename.write(f'{variant_id}\t{rsid}\n')
extract.close()
rename.close()
print(f'Matched in the All of Us file: {n_matched}  (multiallelic sites skipped: {n_multiallelic})')
if n_matched == 0:
    raise SystemExit('No matches. Are the HapMap3 positions on GRCh38, and are the columns named rsid chr pos a1 a2?')

# ---- 3. The people to keep -------------------------------------------------
# Find the person-ID column. A .psam has a header line (starting with #)
# that names it IID; a .fam has no header, and IID is the second column.
is_fam = args.samples.endswith('.fam')
n_people = 0
n_kept = 0
with open(args.samples) as f, open(os.path.join(args.out_dir, 'keep.txt'), 'w') as keep:
    keep.write('#IID\n')                         # PLINK reads this header
    iid_column = 1                               # .fam default (columns count from 0)
    for line in f:
        if line.startswith('##'):
            continue                             # comment lines
        fields = line.split()
        if line.startswith('#'):
            # The .psam header: find which column is IID.
            names = [name.lstrip('#') for name in fields]
            iid_column = names.index('IID')
            continue
        person_id = fields[iid_column]
        n_people += 1
        # The same 1-in-N rule as the phenotype query: MOD(person_id, N) = 0.
        # Python's % is the remainder after division, like SQL's MOD.
        if int(person_id) % args.sample_mod == 0:
            keep.write(person_id + '\n')
            n_kept += 1
# Printed counts are rounded to the nearest hundred unless COUNTS=exact
# (config.sh): these are participant counts, and this printout could end
# up in a shared terminal log.
def about(n):
    """A count as text: exact with COUNTS=exact, else the nearest hundred."""
    if os.environ.get('COUNTS', 'rounded') == 'exact' and n > 20:
        return f'{n:,}'
    if round(n, -2) == 0:
        return 'under 100'
    return f'about {round(n, -2):,}'

print(f'People in the file: {about(n_people)}; kept (1 in {args.sample_mod}): {about(n_kept)}')
