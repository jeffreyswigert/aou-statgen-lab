#!/usr/bin/env python3
"""QC on the PGI: a summary table and a histogram of the standardized PGI.

Run by 04_build_pgi.sh.

What this file does, in order:
  1. Reads the PLINK score file (one row per person) and the phenotype file.
  2. Joins them by person ID. The two files name the ID column differently:
       work/aou_pgi.sscore   column 'IID' (after a column 'FID' that is 0)
       work/aou_pheno.tsv    column 'person_id'
     The numbers are the same; only the column labels differ. We match rows
     by the VALUE of the ID -- never by row position. Matching by position
     ("row 5 here is row 5 there") runs without error and pairs one
     person's score with another person's phenotype.
  3. Standardizes the PGI: PGI_z = (PGI - mean) / SD. Raw PGI units are
     arbitrary; after this step, 1 means "one standard deviation above the
     sample mean". This is the same PGI_z that enters the regression.
  4. Writes a summary table and a histogram of PGI_z.

What to check in the histogram: a single, roughly bell-shaped hump
centered at 0. A PGI is a sum of many small contributions, so it is
usually close to normal. Two humps, a spike, or a long tail usually point
to a problem upstream (for example, a subset of people with many missing
genotypes, or a weight file with a few extreme weights).

Outputs (aggregate only, so they go in results/):
  results/aou_pgi_summary.txt   join counts, summary statistics, correlation
  results/aou_pgi_hist.png      histogram of the standardized PGI

Printing rule as always: shown counts are rounded to the nearest 100;
counts of 1-20 are never shown.
"""
import numpy as np
from pathlib import Path
import matplotlib
matplotlib.use('Agg')                   # "no screen here -- draw to files"
import matplotlib.pyplot as plt

def read_keyed(path):
    """Read a tab-separated table; return (column names, list of rows).
    lstrip('#') removes a leading # some tools put on their header line."""
    lines = Path(path).read_text().splitlines()
    header = lines[0].lstrip('#').split('\t')
    return header, [l.split('\t') for l in lines[1:] if l.strip()]

# Step 1: one dict per file, each keyed by the person's ID.
sh, srows = read_keyed('work/aou_pgi.sscore')
# Key on the IID column BY NAME. AoU .fam files set FID to 0 for everyone,
# so PLINK's first column is '0' on every row; the person ID is in IID.
score = {r[sh.index('IID')]: float(r[sh.index('SCORE1_SUM')]) for r in srows}
ph, prows = read_keyed('work/aou_pheno.tsv')
pheno = {r[0]: r for r in prows}

# Which phenotype did step 02 build? (So printouts name the right thing.)
meta = dict(l.split('=', 1) for l in Path('work/pheno_meta.txt').read_text().splitlines())
label = meta.get('label', 'phenotype')

# Step 2: the analysis set = people present in BOTH files.
# (set intersection: '&' keeps only IDs that appear in both collections.)
iids = sorted(set(score) & set(pheno))
if not iids:                           # zero matches: stop, do not plot nothing
    raise SystemExit('No person IDs are in both files. Compare  head -n 2 work/aou_pgi.sscore'
                     '  with  head -n 2 work/aou_pheno.tsv  -- the ID columns must hold the same numbers.')
raw = np.array([score[i] for i in iids])

# Step 3: standardize.
pgi_z = (raw - raw.mean()) / raw.std()

hz = np.array([float(pheno[i][2]) if pheno[i][2] else np.nan for i in iids])
ok = np.isfinite(hz)                       # rows where the phenotype z exists
r = np.corrcoef(pgi_z[ok], hz[ok])[0, 1] if ok.sum() > 2 else float('nan')

rounded = lambda n: '<=20 (suppressed)' if 1 <= n <= 20 else f'~{round(n, -2):,}'
pct = [1, 5, 25, 50, 75, 95, 99]
q = np.percentile(pgi_z, pct)

# Step 4a: the summary table.
out = ['QC on the PGI -- aggregates only', '',
       f'People scored by PLINK:        {rounded(len(score))}',
       f'People in the phenotype file:  {rounded(len(pheno))}',
       f'In both (analysis set):        {rounded(len(iids))}', '',
       f'Raw PGI (SCORE1_SUM):  mean {raw.mean():.4f}   SD {raw.std():.4f}',
       'Standardized PGI_z = (PGI - mean) / SD:  mean 0, SD 1 by construction', '',
       'PGI_z percentiles:  ' + '  '.join(f'p{p}={v:+.2f}' for p, v in zip(pct, q)),
       f'PGI_z skewness {np.mean(pgi_z**3):+.2f} (normal: 0)   '
       f'kurtosis {np.mean(pgi_z**4):.2f} (normal: 3)', '',
       f'corr(PGI_z, {label} z) = {r:+.3f}', '',
       'This PGI uses one chromosome, so a small correlation is expected.']
if meta.get('id', 'height') != 'height':
    out += ['', f'NOTE: the posted weights are HEIGHT weights, but the phenotype is',
            f'{label} -- so this correlation is CROSS-TRAIT (height PGI vs {label}),',
            'which is usually near zero. A real analysis uses weights for its',
            'own trait; the steps are identical.']

# Step 4b: the histogram of PGI_z, with a standard normal curve drawn on
# top for reference. density=True scales the bars so their total area is
# 1, which puts bars and curve on the same vertical scale.
fig, ax = plt.subplots(figsize=(7, 4.5))
ax.hist(pgi_z, bins=60, density=True, color='#990000', alpha=0.8, label='PGI_z')
grid = np.linspace(-4, 4, 300)
ax.plot(grid, np.exp(-grid**2 / 2) / np.sqrt(2 * np.pi), color='#202124', lw=1.5,
        label='standard normal (reference)')
ax.set_xlim(-4.5, 4.5)
ax.set_xlabel('standardized PGI (SD units)'); ax.set_ylabel('density')
ax.set_title(f'Standardized PGI, analysis sample (n {rounded(len(iids))})')
ax.legend(frameon=False, fontsize=8)
fig.tight_layout(); fig.savefig('results/aou_pgi_hist.png', dpi=150)

out += ['', 'Figure: results/aou_pgi_hist.png (open from the JupyterLab file browser).']
Path('results/aou_pgi_summary.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))

# TRY IT: change bins=60 to bins=20 and re-run  bash scripts/04_build_pgi.sh
# (the scoring re-runs in seconds). Does the shape change, or only the detail?
