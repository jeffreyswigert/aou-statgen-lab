# Statistical genetics on All of Us: Lab 1

A one-hour, step-by-step lab on **All of Us v9 Controlled Tier data**
(Controlled Tier access required). Each step is one script:

| Step | What it does | Script |
|---|---|---|
| 0 | Check tools and settings | `scripts/00_setup.sh` |
| 1 | Put chromosome-22 genotypes (HapMap3 variants) and the ancestry file on the VM: copy the ready-made subset, or build it from All of Us's own files | `scripts/01_fetch_genotypes.sh` |
| 2 | Build a height phenotype from the CDR (BigQuery), one row per person | `scripts/02_build_phenotype.sh` |
| 3 | Summary table and two figures | `scripts/03_explore_phenotype.sh` |
| 4 | Build a polygenic index (PGI) with PLINK; histogram of the standardized PGI | `scripts/04_build_pgi.sh` |
| 5 | Regress standardized height on the standardized PGI, age, sex, and 5 PCs | `scripts/05_pgi_regression.sh` |
| 6 | Check `results/`, write a manifest, archive the run to the workspace bucket | `scripts/06_save_run.sh` |

`slides.pdf` is the deck (each step: what it does, then the commands and
code). `COMMANDS.txt` lists every command used in the lab, in order, with a
note on each, to copy and paste from. `cheatsheet.pdf` lists terminal,
BigQuery, cloud storage, PLINK, and git commands for your own projects.

Every script is written to be read: each step has a comment saying what it
does, why, and what the same step looks like in your own project. Read
`scripts/common.sh` first if bash is new to you.

## Quick start (on your All of Us Workbench VM)

Create a JupyterLab app (standard VM, n1-standard-8 = 8 CPUs / 30 GB, 100 GB disk, autostop
1 hour), open a Terminal from the Launcher, then:

```bash
git clone https://github.com/jeffreyswigert/aou-statgen-lab.git
cd aou-statgen-lab
cp config.example.sh config.sh     # then fill WORKSHOP_BUCKET and BILLING_PROJECT
bash scripts/00_setup.sh
bash scripts/01_fetch_genotypes.sh
bash scripts/02_build_phenotype.sh
bash scripts/03_explore_phenotype.sh
bash scripts/04_build_pgi.sh
bash scripts/05_pgi_regression.sh
bash scripts/06_save_run.sh
```

When you finish, stop the app (Apps tab -> your app -> Stop). Stopping keeps
the app and its disk, so your files are there when you start it again.

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
settings template (`config.example.sh`), and documentation. It should never
hold data, results, the filled-in `config.sh`, or notebook outputs. Step 6 writes
the repository's commit ID into `results/run_manifest.txt`
(`code_version=`, with `-dirty` if files were edited after the commit), so
each archived run names the code that produced it.

## Where the genotypes come from

Every genotype in this lab is All of Us v9 data. All of Us publishes
whole-genome genotypes (the "ACAF threshold" callset) as one file set per
chromosome, in PLINK 2 (`.../acaf_threshold/pgen/`) and PLINK 1
(`.../acaf_threshold/plink_bed/`) formats under
`gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/`. It does not
publish a HapMap3 subset, and the chromosome-22 `.bed` alone is about 250 GB.

`scripts/subset_aou_genotypes.sh` makes the subset: it reads All of Us's
chromosome-22 files, keeps the variants on a public HapMap3 list
(`data/hm3_chr22_hg38.tsv`: rsID, GRCh38 position, alleles; no participant
data), keeps a 1-in-`SAMPLE_MOD`
sample of people, and renames the variants from `chr22:pos:ref:alt` to
rsIDs. Step 1 gets the result one of two ways, set by `GENO_SOURCE` in
`config.sh`:

- `bucket` (default): copy the instructor's ready-made subset from
  `$WORKSHOP_BUCKET/genotypes/` (built before class with
  `scripts/prep/make_hm3_subset.sh`, which runs the same subset script for
  everyone and uploads the result).
- `aou`: run the subset script yourself, straight from All of Us's file.
  If the Workbench has mounted the dataset under `~/workspace`, set
  `ACAF_DIR` to that folder and PLINK reads the file in place; otherwise
  the file is copied to the VM first (large disk, long autostop).

The HapMap3 list is the chromosome-22 part of the variant map published
with LDpred2: Privé, Florian (2020), "European LD reference", figshare,
<https://doi.org/10.6084/m9.figshare.13034123.v3>, file `map.rds`, license
CC BY 4.0. We kept the 15,414 chromosome-22 variants that have a GRCh38
position and wrote five columns: `rsid`, `chr`, `pos` (GRCh38), `a1`, `a2`.
For another chromosome, make the same file from `map.rds` and name it with
`HM3_LIST`.

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

The regression is ordinary least squares on one chromosome; OLS treats
participants as unrelated. `SAMPLE_MOD=10` keeps 1 person in 10 for a quick
trial run. To extend: `GENO_SOURCE=aou CHROM=<n> HM3_LIST=<list>` to build other chromosomes, score
each, and add the per-person `SCORE1_SUM` columns; use weights for your own
trait.
