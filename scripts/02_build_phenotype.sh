#!/usr/bin/env bash
# =============================================================================
# 02_build_phenotype.sh -- build a phenotype from the All of Us database.
#
# Big picture: phenotypes in All of Us live in a database (the Curated
# Data Repository, or CDR), not in files. You get them out with a QUERY:
# a request written in SQL, the standard language for asking databases
# questions. This script sends two queries with the bq tool, saves the
# answers as CSV files in work/, and then runs scripts/build_pheno.py,
# which cleans them into one row per person.
#
# Which phenotype is the PHENO setting in config.sh (default: height).
# Each option is one row of data/phenotypes.tsv, which records:
#   * its CONCEPT IDs. In the CDR every kind of measurement has an ID
#     number, and choosing the right one is a scientific decision. For
#     height: concept 903133 is height measured by the program (plus
#     remote self-report); the generic concept 3036277 also returns
#     heights copied from electronic health records. Both "work".
#   * which COLUMN holds those IDs (program measurements and EHR labs are
#     keyed in different columns),
#   * plausibility bounds and the unit,
#   * whether to standardize within sex.
#
# Ways to run it:
#   bash scripts/02_build_phenotype.sh              # build $PHENO
#   bash scripts/02_build_phenotype.sh list         # show the menu
#   PHENO=ldl bash scripts/02_build_phenotype.sh    # a different phenotype, this run only
#   DRY_RUN=1 bash scripts/02_build_phenotype.sh    # print the SQL, run nothing
#
# In your own work: the same shape (query -> raw CSV in work/ -> a cleaning
# script -> one row per person) fits any CDR variable. Change the menu
# row, not the code.
# =============================================================================
source "$(dirname "$0")/common.sh"

MENU=data/phenotypes.tsv

# ---- "list" mode: print the menu and stop ----------------------------------
# $1 is the first word typed after the script name; ${1:-} makes it empty
# rather than an error when nothing was typed (the -u switch would object).
if [[ "${1:-}" == list ]]; then
  # column -t -s $'\t' lines up a tab-separated file for reading;
  # cut -f 1,2,5,6,7 keeps only the columns worth showing.
  cut -f 1,2,5,6,7 "$MENU" | column -t -s $'\t'
  echo 'Pick one with:  PHENO=<id> bash scripts/02_build_phenotype.sh'
  exit 0
fi

# ---- Look up the chosen phenotype's row in the menu ------------------------
# Read the menu one line at a time. "IFS=$'\t' read -r a b c ..." splits a
# tab-separated line into the named variables. The header line is skipped;
# the line whose first column equals $PHENO is the one we want, and its
# fields stay in the variables after the loop ends.
found=no
while IFS=$'\t' read -r id label concept_column concept_ids lo hi unit sexz note; do
  if [[ "$id" == id ]]; then continue; fi            # the header line
  if [[ "$id" == "$PHENO" ]]; then found=yes; break; fi
done < "$MENU"
if [[ "$found" == no ]]; then
  echo "PHENO='$PHENO' is not in $MENU. Options:" >&2
  cut -f 1 "$MENU" | tail -n +2 | sed 's/^/  /' >&2   # column 1, minus the header, indented
  exit 1
fi
# The cleaning script (Python) needs these values too. "export" hands a
# variable to programs started from this script; python3 reads them with
# os.environ. (Passing them as command-line arguments would work too.)
export PHENO PHENO_LABEL="$label" PHENO_LO="$lo" PHENO_HI="$hi" PHENO_UNIT="$unit" PHENO_SEXZ="$sexz" PHENO_NOTE="$note"

echo "Building phenotype: $label ($unit), concept(s) $concept_ids"
echo "  note: $note"

