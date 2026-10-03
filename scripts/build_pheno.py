#!/usr/bin/env python3
"""Clean the raw database pulls into ONE analysis row per person.

Run by 02_build_phenotype.sh; you do not run this directly. Which
phenotype it is, its plausibility bounds, its unit, and how to
standardize arrive from the menu row that script looked up, passed in
as environment variables named PHENO_*. So this one cleaner serves every
menu entry.

Input (written by the two queries):
  work/raw_pheno.csv    person_id, value_as_number    (MANY rows per person)
  work/raw_person.csv   person_id, year_of_birth, sex_at_birth

Output:
  work/aou_pheno.tsv    person_id, value, value_z, age, sex   (one row per person)
  work/pheno_meta.txt   which phenotype this is (label, unit, ...); later
                        steps read it so their printouts name the variable
Both are PERSON-LEVEL files, which is why they are in work/. They stay in
the workspace.

The cleaning steps (each one is a sentence in a methods section):
  1. ONE ROW PER PERSON: the median of that person's measurements. Median
     rather than mean, so that one mis-entered visit does not move a
     person's value. ("First visit" and "mean" are the common
     alternatives; whichever you use, write it down.)
  2. PLAUSIBILITY BOUNDS (from the menu row): values outside them are far
     more likely to be data errors than people. We COUNT what we remove.
  3. SEX: kept as recorded for Male and Female; every other answer is
     pooled as 'other' (too few people in a class-size subset to treat
     separately; a real study makes its own explicit choice here).
  4. AGE: this year minus birth year. A rough teaching stand-in; real work
     uses age at the time of measurement.
  5. STANDARDIZE: value_z is the value in standard-deviation units,
     (value - mean) / SD. Within sex when the menu says so (height and
     weight: "tall for your group" is the meaningful scale); over the
     whole sample otherwise (blood pressure, lipids).

New to Python? Two ideas carry this file:
  * a LIST is an ordered collection: [1, 2, 3]
  * a DICT (dictionary) is a lookup table: phone_book['Ada'] gives her
    number. We use dicts keyed by person_id throughout, because "find
    this person's row" must happen by ID, never by position in a file.
The style is deliberately plain: loops you can read line by line, rather
than the shorter one-line forms Python also offers. Where a shorter form
is common, a comment shows it.

Printing rule: any participant count we print is rounded to the nearest
hundred, and counts of 1-20 are never printed (the All of Us dissemination
policy forbids sharing counts of 1-20, including counts recoverable by
subtracting two published numbers).
"""
import csv
import os
import statistics
from pathlib import Path

# ---- Settings, handed over by 02_build_phenotype.sh -------------------------
# os.environ is the dictionary of environment variables. .get('NAME',
# default) returns the value, or the default if the variable is not set.
PHENO = os.environ.get('PHENO', 'height')
LABEL = os.environ.get('PHENO_LABEL', PHENO)
UNIT = os.environ.get('PHENO_UNIT', '')
LO = float(os.environ.get('PHENO_LO', '-inf'))     # -inf: no lower bound
HI = float(os.environ.get('PHENO_HI', 'inf'))
WITHIN_SEX = os.environ.get('PHENO_SEXZ', 'yes') == 'yes'
NOTE = os.environ.get('PHENO_NOTE', '')


def rounded(n):
    """A participant count as printable text: '<=20' for 1-20, otherwise
    rounded to the nearest hundred. round(n, -2) rounds to hundreds."""
    if 1 <= n <= 20:
        return '<=20'
    return '~' + str(round(n, -2))


# ---- Step 0: read the measurements, grouped by person ------------------------
# values_by_person['1000010'] ends up as that person's list of readings,
# for example [167.5, 168.1, 167.9].
values_by_person = {}
with open('work/raw_pheno.csv') as f:
    for record in csv.DictReader(f):          # DictReader: each row becomes a dict keyed by the header
        pid = record['person_id']
        value = float(record['value_as_number'])
        if pid not in values_by_person:
            values_by_person[pid] = []        # first time we meet this person: start their list
        values_by_person[pid].append(value)
        # (The one-line form you will see elsewhere:
        #  values_by_person.setdefault(pid, []).append(value) )
