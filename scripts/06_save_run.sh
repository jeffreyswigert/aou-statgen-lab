#!/usr/bin/env bash
# =============================================================================
# 06_save_run.sh -- package the run so future-you can PROVE what was done,
# then copy the archive to the workspace bucket.
#
# Why: work that exists only on a VM's disk is one misclick from gone. The
# archive holds the code as run, your settings, all outputs and logs, and
# two pieces of PROVENANCE: checksums of the inputs (a checksum is a
# fingerprint -- same fingerprint later means provably the same file) and
# the git commit of the code (so the archive names the exact version of
# every script that produced it -- GitHub closing the reproducibility
# loop).
#
# With real data the archive may contain person-level files, which is fine
# -- the bucket is inside the workspace. It must never leave the workspace.
# =============================================================================
source "$(dirname "$0")/common.sh"

# Fail early, with instructions, if no destination bucket is configured.
: "${WORKSHOP_BUCKET:?Set WORKSHOP_BUCKET in config.sh to your workspace gs:// bucket}"
[[ "$WORKSHOP_BUCKET" == gs://* ]] || { echo 'WORKSHOP_BUCKET must start with gs://' >&2; exit 1; }
command -v gcloud >/dev/null

# THE DISCLOSURE SCREEN runs before anything is packaged. It reads every
# results file and flags participant counts of 1-20 -- printed directly OR
# derivable by subtracting two published numbers -- which the All of Us
# dissemination policy forbids sharing. In our AoU mode a finding STOPS
# the save right here (the set -e switch from common.sh turns the
# screen's failure into a full stop). That is deliberate: the safe
# outcome is the default, and overriding it (DISCLOSURE_ACK=1) is an
# explicit, recorded decision after human review -- never an accident.
python3 scripts/check_disclosure.py results

# A unique name for this run: timestamp + random suffix, so a re-run can
# never silently overwrite an earlier archive.
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:8])')"
mkdir -p runs

# The manifest: settings, code version, tool version, input fingerprints.
# git rev-parse asks "which commit is this folder at?"; the -dirty tag is
# added if any file was edited after that commit -- honest provenance.
code_version="$(git rev-parse --short HEAD 2>/dev/null || echo not-a-git-checkout)"
[[ -z "$(git status --porcelain 2>/dev/null)" ]] || code_version="$code_version-dirty"
manifest="results/run_manifest.txt"
{
  printf 'code_version=%s\n' "$code_version"
  printf 'data_mode=%s\ncdr_dataset=%s\nchrom=%s\nsample_mod=%s\n' \
         "$DATA_MODE" "$CDR_DATASET" "$CHROM" "$SAMPLE_MOD"
  "$PLINK2" --version
  # sha256sum computes the fingerprint of each input file.
  sha256sum lab_data/chr${CHROM}_filtered.bed lab_data/chr${CHROM}_filtered.bim \
            lab_data/chr${CHROM}_filtered.fam lab_data/height_weights.txt 2>/dev/null || true
} > "$manifest"

# Bundle the settings, the scripts, and every result into one compressed
# archive (tar -czf = "make a compressed bundle of these folders").
tar -czf "runs/$run_id.tar.gz" config.sh scripts results

# Copy it to the bucket, then LIST it -- always verify the cloud copy
# exists before you trust it (and before you stop the VM).
gflags=(); [[ -z "${BILLING_PROJECT:-}" ]] || gflags=(--billing-project="$BILLING_PROJECT")
dest="${WORKSHOP_BUCKET%/}/statgen-lab/$run_id.tar.gz"
gcloud "${gflags[@]}" storage cp "runs/$run_id.tar.gz" "$dest"
gcloud "${gflags[@]}" storage ls "$dest"
printf 'Saved. Now STOP YOUR CLOUD APP in the Workbench -- VMs bill while idle.\n'

# TRY IT: see the provenance you just created --
#     grep code_version results/run_manifest.txt
#     gcloud storage ls "$WORKSHOP_BUCKET/statgen-lab/"
