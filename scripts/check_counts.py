#!/usr/bin/env python3
"""check_counts.py -- would printing exact counts reveal a count of 1-20?

Run after the lab steps, in either COUNTS mode:
    python3 scripts/check_counts.py

It reads work/count_ledger.tsv, where scripts/counts.py recorded the exact
value of every count the steps printed, and reports two things:

  1. counts that are themselves 1-20 (the scripts print these as <=20);
  2. pairs of counts that differ by 1-20. If both numbers in such a pair
     were printed exactly, a reader could subtract them and get the small
     count.

How to read the result. No pairs: exact counts are safe for this run.
Some pairs: look at each one. If the two counts describe the same people
at two stages (before and after a filter, a group and its total), the
difference is a real count of people, and you need rounding, or you need
to leave one of the two numbers out. If the two counts are unrelated (for
example a count of records and a count of people), the difference is not
a count of anyone.

It does not check sums of three or more counts. If a count is printed as
<=20, also check by hand that the exact counts around it (the other
groups and their total) do not add up to reveal it.

This printout names the counts and says how far apart they are in words,
not numbers, so it is safe to show. The exact values stay in the ledger.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))      # so "import counts" finds scripts/counts.py
from counts import read_ledger, MODE

rows = read_ledger()
if not rows:
    raise SystemExit('No counts recorded yet (work/count_ledger.tsv). Run the lab steps first.')

print(f'Counts recorded: {len(rows)}   (COUNTS={MODE} now; the ledger always holds exact values)')
for step, label, n in rows:
    print(f'  [{step}] {label}')

small = []
for row in rows:
    if 1 <= row[2] <= 20:
        small.append(row)
print()
print('1. Counts of 1-20 (printed as <=20 in both modes):')
if not small:
    print('  none')
for step, label, n in small:
    print(f'  [{step}] {label}')

# Several steps print the same number under different names (the people in
# the analysis file, the Obs of the summary table). Group the names by
# their count, so each distinct number is compared once. Counts of 0-20
# are left out here: they are never printed exactly.
names_by_count = {}
for step, label, n in rows:
    if n > 20:
        if n not in names_by_count:
            names_by_count[n] = []
        names_by_count[n].append(f'[{step}] {label}')
distinct = sorted(names_by_count)

# Every pair of distinct counts, once: number i with each later number j.
close_pairs = []
for i in range(len(distinct)):
    for j in range(i + 1, len(distinct)):
        if 1 <= distinct[j] - distinct[i] <= 20:
            close_pairs.append((names_by_count[distinct[j]], names_by_count[distinct[i]]))
print()
print('2. Pairs of printed counts that differ by 1-20:')
if not close_pairs:
    print('  none')
for larger, smaller in close_pairs:
    print('  the count shared by')
    for name in larger:
        print(f'      {name}')
    print('  is 1-20 more than the count shared by')
    for name in smaller:
        print(f'      {name}')

print()
if close_pairs:
    print('Result: exact counts would let a reader subtract to a count of 1-20 for the')
    print('pairs above. Keep COUNTS=rounded, or leave one number of each pair out.')
elif small:
    print('Result: no two counts differ by 1-20. A <=20 count exists: check by hand that')
    print('the exact counts around it do not add up to reveal it before using COUNTS=exact.')
else:
    print('Result: no count is 1-20 and no two counts differ by 1-20.')
    print('COUNTS=exact is safe for this run (sums of three or more counts not checked).')
