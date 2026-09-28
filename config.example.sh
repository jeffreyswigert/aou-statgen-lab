# =============================================================================
# config.example.sh -- the template for your settings.
#
# Do this once, at the start of the lab:
#     cp config.example.sh config.sh
#     nano config.sh          # fill in the three "FILL ME" values
#
# Why two files? config.sh will contain values specific to YOUR workspace,
# and it is listed in .gitignore so it can never be committed to GitHub by
# accident. The template (this file) is safe to share; your filled copy
# stays with you. That split -- templates in the repo, real values outside
# it -- is a habit worth keeping in your own projects.
#
# The pattern ${NAME:-fallback} means: "if NAME is already set (for
# example, typed before the command), keep it; otherwise use the
# fallback." It lets you override any single setting for one run:
#     CHROM=21 bash scripts/01_fetch_genotypes.sh
# =============================================================================

# We are working with real All of Us data. This switch makes the disclosure
# screen in the save step BLOCK on problems instead of just warning.
export DATA_MODE=aou

# ---- FILL ME: three values from your workspace (instructor projects them) --

# The cloud storage bucket this workspace may write to (starts with gs://).
export WORKSHOP_BUCKET="${WORKSHOP_BUCKET:-}"

# The Google Cloud project that pays for queries and downloads.
export BILLING_PROJECT="${BILLING_PROJECT:-}"

# The Curated Data Repository's BigQuery address, written project.dataset --
# this is the database the phenotype query reads.
export CDR_DATASET="${CDR_DATASET:-}"

# ---- Usually left alone ----------------------------------------------------

# Which PLINK 2 program to run. Default: whatever "plink2" is installed on
# the VM. If your instructor staged a local copy: export PLINK2=$PWD/tools/plink2
export PLINK2="${PLINK2:-plink2}"

# Compute settings for every PLINK call: 2 processor threads and 1024 MiB of
# memory. Small on purpose -- this lab needs seconds, and polite settings
# won't fight other work on a shared VM.
export THREADS=2
export MEMORY_MB=1024

# Which chromosome to download and score. 22 is one of the smallest, which
# keeps the download and the scoring fast. (Real studies use all 22.)
export CHROM="${CHROM:-22}"

# Where the genotype files live: HapMap3-filtered PLINK filesets shared by
# SSGAC, one file trio per chromosome.
export GENO_SRC="${GENO_SRC:-gs://ssgac-shared-genotype-resources-2026/hm3_filtered_plink1}"

# All of Us's genetic-ancestry predictions (used for figure groups and the
# regression's PCs). This bucket is "requester pays": downloads from it must
# name a billing project, which our fetch script handles.
export ANC_SRC="${ANC_SRC:-gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/aux/ancestry/ancestry_preds.tsv}"

# The PGI weight file: GWAS summary statistics posted to the shared USC pod
# bucket, converted to three columns (rsid, effect_allele, weight). The
# default guesses a standard spot inside WORKSHOP_BUCKET; your instructor
# may give you a different gs:// address to paste here.
export WEIGHTS_URI="${WEIGHTS_URI:-${WORKSHOP_BUCKET:+$WORKSHOP_BUCKET/pgi_workshop/height_weights.txt}}"

# Which phenotype to build. Options live in data/phenotypes.tsv, one row
# each with its database concept IDs, plausibility bounds, and caveats --
# run "bash scripts/02_build_phenotype.sh list" to see them. The whole
# pipeline downstream (explore, regression) follows this switch, so trying
# another variable is one line:  PHENO=ldl bash scripts/02_build_phenotype.sh
export PHENO="${PHENO:-height}"

# Class-size switch: keep only people whose person_id divides evenly by this
# number. 10 = roughly a tenth of the cohort (fast queries, quick joins).
# 1 = everyone, for real work after the lab. Same code either way.
export SAMPLE_MOD="${SAMPLE_MOD:-10}"
