#!/usr/bin/env bash
# =============================================================================
# 02_build_phenotype.sh -- build a REAL phenotype from the All of Us database.
#
# Big picture: phenotypes in All of Us live in a database (the Curated Data
# Repository, or CDR), not in files. You get them out with a QUERY -- a
# request written in SQL, the standard language for asking databases
# questions. We run two queries, then hand the raw results to
# scripts/build_pheno.py, which cleans them into one tidy row per person.
#
# WHICH phenotype? That is the PHENO setting in config.sh (default:
# height). Every option lives as one row of data/phenotypes.tsv, carrying
# the pieces that make a phenotype a phenotype:
#   * its CONCEPT IDs -- in this database every kind of measurement has an
#     ID number, and choosing the right one is a scientific decision. The
#     worked example: height has a program-measurement concept (903133)
#     AND a generic medical-records one; the generic one "works", returns
#     plausible numbers, and silently mixes in lower-quality data. Nothing
#     errors. The menu rows record the vetted choice and the caveat.
#   * which COLUMN those IDs live in (program measurements and EHR labs
#     are keyed differently -- a real-file quirk the menu absorbs for you),
#   * PLAUSIBILITY BOUNDS and the unit,
#   * whether to standardize within sex (yes for height/weight, where the
#     sexes form two shifted bell curves).
#
# Useful forms:
#   bash scripts/02_build_phenotype.sh          # build $PHENO (see config)
#   bash scripts/02_build_phenotype.sh list     # show the menu
#   PHENO=ldl bash scripts/02_build_phenotype.sh    # one-off different pick
#   DRY_RUN=1 bash scripts/02_build_phenotype.sh    # print the SQL, run nothing
# =============================================================================
source "$(dirname "$0")/common.sh"

MENU=data/phenotypes.tsv

# "list" mode: print the menu and stop. (awk reads the table; -F'\t' says
# columns are separated by tabs; NR>1 skips the header line.)
if [[ "${1:-}" == list ]]; then
  awk -F'\t' 'NR>1 {printf "  %-12s %-24s [%s-%s %s]\n", $1, $2, $5, $6, $7}' "$MENU"
  echo 'Pick one with:  PHENO=<id> bash scripts/02_build_phenotype.sh'
  exit 0
fi

# Look up the chosen row and unpack its fields into variables. If the id
# is not in the menu, say so and show the options.
row=$(awk -F'\t' -v id="$PHENO" 'NR>1 && $1==id' "$MENU")
[[ -n "$row" ]] || { echo "PHENO='$PHENO' is not in $MENU. Options:" >&2
                     awk -F'\t' 'NR>1{print "  "$1}' "$MENU" >&2; exit 1; }
IFS=$'\t' read -r pid PHENO_LABEL concept_column concept_ids PHENO_LO PHENO_HI PHENO_UNIT PHENO_SEXZ PHENO_NOTE <<<"$row"
# Export = make these visible to the Python cleaning script.
export PHENO PHENO_LABEL PHENO_LO PHENO_HI PHENO_UNIT PHENO_SEXZ PHENO_NOTE

echo "Building phenotype: $PHENO_LABEL ($PHENO_UNIT), concept(s) $concept_ids"
echo "  note: $PHENO_NOTE"

# The two queries this run will ask. MOD(person_id, N) = 0 keeps ~1 person
# in N -- the class-size switch explained in config.sh.
Q1="
  SELECT person_id, value_as_number
  FROM \`$CDR_DATASET.measurement\`
  WHERE $concept_column IN ($concept_ids)
    AND value_as_number IS NOT NULL
    AND MOD(person_id, $SAMPLE_MOD) = 0"
Q2="
  SELECT p.person_id, p.year_of_birth, c.concept_name AS sex_at_birth
  FROM \`$CDR_DATASET.person\` p
  JOIN \`$CDR_DATASET.concept\` c ON c.concept_id = p.sex_at_birth_concept_id
  WHERE MOD(p.person_id, $SAMPLE_MOD) = 0"

# DRY_RUN mode: show the SQL that WOULD run, spend nothing, and stop.
# Reading the query is half of understanding the phenotype.
if [[ "${DRY_RUN:-}" == 1 ]]; then printf 'Query 1:%s\n\nQuery 2:%s\n' "$Q1" "$Q2"; exit 0; fi

# --- Practice-sandbox detour (ignore during the real lab) -------------------
# The free local sandbox used for rehearsal has no database; it ships a
# pre-built height file instead. On the real VM this block does nothing.
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
# The key flag is --maximum_bytes_billed: a hard COST CAP (~$0.16 at the
# default) -- an oversized query refuses to run instead of surprising
# anyone with a bill.
run_bq() {
  local out="$1"; shift
  bq --project_id="$BILLING_PROJECT" query --use_legacy_sql=false --quiet \
     --format=csv --max_rows=10000000 \
     --maximum_bytes_billed="${MAX_BYTES_BILLED:-25000000000}" "$1" > "$out"
  # Only a header line back = wrong database address or empty concept.
  [[ $(wc -l < "$out") -gt 1 ]] || { echo "Query returned nothing: $out -- check CDR_DATASET and the concept IDs." >&2; exit 1; }
}

echo "Query 1: $PHENO measurements, 1 person in ${SAMPLE_MOD} ..."
run_bq results/raw_pheno.csv "$Q1"
echo 'Query 2: year of birth and sex at birth ...'
run_bq results/raw_person.csv "$Q2"

# Now the cleaning: many rows per person -> one defensible row per person.
python3 scripts/build_pheno.py

# Decisions the menu + cleaner made FOR you, that a real study must make
# and state: repeated measurements collapsed by median; values outside the
# plausibility bounds removed; age approximated as 2026 minus birth year;
# and each phenotype's own caveat (printed above). Every one is a sentence
# in a methods section.
#
# TRY IT: walk the same steps with a different variable --
#     bash scripts/02_build_phenotype.sh list
#     PHENO=ldl bash scripts/02_build_phenotype.sh
#     bash scripts/03_explore_phenotype.sh
# Steps 03 and 05 follow the switch automatically. (The posted PGI weights
# are for HEIGHT, so with another phenotype step 05 becomes a cross-trait
# regression -- the output will remind you.)
