"""counts.py -- how every script in this lab prints a count of people.

The All of Us dissemination policy forbids sharing a count of 1-20
participants, including a count someone could work out by subtracting two
numbers you did share. The scripts handle that in one of two ways, chosen
by the COUNTS setting in config.sh:

  COUNTS=rounded   (the default) every count is printed rounded to the
                   nearest hundred, like ~57,600. Two rounded numbers
                   cannot be subtracted to give a small exact count, so
                   nothing more needs checking.
  COUNTS=exact     counts are printed exactly, like 57,612. This is safe
                   only if no two printed counts differ by 1-20, so run
                       python3 scripts/check_counts.py
                   afterwards: it lists every pair that does.

In both modes a count of 1-20 is printed as <=20, never as the number.

Every count that goes through count_text() is also written, exactly, to
work/count_ledger.tsv. That file is what check_counts.py reads. It holds
exact small counts, so it stays in work/ with the person-level files and
is never downloaded.

The other scripts use this file with:
    from counts import start_step, count_text
(Python looks for counts.py next to the script that is running.)
"""
import os
from pathlib import Path

MODE = os.environ.get('COUNTS', 'rounded')
if MODE not in ('rounded', 'exact'):
    raise SystemExit(f"COUNTS must be rounded or exact (got '{MODE}')")

LEDGER = Path('work/count_ledger.tsv')
current_step = 'unnamed step'


def read_ledger():
    """The ledger as a list of (step, label, count) rows; empty if no file."""
    rows = []
    if LEDGER.exists():
        for line in LEDGER.read_text().splitlines()[1:]:    # [1:] skips the header
            step, label, n = line.split('\t')
            rows.append((step, label, int(n)))
    return rows


def write_ledger(rows):
    LEDGER.parent.mkdir(exist_ok=True)                      # make work/ if needed
    lines = ['step\tlabel\tcount']
    for step, label, n in rows:
        lines.append(f'{step}\t{label}\t{n}')
    LEDGER.write_text('\n'.join(lines) + '\n')


def start_step(step):
    """Call once at the top of a script. Names the step, and removes that
    step's rows from an earlier run so the ledger holds only the latest."""
    global current_step
    current_step = step
    kept = []
    for row in read_ledger():
        if row[0] != step:
            kept.append(row)
    write_ledger(kept)


def count_text(n, label):
    """A count of people as printable text, recorded in the ledger.
    label says what was counted, for example 'people in analysis file'."""
    n = int(n)
    rows = read_ledger()
    if (current_step, label, n) not in rows:                # record each count once
        rows.append((current_step, label, n))
        write_ledger(rows)
    if 1 <= n <= 20:
        return '<=20'
    if MODE == 'exact':
        return f'{n:,}'                 # the , inserts thousands separators
    return f'~{round(n, -2):,}'         # round(n, -2) rounds to the nearest hundred
