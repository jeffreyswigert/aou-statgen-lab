#!/usr/bin/env bash
# =============================================================================
# common.sh -- shared setup that EVERY lab script loads first.
#
# If this is your first bash script, read this file slowly once; the ideas
# here repeat in every other script:
#
#   * A line starting with # is a comment: notes for humans, ignored by the
#     computer.
#   * A VARIABLE is a named box holding a value. NAME=value puts something in
#     the box (no spaces around =); $NAME reads it back out.
#   * $(some command) means "run that command and use whatever it printed."
#   * Every command finishes with an invisible EXIT CODE: 0 means "worked",
#     anything else means "failed". Scripts use these codes to stop early.
# =============================================================================

# "set" turns on three safety switches for the whole script:
#   -e            stop at the FIRST command that fails, instead of plowing on
#                 and producing garbage from a broken step
#   -u            using a variable that was never set is an ERROR, instead of
#                 silently acting like empty text
#   -o pipefail   in a chain like "a | b", a failure anywhere fails the chain
# Why we care: in genetics the expensive bugs don't crash -- they produce
# plausible-looking wrong numbers. These switches convert silent problems
# into loud, early stops.
set -euo pipefail

# Move into the folder that CONTAINS the scripts/ folder (the repo root),
# no matter where you were when you typed the command. That way every path
# in every script can be written relative to the repo root and always work.
# (BASH_SOURCE[0] is "the file you are reading right now"; dirname trims the
# file name off, leaving its folder; /.. means "one level up".)
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Load your settings. config.sh is YOUR copy of config.example.sh with the
# real workspace values filled in. "source" runs that file inside this one,
# so all its variables become available here. If you haven't made it yet,
# stop now with instructions instead of failing confusingly later.
[[ -f config.sh ]] || {
  echo 'No config.sh yet. Run:  cp config.example.sh config.sh' >&2
  echo 'then open config.sh and fill in the values your instructor projects.' >&2
  exit 1
}
source config.sh

# Two output folders, kept apart on purpose:
#   work/     PERSON-LEVEL files (one row per participant). These stay in
#             the workspace. Never download them.
#   results/  AGGREGATE outputs only (summary tables, figures). These are
#             the only files that may be downloaded, after the disclosure
#             check in step 06 passes and you have reviewed them.
# (-p means "and do nothing if the folder already exists".)
mkdir -p work results

# Define a tiny helper FUNCTION named p2. From now on, writing
#     p2 --some --flags
# actually runs
#     plink2 --threads 2 --memory 1024 --some --flags
# i.e., PLINK with our compute settings attached. We set those settings in
# ONE place (config.sh) instead of retyping them -- retyped settings
# eventually get mistyped. ("$@" means "all the arguments you gave p2,
# passed along unchanged".)
p2() { "$PLINK2" --threads "$THREADS" --memory "$MEMORY_MB" "$@"; }
