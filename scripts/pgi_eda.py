#!/usr/bin/env python3
"""Look at the PGI before modeling with it: a table and one figure.

Run by 04_build_pgi.sh.

This file's real lesson is JOINS. We combine three files, and each one
names its person-ID column differently:
  results/aou_pgi.sscore        column '#IID'
  results/aou_pheno.tsv         column 'person_id'
  lab_data/ancestry_preds.tsv   column 'research_id'
Same underlying ID numbers, three different labels. Match rows by the
VALUE of the ID -- never by the column's name, and never by "row 5 here
should be row 5 there". Position-based matching is the silent killer: it
runs fine and attaches one person's score to another person's height.

Outputs:
  results/aou_pgi_summary.txt        how many joined, plus correlation
  results/aou_pgi_kde_ancestry.png   PGI density curves by predicted
                                     genetic ancestry

Printing rule as always: shown group sizes are rounded to the nearest 100;
groups of 1-20 people are not drawn at all.
"""
import numpy as np
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def read_keyed(path):
    """Read a tab-separated table; return (column names, list of rows).
    lstrip('#') removes a leading # some tools put on their header line."""
    lines = Path(path).read_text().splitlines()
    header = lines[0].lstrip('#').split('\t')
    return header, [l.split('\t') for l in lines[1:] if l.strip()]

# Build one dict per file, each keyed by the person's ID (see docstring).
sh, srows = read_keyed('results/aou_pgi.sscore')
score = {r[0]: float(r[sh.index('SCORE1_SUM')]) for r in srows}
ph, prows = read_keyed('results/aou_pheno.tsv')
pheno = {r[0]: r for r in prows}
ah, arows = read_keyed('lab_data/ancestry_preds.tsv')
anc = {r[0]: r[1] for r in arows}          # ID -> predicted ancestry label

# Which phenotype did step 02 build? (So printouts name the right thing.)
meta = dict(l.split('=', 1) for l in Path('results/pheno_meta.txt').read_text().splitlines())
label = meta.get('label', 'phenotype')

# The analysis set = people present in BOTH the scores and the phenotype.
# (set intersection: '&' keeps only IDs that appear in both collections.)
iids = sorted(set(score) & set(pheno))
pgi = np.array([score[i] for i in iids])

# Standardize the PGI: subtract the mean, divide by the standard
# deviation. Raw score units are arbitrary; after this, "1" means "one
# standard deviation above this sample's average", which humans can read.
pgi = (pgi - pgi.mean()) / pgi.std()

hz = np.array([float(pheno[i][2]) if pheno[i][2] else np.nan for i in iids])
ancv = np.array([anc.get(i, 'unknown') for i in iids])

rounded = lambda n: '<=20 (suppressed)' if 1 <= n <= 20 else f'~{round(n, -2):,}'
ok = np.isfinite(hz)                       # rows where height_z exists
r = np.corrcoef(pgi[ok], hz[ok])[0, 1] if ok.sum() > 2 else float('nan')

out = ['PGI exploration -- aggregates only', '',
       f'People scored:                 {rounded(len(score))}',
       f'People in the phenotype file:  {rounded(len(pheno))}',
       f'Joined analysis set (both):    {rounded(len(iids))}',
       '(three files, three ID labels -- #IID, person_id, research_id --',
       ' one underlying ID. Joined on the value, checked, never assumed.)', '',
       f'corr(PGI, {label} z)            = {r:+.3f}',
       '',
       'A one-chromosome PGI is deliberately partial, so expect a modest',
       'correlation. What matters: you built it on real data, counted every',
       'match and every join, and can read the figure below honestly.']
if meta.get('id', 'height') != 'height':
    out += ['', f'NOTE: the posted weights are HEIGHT weights, but the phenotype is',
            f'{label} -- so this correlation is CROSS-TRAIT (height PGI vs {label}),',
            'which is usually near zero. A real analysis fetches weights for its',
            'own trait; the mechanics you are practicing are identical.']

# --- The figure: PGI density curves by predicted genetic ancestry.
# (kde = smoothed histogram; see pheno_eda.py for the full explanation.)
def kde(x, grid):
    bw = 1.06 * x.std() * len(x) ** (-1 / 5)
    return np.exp(-0.5 * ((grid[:, None] - x) / bw) ** 2).sum(1) / (len(x) * bw * np.sqrt(2 * np.pi))

grid = np.linspace(pgi.min() - .5, pgi.max() + .5, 300)
fig, ax = plt.subplots(figsize=(7.5, 4.5))
palette = ['#990000', '#666666', '#C89B00', '#3B6FA0', '#5E8C61', '#8B5E83']
drawn = []
for k, g in enumerate(sorted(set(ancv))):
    m = ancv == g
    if m.sum() > 20 and pgi[m].std() > 0:   # small groups: never drawn
        ax.plot(grid, kde(pgi[m], grid), lw=2, color=palette[k % 6],
                label=f'{g} (n {rounded(int(m.sum()))})')
        drawn.append(g)
ax.set_xlabel('PGI (sample SD units)'); ax.set_ylabel('density')
ax.set_title('PGI by predicted genetic ancestry')
ax.legend(frameon=False, fontsize=8)
fig.tight_layout(); fig.savefig('results/aou_pgi_kde_ancestry.png', dpi=150)

# How to read that figure honestly -- two facts that must ALWAYS travel
# together, spelled out because this is the most misread figure in the
# field:
out += ['', f'Figure: results/aou_pgi_kde_ancestry.png (groups drawn: {", ".join(drawn) or "none"}).',
        'Fact 1: differences between the curves reflect allele frequencies',
        'and the discovery study behind the weights at least as much as any',
        'biology. Fact 2: the PGI also PREDICTS less accurately for groups',
        'far from the discovery sample (portability). Say both facts, every',
        'time. These labels are statistical predictions from genotypes --',
        'not race, not ethnicity, not a quality score.']
Path('results/aou_pgi_summary.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))
