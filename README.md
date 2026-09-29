# Statistical genetics on All of Us: Lab 1

A one-hour, step-by-step lab on **All of Us v9 Controlled Tier data**
(Controlled Tier access required). Each step is one script:

| Step | What it does | Script |
|---|---|---|
| 0 | Check tools and settings | `scripts/00_preflight.sh` |
| 1 | Copy chromosome-22 genotypes (HapMap3 variants) and the ancestry file to the VM | `scripts/01_fetch_genotypes.sh` |
| 2 | Build a height phenotype from the CDR (BigQuery), one row per person | `scripts/02_build_phenotype.sh` |
| 3 | Summary table (Stata `summarize` layout) and two figures | `scripts/03_explore_phenotype.sh` |
| 4 | Build a polygenic index (PGI) with PLINK; histogram of the standardized PGI | `scripts/04_build_pgi.sh` |
| 5 | Regress standardized height on the standardized PGI, age, sex, and 5 PCs | `scripts/05_pgi_regression.sh` |
| 6 | Check `results/`, write a manifest, archive the run to the workspace bucket | `scripts/06_save_run.sh` |

`slides.pdf` is the deck (each step: what it does, then the commands and
code). `cheatsheet.pdf` lists terminal, BigQuery, cloud storage, PLINK, and
git commands for your own projects.

## Quick start (on your All of Us Workbench VM)

Create a JupyterLab app (standard VM, 4 CPUs / 16 GB, 100 GB disk, autostop
1 hour), open a Terminal from the Launcher, then:

```bash
git clone https://github.com/jeffreyswigert/aou-statgen-lab.git
cd aou-statgen-lab
cp config.example.sh config.sh     # then fill WORKSHOP_BUCKET and BILLING_PROJECT
bash scripts/00_preflight.sh
bash scripts/01_fetch_genotypes.sh
bash scripts/02_build_phenotype.sh
bash scripts/03_explore_phenotype.sh
bash scripts/04_build_pgi.sh
bash scripts/05_pgi_regression.sh
bash scripts/06_save_run.sh
```

When you finish, pause the app (Apps tab -> your app -> Pause).

## Folders

| Folder | Contents | Leaves the Workbench? |
|---|---|---|
| `lab_data/` | copied-in genotypes, ancestry file, PGI weights | No |
| `work/` | person-level files: query results, phenotype, PGI scores | No |
| `results/` | summary tables and figures (aggregate only) | Yes, after step 6's check passes and you review each file |
| `runs/` | archive of each run (a copy goes to the workspace bucket) | No |

All four folders are listed in `.gitignore`, so git never commits them.

## Data use rules, and how the code follows them

- **Participant-level data stays in the Workbench** (All of Us Data User
  Code of Conduct). Person-level files are written only to `lab_data/` and
  `work/`.
- **No participant count of 1–20 may be shared**, directly or by
  calculation (Data and Statistics Dissemination Policy). Printed counts are
  rounded to the nearest 100 and counts of 1–20 print as `<=20`. Step 6 runs
  `scripts/check_disclosure.py` on `results/` and stops if it finds a count
  of 1–20, a pair of counts that differ by 1–20, or a person-level file.
  Figures and free text are not checked; review them yourself.
- **Downloads are monitored** (Egress Alert Policy). Download only files in
  `results/`: JupyterLab file browser -> right-click -> Download.
- **Code on GitHub may not contain participant data or counts under 20**,
  including in notebook outputs (Researcher FAQ).

Policy texts: support.researchallofus.org (Policies). `cheatsheet.pdf`
lists the article numbers.

## GitHub in this workflow

Code is written and versioned outside the Workbench, cloned onto the VM with
`git clone`, and updated with `git pull`. The repository holds code, the
settings template (`config.example.sh`), and documentation. It never holds
data, results, the filled-in `config.sh`, or notebook outputs. Step 6 writes
the repository's commit ID into `results/run_manifest.txt`
(`code_version=`, with `-dirty` if files were edited after the commit), so
each archived run names the code that produced it.

## Where the genotypes come from

All of Us publishes whole-genome genotypes (the "ACAF threshold" callset) as
one PLINK file set per chromosome under
`gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/acaf_threshold/plink_bed/`.
The chromosome-22 `.bed` is about 250 GB, and All of Us publishes no HapMap3
subset. Before class the instructor ran `scripts/prep/make_hm3_subset.sh`,
which keeps the HapMap3 variants on one chromosome (about 2 GB), renames
variants from `chr22:pos:ref:alt` to rsIDs, and writes
`$WORKSHOP_BUCKET/genotypes/chr22_hm3.{bed,bim,fam}`. To build another
chromosome, run the same script with `CHROM` set (it needs a VM with about
300 GB of free disk).

## Other phenotypes

`data/phenotypes.tsv` lists numeric phenotypes with their concept IDs,
plausibility bounds, units, and standardization rule: height, weight,
systolic blood pressure, LDL, HDL.

```bash
bash scripts/02_build_phenotype.sh list     # the list
PHENO=ldl bash scripts/02_build_phenotype.sh
bash scripts/03_explore_phenotype.sh        # tables and figures follow the choice
bash scripts/05_pgi_regression.sh           # so does the regression
```

`DRY_RUN=1` on step 02 prints the SQL without running a query. To add a
variable, find its concept ID in the public
[Data Browser](https://databrowser.researchallofus.org) and add a row.
The PGI weights are for height, so with another phenotype the step-05
regression is cross-trait; the output says so.

## Scope

The regression is ordinary least squares on a 1-in-10 sample and one
chromosome; OLS treats participants as unrelated. To extend: `SAMPLE_MOD=1`
for everyone; build the HapMap3 subset for chromosomes 1–22, score each, and
add the per-person `SCORE1_SUM` columns; use weights for your own trait.
