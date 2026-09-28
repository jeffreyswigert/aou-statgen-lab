#!/usr/bin/env python3
"""Explore the phenotype: Stata-style summary tables and two figures.

Run by 03_explore_phenotype.sh. Works for whichever phenotype step 02
built (it reads results/pheno_meta.txt to learn the variable's name).

Writes to results/:
  aou_pheno_summary.txt    the tables described below
  aou_pheno_hist.png       a histogram
  aou_pheno_kde_sex.png    smooth density curves, one per sex

Open the .png files by double-clicking them in the JupyterLab file browser.

THE TABLES -- shaped like Stata on purpose, since many of you live there:
  * The first block mirrors `summarize`: one row per group, with Obs,
    Mean, Std. dev. -- except where Stata would print Min and Max, we
    print percentiles (p25 / Median / p75). Why the swap: a minimum or
    maximum is ONE participant's exact value, and this lab's rule is that
    printed output contains only aggregates. (Obs is rounded to the
    nearest 100 for the same reason.)
  * The second block mirrors `summarize, detail`: the percentile ladder
    (1% ... 99%), Variance, Skewness, and Kurtosis -- again minus the
    "smallest/largest four values" columns Stata shows, which are
    individual people. Kurtosis is Stata-style (a normal bell curve
    scores 3).

What to actually LOOK for: a plausible center and spread for the variable
(the handout gives reference ranges); spikes or a second bump, which
usually mean a construction problem upstream (mixed units, duplicated
records), not a discovery; and whether the two sex curves are shifted
copies -- which is why height standardizes within sex.
"""
import numpy as np                      # numpy = fast math on whole columns
from pathlib import Path
import matplotlib
matplotlib.use('Agg')                   # "no screen here -- draw to files"
import matplotlib.pyplot as plt

# Which phenotype is this? Step 02 wrote a small key=value file.
meta = dict(l.split('=', 1) for l in Path('results/pheno_meta.txt').read_text().splitlines())
label = meta.get('label', 'value')
unit = meta.get('unit', '')
name = f'{label} ({unit})' if unit else label

# Read the phenotype table. Row layout (from step 02):
#   person_id  value  value_z  age  sex
rows = [l.split('\t') for l in Path('results/aou_pheno.tsv').read_text().splitlines()[1:]]
v = np.array([float(r[1]) for r in rows])            # all values, one array
sex = np.array([r[4] for r in rows])                 # matching sex labels
age = np.array([float(r[3]) if r[3] else np.nan for r in rows])  # nan = missing

rounded = lambda n: '<=20' if 1 <= n <= 20 else f'~{round(n, -2):,}'

# ---- Block 1: the `summarize`-style table ----------------------------------
def sum_row(rowname, x):
    """One table row: Obs (rounded), Mean, SD, p25, Median, p75."""
    q = np.percentile(x, [25, 50, 75])
    return (f'{rowname:>13} | {rounded(len(x)):>9}  {x.mean():>10.2f}  {x.std(ddof=1):>10.2f}'
            f'  {q[0]:>9.1f}  {q[1]:>9.1f}  {q[2]:>9.1f}')

hdr = (f'{"Variable":>13} | {"Obs":>9}  {"Mean":>10}  {"Std. dev.":>10}'
       f'  {"p25":>9}  {"Median":>9}  {"p75":>9}')
bar = '-' * 14 + '+' + '-' * (len(hdr) - 15)
out = [f'Phenotype exploration: {name} -- aggregates only; the person-level file stays in the workspace',
       '', "Summary (Stata `summarize`-style; Obs rounded to the nearest 100, and",
       "percentiles shown where Stata prints Min/Max -- an extreme is one person's value):",
       '', hdr, bar, sum_row(label[:13], v)]
for s in ('Male', 'Female', 'other'):
    m = sex == s
    out.append(sum_row(s, v[m]) if m.sum() > 20 else
               f'{s:>13} | {rounded(int(m.sum())):>9}  -- too few to display separately')
if np.isfinite(age).sum() > 20:
    out.append(sum_row('age', age[np.isfinite(age)]))

# ---- Block 2: the `summarize, detail`-style panel --------------------------
# Percentile ladder plus the shape numbers. Skewness ~0 and kurtosis ~3
# describe a symmetric bell curve; big departures say "look at the picture".
z = (v - v.mean()) / v.std()
pcts = np.percentile(v, [1, 5, 10, 25, 50, 75, 90, 95, 99])
pairs = list(zip([1, 5, 10, 25, 50, 75, 90, 95, 99], pcts))
out += ['', f'Detail (`summarize, detail`-style), {label}:', '',
        f'{"Percentiles":>18}', bar[:34]]
out += [f'{p:>10}%  {val:>12.1f}' for p, val in pairs]
out += ['', f'{"Variance":>12}  {v.var(ddof=1):>12.2f}',
        f'{"Skewness":>12}  {np.mean(z**3):>12.2f}',
        f'{"Kurtosis":>12}  {np.mean(z**4):>12.2f}',
        '', 'Questions worth a minute: are the group means plausible (the handout has',
        'reference ranges)? Is the SD? Would a spike or second bump implicate a',
        'concept or unit choice upstream?']
Path('results/aou_pheno_summary.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))

# --- Figure 1: histogram. Chop the range into 60 equal "bins" and draw a
# bar showing how many people land in each. Simple and honest -- but the
# bin count is a choice (see TRY IT below).
fig, ax = plt.subplots(figsize=(7, 4.5))
ax.hist(v, bins=60, color='#990000', alpha=0.8)
ax.set_xlabel(name); ax.set_ylabel('people')
ax.set_title(f'{label}, analysis sample (n {rounded(len(v))})')
fig.tight_layout(); fig.savefig('results/aou_pheno_hist.png', dpi=150)

# --- Figure 2: kernel density -- a SMOOTHED histogram. The recipe: put a
# tiny bell curve on top of every single observation, then add them all
# up. The width of those tiny bells (the "bandwidth" bw) controls the
# smoothing: too wide blurs real features away, too narrow invents wiggly
# fake ones. The formula below is a standard default, not a law.
def kde(x, grid):
    bw = 1.06 * x.std() * len(x) ** (-1 / 5)         # TRY IT: halve / double
    return np.exp(-0.5 * ((grid[:, None] - x) / bw) ** 2).sum(1) / (len(x) * bw * np.sqrt(2 * np.pi))

grid = np.linspace(v.min(), v.max(), 300)            # 300 evenly spaced x's
fig, ax = plt.subplots(figsize=(7, 4.5))
for s, color in (('Male', '#666666'), ('Female', '#990000')):
    m = sex == s
    if m.sum() > 20:
        ax.plot(grid, kde(v[m], grid), color=color, lw=2, label=f'{s} (n {rounded(int(m.sum()))})')
ax.set_xlabel(name); ax.set_ylabel('density')
ax.set_title(f'{label} by recorded sex')
ax.legend(frameon=False)
fig.tight_layout(); fig.savefig('results/aou_pheno_kde_sex.png', dpi=150)
print('Figures: results/aou_pheno_hist.png, results/aou_pheno_kde_sex.png '
      '(open from the JupyterLab file browser).')
print('Next: bash scripts/04_build_pgi.sh')

# TRY IT: change bins=60 to bins=15, then to bins=300, and re-run
#     bash scripts/03_explore_phenotype.sh
# What does each version hide or invent? Then walk the whole detour with a
# different variable:  PHENO=ldl bash scripts/02_build_phenotype.sh  and
# re-run this step -- the tables and figures follow the switch.
