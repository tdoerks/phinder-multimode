# Beocat hybrid smoke test

A real same-isolate **hybrid** phage dataset for exercising phinder's Unicycler-hybrid path
end-to-end on Beocat.

**Dataset:** *Pseudomonas phage BRkr* (ENA biosample `SAMD00596621`)
- short reads (paired, DNBSEQ): `DRR459602_1` / `DRR459602_2`
- long reads (ONT MinION): `DRR459603_1`

Both runs are from the same isolate, so the hybrid assembly is biologically valid.

## Run it

```bash
# 1) On a Beocat LOGIN node (has internet): fetch + subsample + build samplesheet
bash fetch_test_data.sh
#    -> writes test_hybrid_data/ and test_hybrid_data/samplesheet_hybrid.csv
#    full data instead of subsampled:  SUBSAMPLE=0 bash fetch_test_data.sh   (slow)

# 2) Submit the Nextflow driver job
sbatch run_beocat_test.sh
```

## What it runs
QC → fastp/filtlong → **Unicycler hybrid** → QUAST → CheckV → Pharokka → MultiQC + summary.
VIBRANT and DIAMOND are skipped (they need user-supplied DBs); CheckV + Pharokka DBs download
at runtime — see the DB note in `run_beocat_test.sh` if Beocat compute nodes lack internet.

## Tunables
- `SHORT_FRAC` / `LONG_FRAC` in `fetch_test_data.sh` — subsample depth (defaults ≈100–150x).
- `PIPELINE_DIR`, `DATA_DIR`, `NXF_SINGULARITY_CACHEDIR` in `run_beocat_test.sh`.
- Verify Beocat module names: `module spider nextflow` / `module spider singularity`.
