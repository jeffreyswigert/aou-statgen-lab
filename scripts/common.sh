#!/usr/bin/env bash
# =============================================================================
# common.sh -- shared setup that EVERY lab script loads first.
#
# You never run this file yourself. Each numbered script starts with
#     source "$(dirname "$0")/common.sh"
# which means "run the lines of common.sh here, as if they were typed at
# the top of this script". So everything below happens at the start of
# every step: the safety switches, the move to the repo folder, loading
# your settings, and making the output folders.
#
# If this is your first bash script, read this file slowly once. The ideas
# repeat in every other script:
#   * A line starting with # is a comment: notes for people, ignored by the
#     computer.
#   * A VARIABLE is a named box holding a value. NAME=value puts something
#     in the box (no spaces around the =); $NAME reads it back out.
#   * $(some command) means "run that command and use whatever it printed".
#   * Every command finishes with an invisible EXIT CODE: 0 means "worked",
#     anything else means "failed". Scripts use these codes to stop early.
#
# In your own work: put the setup that every script in a project needs in
# one file like this, and source it. Then a change (a new folder, a new
# setting) is made once, not once per script.
# =============================================================================

# ---- Safety switches -------------------------------------------------------
# "set" changes how bash behaves for the rest of the script. Three switches:
#   -e            stop at the FIRST command that fails, instead of carrying
#                 on and producing garbage from a broken step
#   -u            using a variable that was never set is an error, instead
#                 of silently acting like empty text (a typo in a variable
#                 name becomes a loud stop, not an empty file name)
#   -o pipefail   in a chain like "a | b", a failure anywhere fails the chain
#                 (without it, only the last command's exit code counts)
# Why we care: in genetics the expensive bugs do not crash. They produce
# plausible-looking wrong numbers. These switches turn silent problems into
# early stops.
set -euo pipefail

# ---- Always work from the repo folder --------------------------------------
# Every path in every script is written relative to the repo root
# (lab_data/..., work/..., results/...). That only works if the script is
# running from the repo root, so we move there first, no matter where you
# were when you typed the command.
#   ${BASH_SOURCE[0]}   the path of the file being read right now (this one)
#   dirname PATH        PATH with the file name cut off, leaving its folder
#   /..                 one folder up (scripts/ -> the repo root)
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# ---- Load your settings ----------------------------------------------------
# config.sh is your copy of config.example.sh with real values filled in.
# "source" runs it here, so its variables (WORKSHOP_BUCKET, CHROM, ...)
# become available to this script.
#   [[ -f config.sh ]]   true if a file named config.sh exists
#   if ! ...             "if that is NOT true"
#   >&2                  send this message to the error stream, so it shows
#                        even when normal output is being saved to a file
#   exit 1               stop the script with a nonzero (failure) code
if [[ ! -f config.sh ]]; then
  echo 'No config.sh yet. Run:  cp config.example.sh config.sh' >&2
  echo 'then open config.sh and fill in the values your instructor projects.' >&2
  exit 1
fi
source config.sh

# ---- Output folders --------------------------------------------------------
# Two output folders, kept apart on purpose:
#   work/     PERSON-LEVEL files (one row per participant). These stay in
#             the workspace. Never download them.
#   results/  AGGREGATE outputs only (summary tables, figures). These are
#             the only files that may be downloaded, after the disclosure
#             check in step 06 passes and you have reviewed them.
# mkdir -p makes a folder, and does nothing if it already exists.
mkdir -p work results

# ---- A shortcut for running PLINK ------------------------------------------
# A bash FUNCTION is a named block of commands. After this definition,
# writing
#     p2 --bfile lab_data/chr22_hm3 --freq
# runs
#     plink2 --threads 2 --memory 1024 --bfile lab_data/chr22_hm3 --freq
# "$@" means "all the arguments given to p2, passed along unchanged".
#
# Why a function: PLINK's compute settings are set in ONE place (config.sh)
# instead of retyped in every PLINK command. Retyped settings eventually get
# mistyped. The alternative, writing "$PLINK2" --threads "$THREADS" ...
# in full each time, works too and is what you will see in many pipelines.
p2() {
  "$PLINK2" --threads "$THREADS" --memory "$MEMORY_MB" "$@"
}

# ---- The billing flag for cloud copies -------------------------------------
# Some All of Us buckets are "requester pays": a copy from them is refused
# unless it names the project that pays for the transfer. Every script that
# copies from the cloud needs the same flag, so it is built here, once.
#   gflags=()                        an empty LIST (bash calls it an array)
#   gflags=(--billing-project=X)     a list holding one item
# A list rather than a plain string so that it can be inserted into a
# command with "${gflags[@]}" and vanish completely when it is empty:
#     gcloud "${gflags[@]}" storage cp SOURCE DEST
if [[ -n "${BILLING_PROJECT:-}" ]]; then     # -n: "is not empty"
  gflags=(--billing-project="$BILLING_PROJECT")
else
  gflags=()
fi
