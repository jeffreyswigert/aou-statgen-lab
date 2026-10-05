#!/usr/bin/env python3
"""A basic regression that includes the PGI.

Run by 05_pgi_regression.sh.

THE MODEL
    phenotype_z = a + b*PGI_z + c*age + d*female + (five PC terms) + noise

Both the outcome and the PGI are STANDARDIZED (mean 0, SD 1):
    phenotype_z = (value - mean) / SD     done in step 02 (within sex for
                                          height and weight)
    PGI_z       = (PGI - mean) / SD       done below, over the analysis rows
So the coefficient b reads "SDs of outcome per SD of PGI".

(The outcome is whichever phenotype step 02 built, height by default; the
printout names it. With another PHENO, remember the posted weights are
height weights, so b is a cross-trait association; the output says so.)

Regression in one paragraph: we assume each person's outcome is roughly
a weighted sum of their predictors plus random noise, and ask which
weights (the coefficients) fit the data best. "Best" means the smallest
sum of squared leftovers, which is why the method is called ordinary
least squares (OLS). The computer solves for those weights directly. Our
choices are which predictors to include and how to read the result.

Where each predictor comes from, and why it is in the model:
  PGI_z     the step-04 score, standardized here.
  age, sex  from the phenotype file. Basic demographics. Where the
            outcome was standardized within sex (height, weight), the
            'female' term picks up any remainder.
  PC1..PC5  principal components: five numbers per person that summarize
            broad genetic ancestry patterns. Both allele frequencies and
            environments differ across ancestral backgrounds, and the
            PGI carries some of that. The PCs absorb part of it, so b is
            less contaminated by population structure. They come from
            All of Us's ancestry file, where they are stored as ONE
            bracketed text string per person ("[-0.009, 0.015, ...]")
            that we split apart ourselves. Real files are like this.

WHAT WE REPORT
  * the coefficient table: each estimate with its SE (standard error,
    the estimate's uncertainty) and t (estimate / SE; roughly, |t| > 2
    means "hard to explain by chance alone").
  * R-squared: the share of outcome variance the predictors explain.
  * INCREMENTAL R-squared: R2 with the PGI minus R2 without it, which is
    what the PGI adds beyond the ordinary covariates. Report this one;
    the PGI's R2 on its own overstates it, because the PGI overlaps with
    the PCs.

WHAT THE RESULT IS AND IS NOT (printed with the results)
  Association, not cause. One chromosome, not a full index. And plain OLS
  assumes unrelated people; with relatives in the sample, a real study
  uses family-aware methods.

About the code: the regression is solved with numpy's least-squares
routine and the textbook formula for standard errors, written out so you
can see every piece. In practice you would usually call a library
(statsmodels in Python, lm() in R) and get the same
numbers plus p-values and diagnostics.

Printing rule: participant counts go through count_text() in
scripts/counts.py (exact, or rounded to the nearest hundred with
COUNTS=rounded; 1-20 never shown).

TRY IT: in the COVARS line below, delete the five PC names, so it reads
    COVARS = ['age', 'female']
and re-run
    bash scripts/05_pgi_regression.sh
Watch the PGI coefficient move. That movement is population structure:
the cheapest demonstration of why the PCs belong in the model.
"""
import numpy as np
from pathlib import Path

from counts import start_step, count_text     # scripts/counts.py: how counts are printed

start_step('05 PGI regression')

# The covariates in the model, by name. This list is the model: remove a
# name and that term leaves the regression; the table and the heading
# follow. Available names: age, female, and PC1 ... PC16.
COVARS = ['age', 'female', 'PC1', 'PC2', 'PC3', 'PC4', 'PC5']


def read_table(path):
    """Tab-separated table -> (column names, list of rows). The # that
    PLINK puts at the start of its header line is removed."""
    lines = Path(path).read_text().splitlines()
    header = lines[0].lstrip('#').split('\t')
    rows = []
    for line in lines[1:]:
        if line.strip():
            rows.append(line.split('\t'))
    return header, rows


# ---- Read the three inputs into dicts keyed by person ID --------------------
# The same files as step 04, joined the same safe way: by ID value.
score_header, score_rows = read_table('work/aou_pgi.sscore')
iid_col = score_header.index('IID')             # IID, not FID (which is 0)
sum_col = score_header.index('SCORE1_SUM')
score = {}
for row in score_rows:
    score[row[iid_col]] = float(row[sum_col])

pheno_header, pheno_rows = read_table('work/aou_pheno.tsv')
pheno = {}
for row in pheno_rows:
    pheno[row[0]] = row                         # person_id, value, value_z, age, sex

anc_header, anc_rows = read_table('lab_data/ancestry_preds.tsv')
pca_col = anc_header.index('pca_features')
pcs = {}
for row in anc_rows:
    # Unpack the bracketed PC string: remove the [ and ], split on commas,
    # and turn each piece into a number. The file has 16 PCs per person.
    text = row[pca_col].strip('[]')
    numbers = []
    for piece in text.split(','):
        numbers.append(float(piece))
    pcs[row[0]] = numbers                       # column 0 is research_id

