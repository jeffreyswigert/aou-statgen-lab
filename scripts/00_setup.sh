#!/usr/bin/env bash
# =============================================================================
# 00_setup.sh -- check the environment BEFORE doing any analysis.
#
# What it does: confirms that the programs the lab needs are installed,
# that the settings file is filled in, and that the disk has room. It
# changes nothing and takes a second.
#
# Why a whole script for this: if a tool or setting is missing, we want
# the lab to fail RIGHT HERE, with a message that says what to fix, not
# five commands from now with a confusing error. In your own projects, a
# check like this at the top of a pipeline saves the most time on a new
# machine or a new workspace, where something is always missing.
#
# (New to scripts? Read scripts/common.sh first; it explains the basics
# that every file here uses.)
# =============================================================================
source "$(dirname "$0")/common.sh"

# printf prints text with placeholders: each %s is replaced by the next
# argument, and \n is a line break. (echo would also work; printf is the
# choice when the output has a fixed layout.)
printf 'Working directory: %s\nData mode: %s\n' "$PWD" "$DATA_MODE"

# ---- Are the programs we need installed? -----------------------------------
# "command -v X" prints where program X is, and fails if X is not
# installed. We do not want the path printed, only the pass/fail, so its
# output is sent to /dev/null (a place that discards everything).
#   if ! command -v X >/dev/null; then ... fi
# reads as: "if X cannot be found, then ...". You will also see this
# written on one line in many scripts:
#   command -v X >/dev/null || { echo 'X missing' >&2; exit 1; }
# where || means "or else". Same meaning; the if form is easier to read.
if ! command -v python3 >/dev/null; then
  echo 'python3 missing.' >&2
  exit 1
fi
if ! command -v "$PLINK2" >/dev/null; then
  echo 'PLINK 2 missing: ask the instructor to finish setup.' >&2
  exit 1
fi
"$PLINK2" --version
python3 --version

# Python extras the figures and regression need (already installed on the
# All of Us Workbench VMs; this confirms it). "python3 -c" runs the quoted
# Python code; importing the two libraries either works or fails.
if ! python3 -c 'import numpy, matplotlib' 2>/dev/null; then
  echo 'python3 needs numpy and matplotlib (preinstalled on the All of Us VM).' >&2
  exit 1
fi

# The two cloud tools: gcloud copies files to and from cloud storage; bq
# sends queries to the CDR database. Both come with the All of Us VM.
# These are warnings, not stops, so the script can be used on a laptop.
if command -v gcloud >/dev/null; then echo 'gcloud available'; else echo 'gcloud missing: cloud copies need the All of Us VM.'; fi
if command -v bq >/dev/null;     then echo 'bq available';     else echo 'bq missing: the phenotype query needs the All of Us VM.'; fi

# ---- Were the FILL ME values filled in? ------------------------------------
# ${NAME:?message} means "stop with this message if NAME is empty". The
# leading colon is a command that does nothing; it is there only so the
# check has somewhere to happen. The longer, plainer way is:
#   if [[ -z "$WORKSHOP_BUCKET" ]]; then echo 'Fill ...' >&2; exit 1; fi
# (-z means "is empty".) Both are common; the short form is worth
# recognizing because it appears in many scripts.
: "${WORKSHOP_BUCKET:?Fill WORKSHOP_BUCKET in config.sh}"
: "${BILLING_PROJECT:?Fill BILLING_PROJECT in config.sh}"
: "${CDR_DATASET:?Fill CDR_DATASET in config.sh}"

# ---- Enough disk space? ----------------------------------------------------
# df reports free space; -h prints sizes in human units (G, M); "." means
# "the disk this folder is on".
df -h .

printf 'Setup check passed. Next: bash scripts/01_fetch_genotypes.sh\n'

# TRY IT: break something on purpose and watch this script catch it:
#     PLINK2=/does/not/exist bash scripts/00_setup.sh
# A pipeline you have personally seen fail LOUDLY is one you can trust.
