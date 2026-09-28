#!/usr/bin/env python3
"""Explore the real phenotype: summary statistics and two figures.

Run by 03_explore_phenotype.sh.

Writes to results/:
  aou_pheno_summary.txt    the numbers: N, mean, SD, quartiles -- overall
                           and per sex group
  aou_height_hist.png      a histogram of height
  aou_height_kde_sex.png   smooth density curves, one per sex

Open the .png files by double-clicking them in the JupyterLab file browser.

What to actually LOOK for:
  * Plausible center and spread? US-cohort height means sit near 176 cm
    (male) and 162 cm (female), SD roughly 7-8. Far off -> suspect units
    or concept choice, not biology.
  * Spikes or a second bump? Those usually mean a construction problem
    upstream (mixed units, duplicated records), not a discovery.
  * The two sex curves are two shifted bell shapes -- which is exactly why
    the phenotype was standardized within sex in step 02.

Printing rule, as everywhere in this lab: group sizes are rounded to the
nearest 100 and counts of 1-20 are never shown (dissemination policy).
"""
import numpy as np                      # numpy = fast math on whole columns
from pathlib import Path
import matplotlib
matplotlib.use('Agg')                   # "no screen here -- draw to files"
import matplotlib.pyplot as plt

# Read the phenotype table. Row layout (from step 02):
#   person_id  height_cm  height_z  age  sex
rows = [l.split('\t') for l in Path('results/aou_pheno.tsv').read_text().splitlines()[1:]]
h = np.array([float(r[1]) for r in rows])            # all heights, one array
sex = np.array([r[4] for r in rows])                 # matching sex labels
age = np.array([float(r[3]) if r[3] else np.nan for r in rows])  # nan = missing

rounded = lambda n: '<=20 (suppressed)' if 1 <= n <= 20 else f'~{round(n, -2):,}'

def block(name, x):
    """One summary line: n, mean, SD, and the quartiles (the values that
    cut the data at 25% / 50% / 75% -- the middle one is the median)."""
    q = np.percentile(x, [25, 50, 75])
    return (f'  {name:<22} n={rounded(len(x)):<12} mean={x.mean():7.2f}  sd={x.std():6.2f}  '
            f'IQR {q[0]:.1f} / {q[1]:.1f} / {q[2]:.1f}')

out = ['Phenotype exploration -- aggregates only; the person-level file stays in the workspace', '',
       'Height (as recorded; sandbox rehearsal shows standardized practice values):',
       block('everyone', h)]
for s in ('Male', 'Female', 'other'):
    m = sex == s                # m = a column of True/False; h[m] = that group
    out.append(block(s, h[m]) if m.sum() > 20 else
               f'  {s:<22} n={rounded(int(m.sum()))} -- too few to display separately')
if np.isfinite(age).sum() > 20:
    out += ['', block('age (years)', age[np.isfinite(age)])]
out += ['', 'Questions worth a minute: are the sex-specific means plausible for a US',
        'cohort? Is the SD? What would a spike or a second bump tell you about the',
        'concept or unit choices upstream?']
Path('results/aou_pheno_summary.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))

# --- Figure 1: histogram. Chop the height range into 60 equal "bins" and
# draw a bar showing how many people land in each. Simple and honest --
# but the bin count is a choice (see TRY IT below).
fig, ax = plt.subplots(figsize=(7, 4.5))
ax.hist(h, bins=60, color='#990000', alpha=0.8)
ax.set_xlabel('height (as recorded)'); ax.set_ylabel('people')
ax.set_title(f'Height, analysis sample (n {rounded(len(h))})')
fig.tight_layout(); fig.savefig('results/aou_height_hist.png', dpi=150)

# --- Figure 2: kernel density -- a SMOOTHED histogram. The recipe: put a
# tiny bell curve on top of every single observation, then add them all
# up. The width of those tiny bells (the "bandwidth" bw) controls the
# smoothing: too wide blurs real features away, too narrow invents wiggly
# fake ones. The formula below is a standard default, not a law.
def kde(x, grid):
    bw = 1.06 * x.std() * len(x) ** (-1 / 5)         # TRY IT: halve / double
    return np.exp(-0.5 * ((grid[:, None] - x) / bw) ** 2).sum(1) / (len(x) * bw * np.sqrt(2 * np.pi))

grid = np.linspace(h.min(), h.max(), 300)            # 300 evenly spaced x's
fig, ax = plt.subplots(figsize=(7, 4.5))
for s, color in (('Male', '#666666'), ('Female', '#990000')):
    m = sex == s
    if m.sum() > 20:
        ax.plot(grid, kde(h[m], grid), color=color, lw=2, label=f'{s} (n {rounded(int(m.sum()))})')
ax.set_xlabel('height (as recorded)'); ax.set_ylabel('density')
ax.set_title('Height by recorded sex: why height standardizes within sex')
ax.legend(frameon=False)
fig.tight_layout(); fig.savefig('results/aou_height_kde_sex.png', dpi=150)
print('Figures: results/aou_height_hist.png, results/aou_height_kde_sex.png '
      '(open from the JupyterLab file browser).')
print('Next: bash scripts/04_build_pgi.sh')

# TRY IT: change bins=60 to bins=15, then to bins=300, and re-run
#     bash scripts/03_explore_phenotype.sh
# What does each version hide or invent? On real data, also notice that
# histogram bars are COUNTS -- a nearly-empty bin is a small count on
# display, which is why figures get a human look before sharing.