meta = {}
for line in Path('work/pheno_meta.txt').read_text().splitlines():
    key, value = line.split('=', 1)
    meta[key] = value
label = meta.get('label', 'phenotype')

# ---- Assemble the analysis rows ---------------------------------------------
# A person enters the model only with a phenotype z, an age, and a
# recorded Male/Female (the z was only defined within those groups; see
# step 02). Everyone else is dropped, and counted rather than silently
# discarded. The IDs in all three files: set intersection with &.
y_list = []                                     # the outcome, one entry per person
x_list = []                                     # the predictors, one list per person
n_dropped = 0
for pid in sorted(set(score) & set(pheno) & set(pcs)):
    row = pheno[pid]
    value_z, age, sex = row[2], row[3], row[4]
    if value_z == '' or age == '' or sex not in ('Male', 'Female'):
        n_dropped += 1
        continue
    if sex == 'Female':
        female = 1.0
    else:
        female = 0.0
    # Every covariate this person could contribute, by name ...
    available = {'age': float(age), 'female': female}
    for k, pc_value in enumerate(pcs[pid]):
        available[f'PC{k + 1}'] = pc_value      # PC1, PC2, ...
    # ... and the ones named in COVARS, in that order, after the PGI.
    x_row = [score[pid]]                        # column 0: the PGI (raw)
    for name in COVARS:
        if name not in available:
            raise SystemExit(f"COVARS names '{name}', which is not available. "
                             f"Choose from: {', '.join(available)}")
        x_row.append(available[name])
    y_list.append(float(value_z))
    x_list.append(x_row)

y = np.array(y_list)
X = np.array(x_list)                            # one row per person, one column per predictor
# Standardize the PGI column (column 0) over the analysis rows: PGI -> PGI_z.
X[:, 0] = (X[:, 0] - X[:, 0].mean()) / X[:, 0].std()
n = len(y)


def fit(predictors):
    """Ordinary least squares with an intercept.
    Returns (coefficients, their standard errors, R-squared).

    M is the design matrix: a column of ones (the intercept) followed by
    the predictor columns. np.linalg.lstsq finds the coefficients that
    make M @ beta as close to y as possible (@ is matrix multiplication).
    The standard errors follow the textbook formula
        SE = sqrt( diag( sigma^2 * (M'M)^-1 ) ),
    where sigma^2 is the residual variance."""
    M = np.column_stack([np.ones(len(y)), predictors])
    result = np.linalg.lstsq(M, y, rcond=None)
    beta = result[0]                            # the coefficients (lstsq returns other things too)
    residuals = y - M @ beta                    # what the model leaves unexplained
    r2 = 1 - residuals.var() / y.var()
    n_obs, n_params = M.shape
    sigma2 = (residuals @ residuals) / (n_obs - n_params)
    covariance = sigma2 * np.linalg.inv(M.T @ M)
    se = np.sqrt(np.diag(covariance))
    return beta, se, r2


beta, se, r2_full = fit(X)                      # the full model
_, _, r2_cov = fit(X[:, 1:])                    # covariates only: every column except the PGI

# ---- Report ------------------------------------------------------------------
names = ['(intercept)', 'PGI_z'] + COVARS
model_text = ' + '.join(['PGI_z'] + COVARS)
out = [f'Regression: {label} (z) ~ {model_text}  (real data; classroom estimate)',
       f'Analysis N: {count_text(n, "regression analysis N")}   (rows dropped for missing age/sex or non-M/F: {count_text(n_dropped, "rows dropped for missing age/sex or non-M/F")})', '',
       f"{'term':<12}{'estimate':>10}{'SE':>9}{'t':>8}"]
for name, b, s in zip(names, beta, se):
    out.append(f'{name:<12}{b:>10.4f}{s:>9.4f}{b / s:>8.2f}')
out += ['',
        f'R2 with PGI    = {r2_full:.4f}',
        f'R2 covariates  = {r2_cov:.4f}',
        f'incremental R2 = {r2_full - r2_cov:.4f}', '',
        f'Reading the headline row: a person one SD higher in this PGI is {beta[1]:+.3f} SD higher',
        f'in {label}, holding the other terms in the model fixed. Association, not cause;',
        'one chromosome, not a full index; independent-samples OLS, not a family model.']
if meta.get('id', 'height') != 'height':
    out += ['', f'NOTE: the posted weights are HEIGHT weights and the outcome is {label},',
            'so this is a CROSS-TRAIT regression; expect a coefficient near zero.',
            'The mechanics are what you are practicing; a real analysis gets',
            'weights for its own trait.']
Path('results/aou_pgi_regression.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))
print('\nNext: bash scripts/06_save_run.sh')
