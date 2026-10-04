# =============================================================================
# config.example.sh -- the template for your settings.
#
# Do this once, at the start of the lab:
#     cp config.example.sh config.sh
#     nano config.sh          # fill in the two "FILL ME" values
#
# Why a settings file at all? The scripts are the same for everyone; the
# values below (your bucket, the billing project, the CDR release, which
# chromosome) are what differ between people, workspaces, and runs. Keeping
# them here, in one place, means no script ever needs editing, and a value
# is typed once instead of in seven scripts. Every script loads this file
# first (see scripts/common.sh).
#
# Why two files? config.sh will contain values specific to YOUR workspace,
# and it is listed in .gitignore so it can never be committed to GitHub by
# accident. The template (this file) is safe to share; your filled copy
# stays with you.
#
# In your own work: in a notebook, the same idea is a first cell of
# settings -- every value that changes between projects, in one place,
# never committed. A file like this one becomes useful once a project is
# a set of scripts run in several places (a collaborator's workspace, a
# batch job, a loop over 22 chromosomes).
#
# How to read each line:
#   export NAME=value   NAME=value alone makes a variable that only this
#                       shell can see. "export" also hands it to programs
#                       the scripts start, such as python3. (Only DATA_MODE
#                       is actually read that way today, by
#                       check_disclosure.py; exporting all of them is the
#                       usual convention and costs nothing.)
#   ${NAME:-fallback}   "if NAME is already set (for example, typed before
#                       the command), keep it; otherwise use the fallback."
#                       It lets you override one setting for one run:
#                           CHROM=21 bash scripts/01_fetch_genotypes.sh
# =============================================================================

# We are working with real All of Us data. This switch makes the disclosure
# screen in the save step BLOCK on problems instead of just warning.
export DATA_MODE=aou

# ---- FILL ME: two values from the workshop workspace (instructor projects them)

# The workshop workspace's cloud storage bucket (starts with gs://). The
# instructor put today's genotype subset and PGI weights here, and your
# saved run goes here too.
export WORKSHOP_BUCKET="${WORKSHOP_BUCKET:-}"

# The Google Cloud project that pays for queries and copies.
export BILLING_PROJECT="${BILLING_PROJECT:-}"

# ---- Set for v9; change only for a different CDR release -------------------

# The Curated Data Repository (CDR) in BigQuery, written project.dataset.
# This is the database the phenotype query reads. C2025Q4R6 is the v9
# Controlled Tier release.
export CDR_DATASET="${CDR_DATASET:-wb-silky-artichoke-2408.C2025Q4R6}"

# ---- Usually left alone ----------------------------------------------------

# Which PLINK 2 program to run. Default: whatever "plink2" is installed on
# the VM. If your instructor staged a local copy: export PLINK2=$PWD/tools/plink2
export PLINK2="${PLINK2:-plink2}"

# Compute settings for every PLINK call: 2 processor threads and 8192 MiB
# (8 GB) of memory, a modest share of the 30 GB VM. Scoring the full
# genotype file (about 535,000 people) fails with "Out of memory" at
# 1024 MiB.
export THREADS="${THREADS:-2}"
export MEMORY_MB="${MEMORY_MB:-8192}"

# Which chromosome to use. 22 is one of the smallest, which keeps the copy
# and the scoring fast. (Real studies use all 22.)
export CHROM="${CHROM:-22}"

# ---- Where the genotypes come from -----------------------------------------
# Two options; both end with lab_data/chr22_hm3.bed/.bim/.fam on the VM.
#   bucket   copy the instructor's ready-made HapMap3 subset from the
#            workshop bucket (three small files; 1-3 minutes).
#   aou      build that subset yourself from All of Us's own chromosome
#            file, the way a real project would (scripts/subset_aou_genotypes.sh).
#            Slower; how much slower depends on whether the All of Us
#            bucket is mounted on the VM (see ACAF_DIR below).
export GENO_SOURCE="${GENO_SOURCE:-bucket}"

# Used when GENO_SOURCE=bucket: the folder holding the subset, and the
# file-name stem of the three files there. Step 1 saves the copies as
# lab_data/chr${CHROM}_hm3.* whatever they are called in the bucket.
export GENO_SRC="${GENO_SRC:-${WORKSHOP_BUCKET:+${WORKSHOP_BUCKET%/}/genotypes}}"
export GENO_STEM="${GENO_STEM:-chr${CHROM}_hm3}"

# Used when GENO_SOURCE=aou:
#   ACAF_FORMAT   which All of Us file format to read: pgen (PLINK 2,
#                 compressed, smaller) or bed (PLINK 1; chr22 is ~250 GB).
#   ACAF_DIR      where All of Us's chromosome files are. Leave empty for the
#                 standard gs:// folder (the file is copied to the VM first).
#                 If the Workbench has mounted the dataset under ~/workspace,
#                 give that folder instead (a path, not gs://): PLINK then
#                 reads the file in place and fetches only what it needs.
#                 scripts/prep/check_genotype_access.sh looks for the mount.
#   HM3_LIST_URI  leave empty for chromosome 22: the HapMap3 variant list
#                 (public reference data: rsID, chromosome, GRCh38 position,
#                 alleles) is in this repository, data/hm3_chr22_hg38.tsv.
#                 For another chromosome, the gs:// address of your own list.
export ACAF_FORMAT="${ACAF_FORMAT:-pgen}"
export ACAF_DIR="${ACAF_DIR:-}"
export HM3_LIST_URI="${HM3_LIST_URI:-}"

# All of Us's genetic-ancestry predictions (used for figure groups and the
# regression's PCs). This bucket is "requester pays": downloads from it must
# name a billing project, which our fetch script handles.
export ANC_SRC="${ANC_SRC:-gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/aux/ancestry/ancestry_preds.tsv}"

# The PGI weight file: published height GWAS summary statistics, converted
# by the instructor to three columns (rsid, effect_allele, weight) and put
# in the workshop bucket.
export WEIGHTS_URI="${WEIGHTS_URI:-${WORKSHOP_BUCKET:+$WORKSHOP_BUCKET/pgi_workshop/height_weights.txt}}"

# Which phenotype to build. Options live in data/phenotypes.tsv, one row
# each with its database concept IDs, plausibility bounds, and caveats --
# run "bash scripts/02_build_phenotype.sh list" to see them. The whole
# pipeline downstream (explore, regression) follows this switch, so trying
# another variable is one line:  PHENO=ldl bash scripts/02_build_phenotype.sh
export PHENO="${PHENO:-height}"

# Sample-size switch: keep only people whose person_id divides evenly by this
# number. 1 = everyone (the default). 10 = roughly a tenth of the cohort,
# for a quick trial run of new code. Same code either way. The phenotype
# query (step 2) and the genotype subset (step 1, aou mode) both apply it,
# so the two files cover the same people.
export SAMPLE_MOD="${SAMPLE_MOD:-1}"

# How counts of people are printed (scripts/counts.py explains both).
#   rounded   to the nearest hundred, like ~57,600. Two rounded numbers
#             cannot be subtracted to give a small exact count.
#   exact     the exact count. Safe only if no two printed counts differ
#             by 1-20; check with:  python3 scripts/check_counts.py
# A count of 1-20 is printed as <=20 either way.
export COUNTS="${COUNTS:-rounded}"
