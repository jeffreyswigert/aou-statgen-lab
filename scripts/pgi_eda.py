#!/usr/bin/env python3
"""QC on the PGI: a summary table and a histogram of the standardized PGI.

Run by 04_build_pgi.sh.

What this file does, in order:
  1. Reads the PLINK score file (one row per person) and the phenotype
     file.
  2. Joins them by person ID. The two files name the ID column
     differently:
       work/aou_pgi.sscore   column 'IID' (after a column 'FID' that is 0)
       work/aou_pheno.tsv    column 'person_id'
     The numbers are the same; only the labels differ. Rows are matched
     by the VALUE of the ID, never by row position: matching by position
     ("row 5 here is row 5 there") runs without error and pairs one
     person's score with another person's phenotype.
  3. Standardizes the PGI: PGI_z = (PGI - mean) / SD. Raw PGI units are
     arbitrary; after this, 1 means "one standard deviation above the
     sample mean". This is the same PGI_z that enters the regression.
  4. Writes a summary table and a histogram of PGI_z.

Outputs (aggregate only, so they go in results/):
  results/aou_pgi_summary.txt   join counts, summary statistics, correlation
  results/aou_pgi_hist.png      histogram of the standardized PGI

Printing rule as always: participant counts are rounded to the nearest
hundred; counts of 1-20 are never shown.
"""
import numpy as np
from pathlib import Path
import matplotlib
matplotlib.use('Agg')                   # "no screen here: draw to files"
import matplotlib.pyplot as plt


def read_table(path):
    """Read a tab-separated table. Returns (column names, list of rows),
    each row a list of text fields. lstrip('#') removes the # that PLINK
    puts at the start of its header line."""
    lines = Path(path).read_text().splitlines()
    header = lines[0].lstrip('#').split('\t')
    rows = []
    for line in lines[1:]:
        if line.strip():                # skip blank lines
            rows.append(line.split('\t'))
    return header, rows


def rounded(n):
    """A participant count as text: '<=20' for 1-20, else nearest hundred."""
    if 1 <= n <= 20:
        return '<=20 (suppressed)'
    return f'~{round(n, -2):,}'


# ---- Step 1: read both files into dicts keyed by person ID -----------------
score_header, score_rows = read_table('work/aou_pgi.sscore')
# Find the columns BY NAME. All of Us .fam files set FID to 0 for everyone,
# so PLINK's first column is '0' on every row; the person ID is in IID.
iid_col = score_header.index('IID')
sum_col = score_header.index('SCORE1_SUM')
score = {}                              # person ID -> raw PGI
for row in score_rows:
    score[row[iid_col]] = float(row[sum_col])
# (The one-line form: score = {r[iid_col]: float(r[sum_col]) for r in score_rows})

pheno_header, pheno_rows = read_table('work/aou_pheno.tsv')
pheno = {}                              # person ID -> the whole row
for row in pheno_rows:
    pheno[row[0]] = row                 # column 0 is person_id

# Which phenotype did step 02 build? (So the printout names it.)
meta = {}
for line in Path('work/pheno_meta.txt').read_text().splitlines():
    key, value = line.split('=', 1)
    meta[key] = value
label = meta.get('label', 'phenotype')

# ---- Step 2: the analysis set = people present in BOTH files ---------------
# set(score) is the set of IDs in the score file; & keeps the IDs that are
# in both sets. sorted() turns the set into an ordered list.
ids = sorted(set(score) & set(pheno))
if len(ids) == 0:
    raise SystemExit('No person IDs are in both files. Compare  head -n 2 work/aou_pgi.sscore'
                     '  with  head -n 2 work/aou_pheno.tsv : the ID columns must hold the same numbers.')
raw = np.array([score[i] for i in ids])         # raw PGI, in the order of ids

# ---- Step 3: standardize ---------------------------------------------------
pgi_z = (raw - raw.mean()) / raw.std()

# The phenotype's z, in the same order; nan where it is blank ('other' sex).
pheno_z_list = []
for i in ids:
    text = pheno[i][2]                  # column 2 is value_z
    if text:
        pheno_z_list.append(float(text))
    else:
        pheno_z_list.append(np.nan)
pheno_z = np.array(pheno_z_list)
has_z = np.isfinite(pheno_z)
if has_z.sum() > 2:
    r = np.corrcoef(pgi_z[has_z], pheno_z[has_z])[0, 1]     # the correlation coefficient
else:
    r = float('nan')

# ---- Step 4a: the summary table --------------------------------------------
percentiles = [1, 5, 25, 50, 75, 95, 99]
cutpoints = np.percentile(pgi_z, percentiles)
percentile_text = '  '.join(f'p{p}={c:+.2f}' for p, c in zip(percentiles, cutpoints))
out = ['QC on the PGI (aggregates only)', '',
       f'People scored by PLINK:        {rounded(len(score))}',
       f'People in the phenotype file:  {rounded(len(pheno))}',
       f'In both (analysis set):        {rounded(len(ids))}', '',
       f'Raw PGI (SCORE1_SUM):  mean {raw.mean():.4f}   SD {raw.std():.4f}',
       'Standardized PGI_z = (PGI - mean) / SD:  mean 0, SD 1 by construction', '',
       'PGI_z percentiles:  ' + percentile_text,
       f'PGI_z skewness {np.mean(pgi_z ** 3):+.2f} (normal: 0)   '
       f'kurtosis {np.mean(pgi_z ** 4):.2f} (normal: 3)', '',
       f'corr(PGI_z, {label} z) = {r:+.3f}', '',
       'This PGI uses one chromosome, so a small correlation is expected.']
if meta.get('id', 'height') != 'height':
    out += ['', 'NOTE: the posted weights are HEIGHT weights, but the phenotype is',
            f'{label}, so this correlation is CROSS-TRAIT (height PGI vs {label}),',
            'which is usually near zero. A real analysis uses weights for its',
            'own trait; the steps are identical.']

# ---- Step 4b: the histogram of PGI_z ---------------------------------------
# A standard normal curve is drawn on top for reference. density=True
# scales the bars so their total area is 1, which puts bars and curve on
# the same vertical scale.
fig, ax = plt.subplots(figsize=(7, 4.5))
ax.hist(pgi_z, bins=60, density=True, color='#990000', alpha=0.8, label='PGI_z')
grid = np.linspace(-4, 4, 300)
normal_curve = np.exp(-grid ** 2 / 2) / np.sqrt(2 * np.pi)
ax.plot(grid, normal_curve, color='#202124', lw=1.5, label='standard normal (reference)')
ax.set_xlim(-4.5, 4.5)
ax.set_xlabel('standardized PGI (SD units)')
ax.set_ylabel('density')
ax.set_title(f'Standardized PGI, analysis sample (n {rounded(len(ids))})')
ax.legend(frameon=False, fontsize=8)
fig.tight_layout()
fig.savefig('results/aou_pgi_hist.png', dpi=150)

out += ['', 'Figure: results/aou_pgi_hist.png (open from the JupyterLab file browser).']
Path('results/aou_pgi_summary.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))

# TRY IT: change bins=60 to bins=20 and re-run  bash scripts/04_build_pgi.sh
# (the scoring re-runs in seconds). Does the shape change, or only the detail?
