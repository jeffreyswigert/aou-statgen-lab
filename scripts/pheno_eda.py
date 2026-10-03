#!/usr/bin/env python3
"""Explore the phenotype: a summary table and two figures.

Run by 03_explore_phenotype.sh. Works for whichever phenotype step 02
built (it reads work/pheno_meta.txt to learn the variable's name).

Reads work/aou_pheno.tsv (person-level). Writes AGGREGATE outputs to results/:
  aou_pheno_summary.txt    the tables described below
  aou_pheno_hist.png       a histogram
  aou_pheno_kde_sex.png    smooth density curves, one per sex
Open the .png files by double-clicking them in the JupyterLab file browser.

THE TABLES
  * Block 1: one row per group (everyone, Male, Female, other; then age)
    with the number of observations, the mean, the standard deviation,
    and the 25th, 50th, and 75th percentiles. Percentiles rather than the
    minimum and maximum, because a minimum or maximum is ONE
    participant's exact value, and printed output here holds only
    aggregates. (Obs is rounded to the nearest hundred for the same
    reason.)
  * Block 2: the percentile ladder (1% ... 99%), variance, skewness, and
    kurtosis. Skewness 0 and kurtosis 3 describe a symmetric bell curve
    (this is the convention where a normal distribution scores 3; some
    software subtracts 3 and reports 0).

What to look for: a plausible center and spread for the variable
(height, US adults: about 176 cm for men and 162 cm for women, SD 7-8 cm),
and whether the two sex curves are shifted copies of each other, which
is why height is standardized within sex.

About the code: numpy holds a whole column of numbers in one ARRAY and
does arithmetic on all of them at once (v.mean(), v - v.mean()). The
same could be written with Python lists and a loop; numpy is shorter and
much faster on hundreds of thousands of rows. matplotlib draws the
figures.
"""
import numpy as np
from pathlib import Path
import matplotlib
matplotlib.use('Agg')                   # "no screen here: draw to files"
import matplotlib.pyplot as plt

# ---- Which phenotype is this? ----------------------------------------------
# Step 02 wrote a small key=value file. Read it into a dict.
meta = {}
for line in Path('work/pheno_meta.txt').read_text().splitlines():
    key, value = line.split('=', 1)     # split at the FIRST = only
    meta[key] = value
label = meta.get('label', 'value')
unit = meta.get('unit', '')
if unit:
    name = f'{label} ({unit})'
else:
    name = label

# ---- Read the phenotype table ----------------------------------------------
# Row layout (from step 02): person_id  value  value_z  age  sex
values = []
sexes = []
ages = []
lines = Path('work/aou_pheno.tsv').read_text().splitlines()
for line in lines[1:]:                  # [1:] skips the header line
    fields = line.split('\t')
    values.append(float(fields[1]))
    sexes.append(fields[4])
    if fields[3]:
        ages.append(float(fields[3]))
    else:
        ages.append(np.nan)             # nan = "not a number", numpy's missing value
v = np.array(values)                    # the whole column as one numpy array
sex = np.array(sexes)
age = np.array(ages)


def rounded(n):
    """A participant count as text: '<=20' for 1-20, else nearest hundred."""
    if 1 <= n <= 20:
        return '<=20'
    return f'~{round(n, -2):,}'         # the , inserts thousands separators


# ---- Block 1: the summary table ---------------------------------------------
def summary_row(rowname, x):
    """One table row: Obs (rounded), mean, SD, p25, median, p75.
    x.std(ddof=1) is the sample SD (divides by n-1); np.percentile gives
    the requested percentiles. The format codes (>10.2f) mean: right-
    aligned in 10 characters, 2 decimal places."""
    p25, p50, p75 = np.percentile(x, [25, 50, 75])
    return (f'{rowname:>13} | {rounded(len(x)):>9}  {x.mean():>10.2f}  {x.std(ddof=1):>10.2f}'
            f'  {p25:>9.1f}  {p50:>9.1f}  {p75:>9.1f}')


header = (f'{"Variable":>13} | {"Obs":>9}  {"Mean":>10}  {"Std. dev.":>10}'
          f'  {"p25":>9}  {"Median":>9}  {"p75":>9}')
