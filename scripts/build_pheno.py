#!/usr/bin/env python3
"""Clean the raw database pulls into ONE analysis row per person.

Run by 02_build_phenotype.sh -- you don't run this directly. Which
phenotype, its plausibility bounds, its unit, and how to standardize all
arrive from the menu row that script looked up (passed in as environment
variables named PHENO_*), so this same cleaner serves every menu entry.

New to Python? Two ideas carry this whole file:
  * a LIST is an ordered collection: [1, 2, 3]
  * a DICT (dictionary) is a lookup table: phone_book['Ada'] -> her number.
    We use dicts keyed by person_id constantly, because "find this
    person's row" must happen by ID, never by position in a file.

Input (written by the two queries):
  work/raw_pheno.csv    person_id, value_as_number   (MANY rows/person)
  work/raw_person.csv   person_id, year_of_birth, sex_at_birth

Output:
  work/aou_pheno.tsv    person_id, value, value_z, age, sex
  work/pheno_meta.txt   which phenotype this is (label, unit, ...) --
                        later steps read it so their printouts and
                        figures name the right variable
  All of these are PERSON-LEVEL files, which is why they are in work/.
  They stay inside the workspace.

The cleaning steps -- each one is a sentence in a methods section:
  1. ONE ROW PER PERSON: the median of that person's measurements. Median
     rather than mean so that one mis-entered visit does not move a
     person's value. ("First visit" and "mean" are the common
     alternatives; whichever you use, write it down.)
  2. PLAUSIBILITY BOUNDS (from the menu row): values outside are far more
     likely to be data errors than people. We COUNT what we remove.
  3. SEX: kept as recorded for Male/Female; every other answer pooled as
     'other' (too few people in a class subset to treat separately -- a
     real study makes its own explicit choice here).
  4. AGE: this year minus birth year -- a rough teaching stand-in. Real
     work uses age at the time of measurement.
  5. STANDARDIZE: value_z is the value in standard-deviation units.
     Within sex when the menu says so (height, weight: the sexes form two
     shifted bell curves, and "tall for your group" is the meaningful
     scale); over the whole sample otherwise (blood pressure, lipids).

Printing rule, because this is real data: any count we PRINT is rounded
to the nearest 100, and counts of 1-20 are never printed at all (the
All of Us dissemination policy forbids sharing small participant counts,
including counts recoverable by subtracting two published numbers).
"""
import csv, os, statistics
from pathlib import Path

OUT = Path('work/aou_pheno.tsv')

# The menu row's settings, handed over by 02_build_phenotype.sh.
PHENO = os.environ.get('PHENO', 'height')
LABEL = os.environ.get('PHENO_LABEL', PHENO)
UNIT = os.environ.get('PHENO_UNIT', '')
LO = float(os.environ.get('PHENO_LO', '-inf'))
HI = float(os.environ.get('PHENO_HI', 'inf'))
SEXZ = os.environ.get('PHENO_SEXZ', 'yes') == 'yes'
NOTE = os.environ.get('PHENO_NOTE', '')

rounded = lambda n: '<=20' if 1 <= n <= 20 else '~' + str(round(n, -2))

def write_out(rows):
    """Write the finished table, plus the small 'what is this' meta file."""
    with OUT.open('w') as f:
        w = csv.writer(f, delimiter='\t', lineterminator='\n')
        w.writerow(['person_id', 'value', 'value_z', 'age', 'sex'])
        w.writerows(rows)
    Path('work/pheno_meta.txt').write_text(
        f'id={PHENO}\nlabel={LABEL}\nunit={UNIT}\nsex_standardized={"yes" if SEXZ else "no"}\nnote={NOTE}\n')


# Step 0: read every measurement into a dict of lists --
# values_by_person['1234567'] ends up as that person's list of readings,
# e.g. [167.5, 168.1, 167.9]. setdefault means "start an empty list the
# first time we meet a person".
values_by_person = {}
with open('work/raw_pheno.csv') as f:
    for record in csv.DictReader(f):        # DictReader: each row -> a dict
        values_by_person.setdefault(record['person_id'], []).append(float(record['value_as_number']))
n_people_raw = len(values_by_person)
n_records = sum(len(v) for v in values_by_person.values())

# Read the person table into a dict keyed the same way.
person = {r['person_id']: r for r in csv.DictReader(open('work/raw_person.csv'))}

# Steps 1-4: one row per person, bounds, sex, age.
rows, n_implausible = [], 0
for pid, values in values_by_person.items():
    v = statistics.median(values)                      # step 1
    if not LO <= v <= HI:                              # step 2
        n_implausible += 1
        continue                                       # skip this person
    p = person.get(pid, {})                            # {} if somehow absent
    sex = p.get('sex_at_birth', '')
    sex = sex if sex in ('Male', 'Female') else 'other'  # step 3
    yob = p.get('year_of_birth', '')
    age = str(2026 - int(yob)) if yob.isdigit() else ''  # step 4
    rows.append([pid, v, sex, age])

# Step 5: standardize. z = (value - group mean) / group SD, where "group"
# is the person's sex group (SEXZ phenotypes) or everyone (the rest).
final = []
if SEXZ:
    for sex in ('Male', 'Female', 'other'):
        group = [r for r in rows if r[2] == sex]
        if sex != 'other' and len(group) > 1:
            mu = statistics.mean(r[1] for r in group)
            sd = statistics.stdev(r[1] for r in group)
        for r in group:
            z = f'{(r[1] - mu) / sd:.4f}' if sex != 'other' else ''
            final.append([r[0], f'{r[1]:.1f}', z, r[3], r[2]])
else:
    mu = statistics.mean(r[1] for r in rows)
    sd = statistics.stdev(r[1] for r in rows)
    final = [[r[0], f'{r[1]:.1f}', f'{(r[1] - mu) / sd:.4f}', r[3], r[2]] for r in rows]
final.sort(key=lambda r: int(r[0]))
write_out(final)

# Sample counts at each cleaning step: how many records and people came in,
# how many were removed and why, how many remain.
print(f"""Sample counts at each cleaning step, {LABEL} (rounded to nearest 100; 1-20 suppressed):
  measurement records pulled          {rounded(n_records)}
  people with any measurement         {rounded(n_people_raw)}
  removed: outside {LO:g}-{HI:g} {UNIT:<6} {rounded(n_implausible)}
  people in analysis file             {rounded(len(final))}
Wrote work/aou_pheno.tsv (person-level -- stays in the workspace).
Next: bash scripts/03_explore_phenotype.sh""")
