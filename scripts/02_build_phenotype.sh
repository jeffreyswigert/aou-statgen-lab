#!/usr/bin/env bash
# =============================================================================
# 02_build_phenotype.sh -- build a REAL phenotype (height) from the All of Us
# database.
#
# Big picture: phenotypes in All of Us live in a database (the Curated Data
# Repository, or CDR), not in files. You get them out with a QUERY -- a
# request written in SQL, the standard language for asking databases
# questions. We run two queries, then hand the raw results to a Python
# script that cleans them into one tidy row per person.
#
# Query 1: every height measurement (many people were measured at several
#          visits, so this returns MANY rows per person).
# Query 2: each person's year of birth and recorded sex at birth.
#
# The single most important line is the WHERE clause choosing concept
# 903133. In this database every kind of measurement has an ID number
# called a CONCEPT ID, and there are TWO for height: this one (the
# program's own standardized measurement) and a generic medical-records
# one. The generic one "works" -- it returns plausible numbers -- but
# silently mixes in hundreds of thousands of hospital-record heights of
# much lower quality. Nothing would error. Choosing the concept is a
# scientific decision, and it is the first thing a reviewer should ask
# about.
# =============================================================================
source "$(dirname "$0")/common.sh"

# --- Practice-sandbox detour (ignore during the real lab) -------------------
# The free local sandbox used for rehearsal has no database; it ships a
# pre-built phenotype file instead. If we detect the sandbox, adapt that
# file and skip the queries. On the real VM this block does nothing.
if [[ -n "${AOU_SANDBOX_ROOT:-}" ]]; then
  echo 'SANDBOX: no database here. Using the sandbox pre-built height phenotype.'
  mkdir -p lab_data
  gsutil cp gs://ssgac-shared-phenotype-resources-2026/phenotypes/height.pheno lab_data/
  gsutil cp gs://ssgac-shared-phenotype-resources-2026/phenotypes/covar.txt lab_data/
  python3 scripts/build_pheno.py --from-sandbox
  exit 0
fi
# ---------------------------------------------------------------------------

command -v bq >/dev/null || { echo 'bq (the BigQuery tool) not found -- run this on the AoU Workbench VM.' >&2; exit 1; }

# A helper that runs one query safely and saves the answer as a CSV file.
run_bq() {
  local out="$1"; shift        # first argument = the file to write
  # The important flag is --maximum_bytes_billed: a hard COST CAP. If a
  # query would scan more data than this (~$0.16 worth), it refuses to run
  # instead of surprising anyone with a bill.
  bq --project_id="$BILLING_PROJECT" query --use_legacy_sql=false --quiet \
     --format=csv --max_rows=10000000 \
     --maximum_bytes_billed="${MAX_BYTES_BILLED:-25000000000}" "$1" > "$out"
  # A one-line answer means only the header came back: wrong database
  # address or wrong concept. Stop here, where the cause is obvious.
  [[ $(wc -l < "$out") -gt 1 ]] || { echo "Query returned nothing: $out -- check CDR_DATASET." >&2; exit 1; }
}

# MOD(person_id, N) = 0 keeps ~1 person in N: the class-size switch
# explained in config.sh. Same code, smaller cohort, faster lab.
echo "Query 1: height measurements (concept 903133), 1 person in ${SAMPLE_MOD} ..."
run_bq results/raw_height.csv "
  SELECT person_id, value_as_number
  FROM \`$CDR_DATASET.measurement\`
  WHERE measurement_source_concept_id = 903133
    AND value_as_number IS NOT NULL
    AND MOD(person_id, $SAMPLE_MOD) = 0"

echo 'Query 2: year of birth and sex at birth ...'
# The person table stores sex as a concept ID number; JOINing to the
# concept table swaps the number for its human-readable name.
run_bq results/raw_person.csv "
  SELECT p.person_id, p.year_of_birth, c.concept_name AS sex_at_birth
  FROM \`$CDR_DATASET.person\` p
  JOIN \`$CDR_DATASET.concept\` c ON c.concept_id = p.sex_at_birth_concept_id
  WHERE MOD(p.person_id, $SAMPLE_MOD) = 0"

# Now the cleaning: many rows per person -> one defensible row per person.
python3 scripts/build_pheno.py

# Decisions we made FOR you today, that a real study must make and state:
# repeated visits collapsed by median; heights outside 100-250 cm removed;
# clinic measurements and remote self-report pooled (they share concept
# 903133); age approximated as 2026 minus birth year. Every one of these
# is a sentence in a methods section.