bar = '-' * 14 + '+' + '-' * (len(header) - 15)
out = [f'Phenotype exploration: {name}. Aggregates only; the person-level file stays in the workspace.',
       '', 'Summary (percentiles shown in place of min and max: an extreme is one person\'s value):',
       '', header, bar, summary_row(meta.get('id', 'value')[:13], v)]
for s in ('Male', 'Female', 'other'):
    in_group = (sex == s)               # a True/False array, one entry per row
    if in_group.sum() > 20:             # .sum() counts the Trues
        out.append(summary_row(s, v[in_group]))     # v[in_group] keeps those rows
    else:
        out.append(f'{s:>13} | {rounded(int(in_group.sum())):>9}  -- too few to display separately')
has_age = np.isfinite(age)              # True where age is not nan
if has_age.sum() > 20:
    out.append(summary_row('age', age[has_age]))

# ---- Block 2: percentiles and shape ------------------------------------------
z = (v - v.mean()) / v.std()
percentiles = [1, 5, 10, 25, 50, 75, 90, 95, 99]
cutpoints = np.percentile(v, percentiles)
out += ['', f'Detail, {label}:', '', f'{"Percentiles":>18}', bar[:34]]
for p, cut in zip(percentiles, cutpoints):
    out.append(f'{p:>10}%  {cut:>12.1f}')
# Skewness is the mean of z cubed; kurtosis the mean of z to the fourth.
out += ['', f'{"Variance":>12}  {v.var(ddof=1):>12.2f}',
        f'{"Skewness":>12}  {np.mean(z ** 3):>12.2f}',
        f'{"Kurtosis":>12}  {np.mean(z ** 4):>12.2f}',
        '', 'Check: is each mean in the expected range for this variable, and is the SD?',
        '(Height, US adults: about 176 cm men, 162 cm women; SD 7-8 cm.)']
Path('results/aou_pheno_summary.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))

# ---- Figure 1: histogram -----------------------------------------------------
# Chop the range into 60 equal bins and draw a bar for the number of
# people in each. The bin count is a choice (see TRY IT below).
fig, ax = plt.subplots(figsize=(7, 4.5))
ax.hist(v, bins=60, color='#990000', alpha=0.8)
ax.set_xlabel(name)
ax.set_ylabel('people')
ax.set_title(f'{label}, analysis sample (n {rounded(len(v))})')
fig.tight_layout()
fig.savefig('results/aou_pheno_hist.png', dpi=150)


# ---- Figure 2: kernel density, one curve per sex -----------------------------
# A kernel density is a SMOOTHED histogram. The recipe: put a small bell
# curve on top of every observation, then add them all up. The width of
# those small bells (the bandwidth, bw) sets the smoothing: too wide blurs
# real features away, too narrow invents wiggles. The formula for bw is a
# standard default, not a law. (Libraries such as scipy or seaborn have a
# ready-made version; this one is written out so you can see the recipe.)
def kde(x, grid):
    bw = 1.06 * x.std() * len(x) ** (-1 / 5)         # TRY IT: halve it, double it
    density = np.zeros(len(grid))
    for point in x:                                    # one small bell per observation
        density += np.exp(-0.5 * ((grid - point) / bw) ** 2)
    return density / (len(x) * bw * np.sqrt(2 * np.pi))


grid = np.linspace(v.min(), v.max(), 300)              # 300 evenly spaced x positions
fig, ax = plt.subplots(figsize=(7, 4.5))
for s, color in (('Male', '#666666'), ('Female', '#990000')):
    in_group = (sex == s)
    if in_group.sum() > 20:
        ax.plot(grid, kde(v[in_group], grid), color=color, lw=2,
                label=f'{s} (n {rounded(int(in_group.sum()))})')
ax.set_xlabel(name)
ax.set_ylabel('density')
ax.set_title(f'{label} by recorded sex')
ax.legend(frameon=False)
fig.tight_layout()
fig.savefig('results/aou_pheno_kde_sex.png', dpi=150)
print('Figures: results/aou_pheno_hist.png, results/aou_pheno_kde_sex.png '
      '(open from the JupyterLab file browser).')
print('Next: bash scripts/04_build_pgi.sh')

# TRY IT: change bins=60 to bins=15, then to bins=300, and re-run
#     bash scripts/03_explore_phenotype.sh
# What does each version hide or invent? Then do the whole detour with a
# different variable:  PHENO=ldl bash scripts/02_build_phenotype.sh  and
# re-run this step. The tables and figures follow the switch.