n_records = 0
for values in values_by_person.values():
    n_records += len(values)
n_people_raw = len(values_by_person)

# ---- Read the person table into a dict keyed the same way --------------------
person = {}
with open('work/raw_person.csv') as f:
    for record in csv.DictReader(f):
        person[record['person_id']] = record

# ---- Steps 1-4: one row per person; bounds; sex; age -------------------------
# Each finished person becomes a small dict; all of them go in the list rows.
rows = []
n_implausible = 0
for pid, values in values_by_person.items():
    # Step 1: one value per person, the median.
    value = statistics.median(values)
    # Step 2: plausibility bounds. "continue" skips to the next person.
    if value < LO or value > HI:
        n_implausible += 1
        continue
    # Step 3: sex at birth, as recorded for Male/Female, else 'other'.
    # person.get(pid, {}) returns an empty dict if the person is missing
    # from the person table, so the next lines do not crash.
    p = person.get(pid, {})
    sex = p.get('sex_at_birth', '')
    if sex not in ('Male', 'Female'):
        sex = 'other'
    # Step 4: age. yob is text from the CSV; isdigit() checks it is a number.
    yob = p.get('year_of_birth', '')
    if yob.isdigit():
        age = str(2026 - int(yob))
    else:
        age = ''                                # missing: leave blank
    rows.append({'pid': pid, 'value': value, 'sex': sex, 'age': age})

# ---- Step 5: standardize -----------------------------------------------------
# z = (value - group mean) / group SD. The "group" is the person's sex
# (height, weight) or everyone (blood pressure, lipids). People in the
# 'other' group get no z when standardizing within sex: the group is too
# small for a meaningful mean and SD, and step 05 counts and drops them.
def mean_and_sd(values):
    """The mean and the (sample) standard deviation of a list of numbers."""
    return statistics.mean(values), statistics.stdev(values)

if WITHIN_SEX:
    groups = ['Male', 'Female']
else:
    groups = ['all']
stats = {}                                      # group -> (mean, sd)
for group in groups:
    group_values = []
    for r in rows:
        if group == 'all' or r['sex'] == group:
            group_values.append(r['value'])
    if len(group_values) > 1:
        stats[group] = mean_and_sd(group_values)

final = []
for r in rows:
    if WITHIN_SEX:
        group = r['sex']                        # 'Male', 'Female', or 'other'
    else:
        group = 'all'
    if group in stats:
        mu, sd = stats[group]
        z = f"{(r['value'] - mu) / sd:.4f}"     # 4 decimal places
    else:
        z = ''                                  # no group statistics: blank
    final.append([r['pid'], f"{r['value']:.1f}", z, r['age'], r['sex']])
final.sort(key=lambda row: int(row[0]))          # sort rows by person ID (as numbers)

# ---- Write the outputs -------------------------------------------------------
with open('work/aou_pheno.tsv', 'w') as f:
    writer = csv.writer(f, delimiter='\t', lineterminator='\n')
    writer.writerow(['person_id', 'value', 'value_z', 'age', 'sex'])
    writer.writerows(final)
if WITHIN_SEX:
    sexz_text = 'yes'
else:
    sexz_text = 'no'
Path('work/pheno_meta.txt').write_text(
    f'id={PHENO}\nlabel={LABEL}\nunit={UNIT}\nsex_standardized={sexz_text}\nnote={NOTE}\n')

# ---- Sample counts at each cleaning step -------------------------------------
print(f'Sample counts at each cleaning step, {LABEL}:')
print(f'  measurement records pulled          {rounded(n_records)}')
print(f'  people with any measurement         {rounded(n_people_raw)}')
print(f'  removed: outside {LO:g}-{HI:g} {UNIT:<6} {rounded(n_implausible)}')
print(f'  people in analysis file             {rounded(len(final))}')
print('Wrote work/aou_pheno.tsv (person-level; stays in the workspace).')
print('Next: bash scripts/03_explore_phenotype.sh')
