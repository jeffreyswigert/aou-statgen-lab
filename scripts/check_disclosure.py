#!/usr/bin/env python3
"""Automated screen against the AoU Data and Statistics Dissemination Policy.

The policy prohibits disseminating any participant count of 1 to 20 (0 is
permitted), including counts that can be DERIVED from other reported numbers
(e.g., two rows of a sample-count table whose difference is 1..20). This screen:

  A. finds participant-level files (a person-ID column). In this lab
     results/ is for aggregate outputs only, so any such file in results/
     is itself a finding: it belongs in work/ and must never be downloaded,
  B. flags participant-count cells of 1..20 in small summary tables,
  C. flags pairs of counts in the same column whose difference is 1..20.

It complements, and does not replace, manual review: free text, figures, and
percentages that imply small counts still need a human reader.

Exit is nonzero -- blocking the save under `set -e` -- only when DATA_MODE=aou,
a B or C finding exists, and DISCLOSURE_ACK=1 is not set.

TRY IT: run it on any folder of your own tables --
    python3 scripts/check_disclosure.py path/to/your/results
and watch what the AoU-mode gate feels like:
    DATA_MODE=aou python3 scripts/check_disclosure.py results; echo "exit=$?"
Adapting this pattern to your own pipeline is the single most reusable thing
in this workshop: screen at the export boundary, block by default, and make
the override an explicit, recorded decision.
"""
import os, re, sys
from itertools import combinations
from pathlib import Path

RESULTS = Path(sys.argv[1] if len(sys.argv) > 1 else 'results')
ID_COLS = re.compile(r'^#?(F?IID|person_id|research_id)$', re.I)
COUNT_COLS = re.compile(r'sample|person|participant|obs|^n$|^count', re.I)
participant_level, findings = [], []

for path in sorted(RESULTS.iterdir()):
    if path.suffix in ('.pgen', '.log') or not path.is_file():
        continue
    try:
        lines = [l.split('\t' if '\t' in l else None) for l in path.read_text().splitlines() if l.strip()]
    except UnicodeDecodeError:
        continue
    if not lines:
        continue
    header = [c.lstrip('#') for c in lines[0]]
    if any(ID_COLS.match(c) for c in lines[0]):
        participant_level.append(path.name)
        findings.append(f'{path.name}: participant-level file in results/ (move it to work/)')
        continue
    if len(lines) > 51:      # small summary tables only; big per-variant files
        continue             # carry no small-table participant counts to screen
    for j, col in enumerate(header):
        if not COUNT_COLS.search(col):
            continue
        vals = [(i + 1, int(r[j])) for i, r in enumerate(lines[1:])
                if len(r) > j and r[j].isdigit()]
        for i, v in vals:
            if 1 <= v <= 20:
                findings.append(f'{path.name}: {col} row {i} is {v} (direct count 1-20)')
        seen = set()
        for (i1, v1), (i2, v2) in combinations(vals, 2):
            d = abs(v1 - v2)
            if 1 <= d <= 20 and (col, d) not in seen:
                seen.add((col, d))
                findings.append(f'{path.name}: {col} rows {i1},{i2} differ by {d} (derivable count 1-20)')

report = ['Disclosure screen (AoU Data and Statistics Dissemination Policy)', '']
report += ['Participant-level files found here (results/ should have none):']
report += [f'  {n}' for n in participant_level] or ['  none found']
report += ['', 'Findings (in AoU mode the save stops on any of these; round, combine, remove, or move the file):']
report += [f'  {f}' for f in findings] or ['  none found']
report += ['', 'Free text, figures, and percentages still require manual review.']
(RESULTS / 'disclosure_report.txt').write_text('\n'.join(report) + '\n')
print('\n'.join(report))

if findings and os.environ.get('DATA_MODE') == 'aou' and os.environ.get('DISCLOSURE_ACK') != '1':
    print('\nBLOCKED: findings in AoU mode. Fix the tables, or re-run '
          'with DISCLOSURE_ACK=1 after a documented manual review.', file=sys.stderr)
    sys.exit(1)
