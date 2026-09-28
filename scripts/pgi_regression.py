#!/usr/bin/env python3
"""A basic regression incorporating the PGI (the lab's capstone).

Run by 05_pgi_regression.sh.

THE MODEL
    phenotype_z = a + b*PGI + c*age + d*female + (five PC terms) + noise

(The outcome is whichever phenotype step 02 built -- height by default;
the printout names it. If you switched PHENO to another variable, remember
the posted weights are HEIGHT weights, so b becomes a cross-trait
association -- the output will say so.)

Regression, in one paragraph: we assume each person's height is roughly a
weighted mix of their predictors plus random noise, and we ask "which
weights (coefficients) make that assumption fit the data best?" The
computer solves that directly; the science is in choosing the predictors
and reading the answer honestly.

Where each predictor comes from, and why it is in the model:
  PGI       from step 04, standardized here to mean 0 / SD 1 -- so the
            headline coefficient b reads "SDs of outcome per SD of PGI".
  age, sex  from the phenotype file. Basic demographics; where the
            outcome was standardized within sex (height, weight),
            'female' mops up any remainder.
  PC1..PC5  "principal components": five numbers per person that
            summarize broad genetic ancestry patterns. Why include them?
            Both allele frequencies AND environments differ across
            ancestral backgrounds, and the PGI carries some of that. The
            PCs absorb part of it so b is less contaminated by structure.
            They come from All of Us's ancestry file -- where they are
            stored as ONE bracketed text string per person ("[-0.009,
            0.015, ...]") that we must split apart ourselves. Real files
            are like this; read them before trusting them.

WHAT WE REPORT
  * the coefficient table: each estimate with its SE (standard error --
    the estimate's uncertainty) and t (estimate / SE; roughly, |t| > 2
    means "hard to explain by chance alone").
  * R-squared: the share of height variation the predictors explain.
  * INCREMENTAL R-squared: R2 with the PGI minus R2 without it -- what the
    PGI ADDS beyond the ordinary covariates. Report this one; the PGI's
    R2 alone flatters it, because the PGI overlaps with the PCs.

HONEST LABELS (printed with the results)
  Association, not cause. One chromosome, not a full index. And plain OLS
  assumes unrelated people -- with relatives in the sample, a real study
  needs family-aware methods.

Printing rule: shown Ns rounded to the nearest 100; 1-20 never shown.

TRY IT: in the COVARS line below, delete the five PC names and re-run
    bash scripts/05_pgi_regression.sh
Watch the PGI coefficient move. That movement IS population structure --
the cheapest demonstration of why the PCs belong in the model.
"""
import numpy as np
from pathlib import Path

COVARS = ['age', 'female'] + [f'PC{i}' for i in range(1, 6)]

def read_keyed(path):
    """Tab-separated table -> (column names, rows); '#' stripped off header."""
    lines = Path(path).read_text().splitlines()
    h = lines[0].lstrip('#').split('\t')
    return h, [l.split('\t') for l in lines[1:] if l.strip()]

# The same three files as step 04, joined the same safe way: by ID value.
sh, srows = read_keyed('results/aou_pgi.sscore')
score = {r[0]: float(r[sh.index('SCORE1_SUM')]) for r in srows}
ph, prows = read_keyed('results/aou_pheno.tsv')
pheno = {r[0]: r for r in prows}
ah, arows = read_keyed('lab_data/ancestry_preds.tsv')
ai = ah.index('pca_features')
meta = dict(l.split('=', 1) for l in Path('results/pheno_meta.txt').read_text().splitlines())
label = meta.get('label', 'phenotype')
# Unpack the bracketed PC string: strip the [ ], split on commas, keep the
# first five numbers.
pcs = {r[0]: [float(x) for x in r[ai].strip('[]').split(',')[:5]] for r in arows}

# Assemble the analysis rows. A person enters the model only with a
# height_z, an age, and a recorded Male/Female (height_z was only defined
# within those groups -- see step 02). Everyone else is dropped -- and, as
# always, counted rather than silently discarded.
rows, n_dropped = [], 0
for iid in sorted(set(score) & set(pheno) & set(pcs)):
    r = pheno[iid]                 # person_id, value, value_z, age, sex
    if r[2] and r[3] and r[4] in ('Male', 'Female'):
        rows.append([float(r[2]),                      # y: the phenotype's z
                     score[iid],                       # PGI (raw, for now)
                     float(r[3]),                      # age
                     1.0 if r[4] == 'Female' else 0.0  # female: 1 yes, 0 no
                     ] + pcs[iid])                     # PC1..PC5
    else:
        n_dropped += 1

y = np.array([r[0] for r in rows])         # the outcome column
X = np.array([r[1:] for r in rows])        # the predictor columns
X[:, 0] = (X[:, 0] - X[:, 0].mean()) / X[:, 0].std()   # standardize the PGI
n = len(y)

def fit(Xs):
    """Ordinary least squares with an intercept.
    Returns (coefficients, their SEs, R-squared). np.linalg.lstsq is the
    solver that finds the best-fitting coefficients; the SE formula is the
    standard textbook one."""
    M = np.column_stack([np.ones(len(y)), Xs])         # add intercept column
    beta, *_ = np.linalg.lstsq(M, y, rcond=None)
    resid = y - M @ beta                               # leftover noise
    r2 = 1 - resid.var() / y.var()
    sigma2 = resid @ resid / (len(y) - M.shape[1])
    se = np.sqrt(np.diag(sigma2 * np.linalg.inv(M.T @ M)))
    return beta, se, r2

beta, se, r2_full = fit(X)          # the full model
_, _, r2_cov = fit(X[:, 1:])        # covariates only (PGI column removed)

rounded = lambda m: '<=20 (suppressed)' if 1 <= m <= 20 else f'~{round(m, -2):,}'
names = ['(intercept)', 'PGI'] + COVARS
out = [f'Regression: {label} (z) ~ PGI + age + female + PC1..PC5  (real data; classroom estimate)',
       f'Analysis N: {rounded(n)}   (rows dropped for missing age/sex or non-M/F: {rounded(n_dropped)})', '',
       f"{'term':<12}{'estimate':>10}{'SE':>9}{'t':>8}"]
out += [f'{nm:<12}{b:>10.4f}{s:>9.4f}{b / s:>8.2f}' for nm, b, s in zip(names, beta, se)]
out += ['',
        f'R2 with PGI    = {r2_full:.4f}',
        f'R2 covariates  = {r2_cov:.4f}',
        f'incremental R2 = {r2_full - r2_cov:.4f}', '',
        'Reading the headline row: a person one SD higher in this PGI is '
        f'{beta[1]:+.3f} SD higher',
        f'in {label}, conditional on age, sex, and five PCs. Association, not cause;',
        'one chromosome, not a full index; independent-samples OLS, not a family model.']
if meta.get('id', 'height') != 'height':
    out += ['', f'NOTE: the posted weights are HEIGHT weights and the outcome is {label},',
            'so this is a CROSS-TRAIT regression -- expect a coefficient near zero.',
            'The mechanics are what you are practicing; a real analysis fetches',
            'weights for its own trait.']
Path('results/aou_pgi_regression.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))
print('\nNext: bash scripts/06_save_run.sh')
