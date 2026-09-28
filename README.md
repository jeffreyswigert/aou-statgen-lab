# Statistical genetics on All of Us: hands-on with your Workbench

Materials for a one-hour lab run entirely on **real All of Us v9 data**
(Controlled Tier required): 20 minutes of instruction, then 40 hands-on
minutes in which you

1. **explore** a real variable (summary statistics and histograms),
2. **construct a phenotype** from raw CDR records — QC'd,
   plausibility-bounded, one row per person,
3. **build a PGI** with PLINK on a single chromosome, from GWAS summary
   statistics posted to the shared USC pod bucket, and
4. **run a basic regression** that incorporates the PGI.

The deliverable is confidence with your *actual* Workbench: real queries,
real files, real conventions, real rules.

## Quick start (on your AoU Workbench VM)

Open a Terminal from the JupyterLab Launcher, then:

```bash
git clone https://github.com/jeffreyswigert/aou-statgen-lab.git
cd aou-statgen-lab
cp config.example.sh config.sh     # then fill the values your instructor projects
bash scripts/00_preflight.sh
bash scripts/01_fetch_genotypes.sh
bash scripts/02_build_phenotype.sh
bash scripts/03_explore_phenotype.sh
bash scripts/04_build_pgi.sh
bash scripts/05_pgi_regression.sh
bash scripts/06_save_run.sh
```

Follow along in `handout.pdf`; `slides.pdf` is the deck. There is **no
answer key** — your numbers are real; the handout gives plausibility checks
instead. Figures land in `results/` as PNGs; open them from the JupyterLab
file browser.

## Reading the code IS the lab

The scripts are written for people who have seen very little code. Every
step carries a comment explaining not just *what* it does but *why* —
which alleles get counted, why the median, why counts print rounded, why a
failed match is silent and how we catch it. Read each script before you
run it (`less scripts/02_build_phenotype.sh`, press `q` to exit), and try
the **TRY IT** experiment at the bottom of each one. Start with
`scripts/common.sh` — it explains the shell basics every other file uses.

## Ground rules, baked into the scripts

- **Person-level files never leave the workspace.** Downloaded data and
  results are git-ignored; the save archive goes only to your workspace
  bucket.
- **Printed outputs are aggregate and screened**: counts round to the
  nearest 100, counts of 1–20 are suppressed, and the save step runs a
  disclosure screen (`scripts/check_disclosure.py`) that **blocks** on
  findings — overriding is an explicit, recorded decision, never an
  accident.
- **Every query is byte-capped** (~$0.16 each at the default).
- **Stop your cloud app when done.** VMs bill while idle.

## GitHub in the All of Us flow

This repo is itself the demonstration: code is developed and versioned
*outside* the Controlled Tier perimeter, then `git clone`d onto the
Workbench VM (public repos need no credentials there) and updated with
`git pull`. Code crosses the boundary freely, in both directions; **data
never does**. Version code, config *templates*, and docs; never commit
person-level files, results, filled configs (`config.sh` is git-ignored on
purpose), or notebooks with outputs — a saved `.ipynb` embeds its cell
outputs. Treat `.gitignore` as a compliance tool. The save step records
this repo's commit hash in every run manifest (`code_version=`, with a
`-dirty` flag for uncommitted edits), so each archived run names the exact
code that produced it.

## After the lab

These scripts demonstrate a workflow, not a complete analysis protocol:
ordinary regression does not account for relatives, five PCs are a
convention rather than a guarantee, and a one-chromosome PGI is
deliberately partial. To scale up: set `SAMPLE_MOD=1` for the full cohort,
loop `CHROM` over 1–22 and sum the `.sscore` SUM columns, and swap in your
own trait's concept ID and weights. A free local sandbox mirroring the
platform's file conventions lets you debug all of this on your laptop
before paying for a VM — ask your instructor for it.
