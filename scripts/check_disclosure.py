#!/usr/bin/env python3
"""A check on results/ against the All of Us Data and Statistics
Dissemination Policy, run before anything is saved or downloaded.

The policy prohibits disseminating any participant count of 1 to 20 (0 is
permitted), including counts that can be DERIVED from other reported
numbers (for example, two rows of a sample-count table whose difference
is between 1 and 20). This script:

  A. finds participant-level files (any file with a person-ID column).
     results/ is for aggregate outputs only, so such a file in results/
     is itself a finding: it belongs in work/ and must never be
     downloaded;
  B. flags participant-count cells of 1-20 in small summary tables;
  C. flags pairs of counts in the same column whose difference is 1-20.

It complements manual review; it does not replace it. Free text,
figures, and percentages that imply small counts still need a human
reader.

Exit code: nonzero (which stops the save under set -e) only when
DATA_MODE=aou, a finding exists, and DISCLOSURE_ACK=1 is not set.

Run:  python3 scripts/check_disclosure.py results
The report is printed and written to results/disclosure_report.txt.

In your own work: run a check like this at the export boundary, block by
default, and make the override an explicit, recorded decision. Adapt the
column-name patterns below to your own tables.

TRY IT: run it on any folder of your own tables:
    python3 scripts/check_disclosure.py path/to/your/results
and see what the AoU-mode gate does:
    DATA_MODE=aou python3 scripts/check_disclosure.py results; echo "exit=$?"
"""
import os
import re
import sys
from itertools import combinations
from pathlib import Path

# The folder to check: the first command-line argument, or results/.
if len(sys.argv) > 1:
    RESULTS = Path(sys.argv[1])
else:
    RESULTS = Path('results')

# Regular expressions (patterns for matching text). re.I = ignore case.
#   ID_COLS     a column name that means "one row per person": FID, IID,
#               person_id, research_id (an optional # in front, as PLINK writes)
#   COUNT_COLS  a column name that suggests a participant count
ID_COLS = re.compile(r'^#?(F?IID|person_id|research_id)$', re.I)
COUNT_COLS = re.compile(r'sample|person|participant|obs|^n$|^count', re.I)
MAX_TABLE_ROWS = 51      # bigger files are per-variant tables, not small summary tables

participant_level = []   # names of person-level files found
findings = []            # human-readable descriptions of each problem

for path in sorted(RESULTS.iterdir()):
    if not path.is_file() or path.suffix in ('.pgen', '.log'):
        continue
    # Read the file as lines of fields. Split on tabs if the line has any,
    # otherwise on whitespace. A binary file (a .png) cannot be decoded as
    # text; skip it.
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    lines = []
    for line in text.splitlines():
        if not line.strip():
            continue
        if '\t' in line:
            lines.append(line.split('\t'))
        else:
            lines.append(line.split())
    if not lines:
        continue
    header = [name.lstrip('#') for name in lines[0]]

    # A. a person-ID column in the header means a person-level file.
    is_person_level = False
    for name in lines[0]:
        if ID_COLS.match(name):
            is_person_level = True
    if is_person_level:
        participant_level.append(path.name)
        findings.append(f'{path.name}: participant-level file in results/ (move it to work/)')
        continue

    # B and C only apply to small tables with count-like columns.
    if len(lines) > MAX_TABLE_ROWS:
        continue
    for j, column_name in enumerate(header):
        if not COUNT_COLS.search(column_name):
            continue
        # Collect (row number, value) for every whole-number cell in this column.
        values = []
        for i, row in enumerate(lines[1:], start=1):
            if len(row) > j and row[j].isdigit():
                values.append((i, int(row[j])))
        # B. a direct count of 1-20
        for i, v in values:
            if 1 <= v <= 20:
                findings.append(f'{path.name}: {column_name} row {i} is {v} (direct count 1-20)')
        # C. two counts whose difference is 1-20. combinations(values, 2)
        # gives every pair once. The same difference is reported once per column.
        reported = set()
        for (i1, v1), (i2, v2) in combinations(values, 2):
            d = abs(v1 - v2)
            if 1 <= d <= 20 and d not in reported:
                reported.add(d)
                findings.append(f'{path.name}: {column_name} rows {i1},{i2} differ by {d} (derivable count 1-20)')

# ---- The report ---------------------------------------------------------------
report = ['Disclosure check (All of Us Data and Statistics Dissemination Policy)', '',
          'Participant-level files found here (results/ should have none):']
if participant_level:
    for name in participant_level:
        report.append(f'  {name}')
else:
    report.append('  none found')
report += ['', 'Findings (in AoU mode the save stops on any of these; round, combine, remove, or move the file):']
if findings:
    for f in findings:
        report.append(f'  {f}')
else:
    report.append('  none found')
report += ['', 'Free text, figures, and percentages still require manual review.']
(RESULTS / 'disclosure_report.txt').write_text('\n'.join(report) + '\n')
print('\n'.join(report))

# ---- The gate --------------------------------------------------------------------
if findings and os.environ.get('DATA_MODE') == 'aou' and os.environ.get('DISCLOSURE_ACK') != '1':
    print('\nBLOCKED: findings in AoU mode. Fix the tables, or re-run '
          'with DISCLOSURE_ACK=1 after a documented manual review.', file=sys.stderr)
    sys.exit(1)
