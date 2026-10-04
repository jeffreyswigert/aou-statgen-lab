#!/usr/bin/env bash
# =============================================================================
# 06_save_run.sh -- check the outputs, record what was done, and copy an
# archive of the run to the workspace bucket.
#
# Why: work that exists only on a VM's disk is one misclick from gone, and
# a result you cannot trace back to the code and inputs that produced it
# is hard to defend. The archive holds the code as run, your settings, all
# outputs and logs, and two pieces of PROVENANCE: checksums of the inputs
# (a checksum is a fingerprint; the same fingerprint later means provably
# the same file) and the git commit of the code (the exact version of
# every script).
#
# The archive contains person-level files (work/). That is fine inside
# the workspace bucket. It must never leave the workspace.
#
# The four steps, in order:
#   1. the disclosure check on results/
#   2. the manifest (results/run_manifest.txt)
#   3. the archive (runs/<timestamp>.tar.gz)
#   4. the copy to the bucket, and a listing to confirm it
# =============================================================================
source "$(dirname "$0")/common.sh"

# Stop early, with instructions, if no destination bucket is configured.
: "${WORKSHOP_BUCKET:?Set WORKSHOP_BUCKET in config.sh to your workspace gs:// bucket}"
if [[ "$WORKSHOP_BUCKET" != gs://* ]]; then
  echo 'WORKSHOP_BUCKET must start with gs://' >&2
  exit 1
fi

# ---- 1. The disclosure check ---------------------------------------------------
# scripts/check_disclosure.py reads every file in results/ and reports
# participant counts of 1-20, printed directly OR recoverable by
# subtracting two printed numbers, and any person-level file. The All of
# Us dissemination policy forbids sharing such counts. In our AoU mode
# (DATA_MODE=aou in config.sh) a finding makes the check exit with a
# failure code, and the set -e switch from common.sh then stops this
# script right here. That is deliberate: the safe outcome is the
# default, and overriding it (DISCLOSURE_ACK=1) is an explicit, recorded
# decision after a person has reviewed the file.
python3 scripts/check_disclosure.py results

# The same question for what the steps printed on screen: did any two
# printed counts differ by 1-20? (scripts/counts.py recorded each one.)
# With exact counts in AoU mode, a finding stops the script here too.
if [[ -s work/count_ledger.tsv ]]; then
  python3 scripts/check_counts.py
fi

# ---- 2. The manifest -------------------------------------------------------------
# A unique name for this run: the UTC time, plus a random suffix so that
# two runs in the same second cannot collide.
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:8])')"
mkdir -p runs

# Which version of the code is this? "git rev-parse --short HEAD" prints
# the current commit's short ID. If any tracked file was edited after
# that commit (git status --porcelain prints something), "-dirty" is
# added, so the manifest records that the code was not exactly the commit.
code_version="$(git rev-parse --short HEAD 2>/dev/null || echo not-a-git-checkout)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  code_version="$code_version-dirty"
fi
manifest="results/run_manifest.txt"
# The { ... } > FILE form sends everything printed inside the braces into
# the file, in one go.
{
  printf 'code_version=%s\n' "$code_version"
  printf 'data_mode=%s\ncdr_dataset=%s\nchrom=%s\nsample_mod=%s\ngeno_source=%s\n' \
         "$DATA_MODE" "$CDR_DATASET" "$CHROM" "$SAMPLE_MOD" "${GENO_SOURCE:-bucket}"
  "$PLINK2" --version
  # sha256sum prints the fingerprint of each input file.
  sha256sum lab_data/chr${CHROM}_hm3.bed lab_data/chr${CHROM}_hm3.bim \
            lab_data/chr${CHROM}_hm3.fam lab_data/height_weights.txt 2>/dev/null || true
} > "$manifest"

# ---- 3. The archive ----------------------------------------------------------------
# tar -czf ARCHIVE THINGS... = "make a compressed bundle of these
# folders and files" (c = create, z = compress, f = into this file).
tar -czf "runs/$run_id.tar.gz" config.sh scripts work results

# ---- 4. Copy it to the bucket, then list it ------------------------------------------
# Always confirm the cloud copy exists before you trust it (and before
# you stop the VM).
dest="${WORKSHOP_BUCKET%/}/statgen-lab/$run_id.tar.gz"
gcloud "${gflags[@]}" storage cp "runs/$run_id.tar.gz" "$dest"
gcloud "${gflags[@]}" storage ls "$dest"
# cat <<'MSG' ... MSG prints everything between the two markers as-is.
cat <<'MSG'
Saved to the workspace bucket (the archive stays inside the Workbench).

To download results to your own computer:
  1. Only files in results/ (aggregate tables and figures). Never work/,
     lab_data/, runs/, or the archive.
  2. Open and read each file first: no count of 1-20 people, directly or
     by subtracting two numbers.
  3. JupyterLab file browser -> right-click the file -> Download.

Then STOP YOUR CLOUD APP (Apps tab -> your app -> Stop). A running VM bills
by the hour. Stop keeps the app and its disk; your files will still be here.
MSG

# TRY IT: see the provenance you just created:
#     grep code_version results/run_manifest.txt
#     gcloud storage ls "$WORKSHOP_BUCKET/statgen-lab/"