# ---- The two queries ---------------------------------------------------------
# SQL, line by line:
#   SELECT a, b        which columns to return
#   FROM `table`       which table (project.dataset.table, in backticks)
#   WHERE ...          which rows: the concept IDs we chose, with a value,
#                      and MOD(person_id, N) = 0: the person's ID divides
#                      evenly by N, which keeps about 1 person in N (every
#                      ID divides evenly by 1, so N = 1 keeps everyone). It
#                      is the sample-size switch from config.sh, and the same
#                      rule step 1 (aou mode) applies to the genotypes.
# A bash variable can hold several lines of text; the query is built here
# so that DRY_RUN can print it and bq can run it, from one definition.
Q1="
  SELECT person_id, value_as_number
  FROM \`$CDR_DATASET.measurement\`
  WHERE $concept_column IN ($concept_ids)
    AND value_as_number IS NOT NULL
    AND MOD(person_id, $SAMPLE_MOD) = 0"
# The second query joins two tables: person (year of birth, and the ID of
# the sex-at-birth answer) with concept (the words that ID stands for).
# JOIN ... ON says which columns must match between the two tables.
Q2="
  SELECT p.person_id, p.year_of_birth, c.concept_name AS sex_at_birth
  FROM \`$CDR_DATASET.person\` p
  JOIN \`$CDR_DATASET.concept\` c ON c.concept_id = p.sex_at_birth_concept_id
  WHERE MOD(p.person_id, $SAMPLE_MOD) = 0"

# ---- DRY_RUN mode: show the SQL and stop -------------------------------------
if [[ "${DRY_RUN:-}" == 1 ]]; then
  printf 'Query 1:%s\n\nQuery 2:%s\n' "$Q1" "$Q2"
  exit 0
fi

if ! command -v bq >/dev/null; then
  echo 'bq (the BigQuery tool) not found. Run this on the All of Us Workbench VM.' >&2
  exit 1
fi

# ---- Run a query and save the answer as CSV ----------------------------------
# A function, because the same six-line command is needed twice.
#   bq query                        send a query
#   --project_id=X                  the project billed for it
#   --use_legacy_sql=false          standard SQL (the syntax above)
#   --quiet                         no progress chatter
#   --format=csv                    answer as comma-separated text
#   --max_rows=10000000             do not truncate the answer
#   --maximum_bytes_billed=N        a hard COST CAP: a query that would
#                                   scan more than N bytes is refused
#                                   instead of run (25 GB is about $0.16)
#   > "$out"                        save what bq prints into the file
run_query() {
  local out="$1"       # first argument: the file to write
  local sql="$2"       # second argument: the query text
  bq --project_id="$BILLING_PROJECT" query --use_legacy_sql=false --quiet \
     --format=csv --max_rows=10000000 \
     --maximum_bytes_billed="${MAX_BYTES_BILLED:-25000000000}" "$sql" > "$out"
  # An answer with only the header line means the query matched nothing:
  # usually a wrong dataset name or a concept ID with no rows.
  if [[ $(wc -l < "$out") -le 1 ]]; then
    echo "Query returned nothing: $out. Check CDR_DATASET and the concept IDs." >&2
    exit 1
  fi
}

if [[ "$SAMPLE_MOD" == 1 ]]; then who=everyone; else who="1 person in $SAMPLE_MOD"; fi
echo "Query 1: $PHENO measurements, $who ..."
run_query work/raw_pheno.csv "$Q1"
echo 'Query 2: year of birth and sex at birth ...'
run_query work/raw_person.csv "$Q2"

# ---- Clean: many rows per person -> one row per person -----------------------
python3 scripts/build_pheno.py

# Decisions the menu and the cleaner made for you, which a real study
# must make and state: repeated measurements collapsed to the median;
# values outside the plausibility bounds removed; age approximated as 2026
# minus birth year; and the phenotype's own caveat (printed above). Each
# is a sentence in a methods section.
#
# TRY IT: the same steps with a different variable:
#     bash scripts/02_build_phenotype.sh list
#     PHENO=ldl bash scripts/02_build_phenotype.sh
#     bash scripts/03_explore_phenotype.sh
# Steps 03 and 05 follow the switch. (The posted PGI weights are for
# height, so with another phenotype step 05 is a cross-trait regression;
# the output says so.)
