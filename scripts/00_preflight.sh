#!/usr/bin/env bash
# =============================================================================
# 00_preflight.sh -- check the environment BEFORE doing any analysis.
#
# Why a whole script for this: if a tool or setting is missing, we want the
# lab to fail RIGHT HERE, with a message that says what to fix -- not five
# commands from now with a confusing error. Run it at the start of every
# session; it changes nothing and takes a second.
#
# (New to scripts? Read scripts/common.sh first -- it explains the basics
# that every file here uses.)
# =============================================================================
source "$(dirname "$0")/common.sh"

printf 'Working directory: %s\nData mode: %s\n' "$PWD" "$DATA_MODE"

# Are the programs we need installed? "command -v X" asks the shell "could
# you run X?" and fails if not. The "|| { ...; exit 1; }" pattern means:
# if the check failed, print a message and stop (|| = "or else").
command -v python3 >/dev/null || { echo 'python3 missing.' >&2; exit 1; }
command -v "$PLINK2" >/dev/null || { echo 'PLINK 2 missing: ask the instructor to finish setup.' >&2; exit 1; }
"$PLINK2" --version
python3 --version

# Python extras the figures and regression need (already installed on AoU
# Workbench VMs -- this just confirms it).
python3 -c 'import numpy, matplotlib' 2>/dev/null \
  || { echo 'python3 needs numpy and matplotlib (preinstalled on the AoU VM).' >&2; exit 1; }

# The two cloud tools: gcloud copies files from cloud storage, bq queries
# the CDR database. Both come with the AoU VM.
command -v gcloud >/dev/null && echo 'gcloud available' || echo 'gcloud missing: cloud fetches need the AoU VM.'
command -v bq >/dev/null && echo 'bq available' || echo 'bq missing: the phenotype query needs the AoU VM.'

# Were the three FILL ME values actually filled? ":?" means "stop with this
# message if the variable is empty" -- catching a skipped config edit now.
: "${WORKSHOP_BUCKET:?Fill WORKSHOP_BUCKET in config.sh}"
: "${BILLING_PROJECT:?Fill BILLING_PROJECT in config.sh}"
: "${CDR_DATASET:?Fill CDR_DATASET in config.sh}"

# Enough disk space? (-h prints sizes in human units.)
df -h .

printf 'Preflight passed. Next: bash scripts/01_fetch_genotypes.sh\n'

# TRY IT: break something on purpose and watch this script catch it --
#     PLINK2=/does/not/exist bash scripts/00_preflight.sh
# A pipeline you have personally seen fail LOUDLY is one you can trust.
