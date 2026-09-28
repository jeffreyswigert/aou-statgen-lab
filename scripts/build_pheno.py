#!/usr/bin/env python3
"""Clean the raw database pulls into ONE analysis row per person.

Run by 02_build_phenotype.sh -- you don't run this directly.

New to Python? Two ideas carry this whole file:
  * a LIST is an ordered collection: [1, 2, 3]
  * a DICT (dictionary) is a lookup table: phone_book['Ada'] -> her number.
    We use dicts keyed by person_id constantly, because "find this person's
    row" must happen by ID, never by position in a file.

Input (written by the two queries):
  results/raw_height.csv   person_id, value_as_number   (MANY rows/person)
  results/raw_person.csv   person_id, year_of_birth, sex_at_birth

Output:
  results/aou_pheno.tsv    person_id, height_cm, height_z, age, sex
  This file is PERSON-LEVEL REAL DATA. It stays inside the workspace.

The cleaning chain -- five decisions, each one a methods-section sentence:
  1. ONE ROW PER PERSON: the median of that person's measurements. Median
     rather than mean because one badly-entered visit (a typo'd 17 cm)
     shouldn't drag anyone's value; "first visit" is another defensible
     choice. Pick one, say which.
  2. PLAUSIBILITY BOUNDS: keep 100-250 cm. Values outside are far more
     likely to be data errors than people; we COUNT what we remove.
  3. SEX: kept as recorded for Male/Female; every other answer is pooled
     as 'other' (too few people in a class subset to treat separately --
     a real study makes its own explicit choice here).
  4. STANDARDIZE WITHIN SEX: height_z says how many standard deviations a
     person is from the mean OF THEIR OWN sex group. Why within sex?
     Heights of males and females form two overlapping bell curves;
     standardizing them together would mostly measure "which curve are you
     on" instead of "are you tall for your group".
  5. AGE: this year minus birth year -- a rough teaching stand-in. Real
     work uses age at the time of measurement.

One more rule, because this is real data: any count we PRINT is rounded to
the nearest 100, and counts of 1-20 are never printed at all. The All of Us
dissemination policy forbids sharing small participant counts -- including
counts someone could work out by subtracting two published numbers -- so we
design the printout so that can't happen. Exact numbers exist only in files
that stay in the workspace.
"""
import csv, statistics, sys
from pathlib import Path

OUT = Path('results/aou_pheno.tsv')

# A tiny helper for the printing rule above. "lambda" is just a one-line
# way to define a function: rounded(7) -> '<=20', rounded(59312) -> '59300'.
rounded = lambda n: '<=20' if 1 <= n <= 20 else str(round(n, -2))

def write_out(rows):
    """Write the finished table as tab-separated text with a header line."""
    with OUT.open('w') as f:
        w = csv.writer(f, delimiter='\t', lineterminator='\n')
        w.writerow(['person_id', 'height_cm', 'height_z', 'age', 'sex'])
        w.writerows(rows)

# --- Practice-sandbox detour (real lab skips this) --------------------------
if '--from-sandbox' in sys.argv:
    # The sandbox's ready-made file mimics a real quirk: some rows say the
    # literal text "NA" instead of a number. Treating "NA" as a number
    # crashes; treating it as data poisons averages. So: drop, and COUNT.
    pheno, n_na = {}, 0
    for line in Path('lab_data/height.pheno').read_text().splitlines():
        fid, iid, value = line.split()
        if value == 'NA':
            n_na += 1
        else:
            pheno[iid] = float(value)
    print(f'Dropped rows with NA phenotype: {rounded(n_na)}')
    covar = {l.split()[1]: (l.split()[2], l.split()[3])
             for l in Path('lab_data/covar.txt').read_text().splitlines()}
    sexmap = {'1': 'Male', '2': 'Female'}    # this file codes sex as 1/2
    rows = [[iid, f'{v:.4f}', f'{v:.4f}', covar.get(iid, ('', ''))[1],
             sexmap.get(covar.get(iid, ('', ''))[0], 'other')]
            for iid, v in sorted(pheno.items())]
    write_out(rows)
    print(f'SANDBOX phenotype adapted: ~{rounded(len(rows))} people '
          '(values are pre-standardized practice numbers, not centimeters).')
    sys.exit(0)
# ---------------------------------------------------------------------------

# Step 0: read every height record into a dict of lists --
# heights['1234567'] ends up as that person's list of measurements, e.g.
# [167.5, 168.1, 167.9]. setdefault means "start an empty list the first
# time we meet a person".
heights = {}
with open('results/raw_height.csv') as f:
    for record in csv.DictReader(f):        # DictReader: each row -> a dict
        heights.setdefault(record['person_id'], []).append(float(record['value_as_number']))
n_people_raw = len(heights)
n_records = sum(len(v) for v in heights.values())

# Read the person table into a dict keyed the same way.
person = {r['person_id']: r for r in csv.DictReader(open('results/raw_person.csv'))}

# Steps 1-3: one row per person, bounds, sex handling.
rows, n_implausible = [], 0
for pid, values in heights.items():
    h = statistics.median(values)                      # decision 1
    if not 100 <= h <= 250:                            # decision 2
        n_implausible += 1
        continue                                       # skip this person
    p = person.get(pid, {})                            # {} if somehow absent
    sex = p.get('sex_at_birth', '')
    sex = sex if sex in ('Male', 'Female') else 'other'  # decision 3
    yob = p.get('year_of_birth', '')
    age = str(2026 - int(yob)) if yob.isdigit() else ''  # decision 5
    rows.append([pid, h, sex, age])

# Step 4: standardize within sex. For each group: z = (value - group mean)
# divided by the group's standard deviation.
final = []
for sex in ('Male', 'Female', 'other'):
    group = [r for r in rows if r[2] == sex]
    if sex != 'other' and len(group) > 1:
        mu = statistics.mean(r[1] for r in group)
        sd = statistics.stdev(r[1] for r in group)
    for r in group:
        z = f'{(r[1] - mu) / sd:.4f}' if sex != 'other' else ''
        final.append([r[0], f'{r[1]:.1f}', z, r[3], r[2]])
final.sort(key=lambda r: int(r[0]))
write_out(final)

# The funnel: how many went in, what was removed and why, how many remain.
# If you cannot narrate this table, the cleaning isn't done.
print(f"""Cleaning funnel (printed counts rounded to the nearest 100; 1-20 suppressed):
  height records pulled            ~{rounded(n_records)}
  people with any measurement      ~{rounded(n_people_raw)}
  removed: implausible (<100/>250) ~{rounded(n_implausible)}
  people in analysis file          ~{rounded(len(final))}
Wrote results/aou_pheno.tsv (person-level -- stays in the workspace).
Next: bash scripts/03_explore_phenotype.sh""")
