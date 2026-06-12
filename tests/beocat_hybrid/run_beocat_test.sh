#!/bin/bash
# ---------------------------------------------------------------------------
# Beocat head-job for the phinder HYBRID smoke test.
# This sbatch only runs the Nextflow DRIVER; each pipeline process becomes its
# own SLURM job (executor='slurm' in -profile beocat). So: small cpu/mem, long walltime.
#
#   1) bash fetch_test_data.sh          # on a LOGIN node (downloads + samplesheet)
#   2) sbatch run_beocat_test.sh        # submit this driver
# ---------------------------------------------------------------------------
#SBATCH --job-name=phinder_hybrid_test
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --mem=8G
#SBATCH --time=2-00:00:00
#SBATCH --output=phinder_test.%j.out
#SBATCH --error=phinder_test.%j.err

set -euo pipefail

# --- adjust these to your paths -------------------------------------------------
PIPELINE_DIR="${PIPELINE_DIR:-$HOME/phinder-multimode}"     # cloned repo
DATA_DIR="${DATA_DIR:-$PWD/test_hybrid_data}"               # output of fetch_test_data.sh
export NXF_SINGULARITY_CACHEDIR="${NXF_SINGULARITY_CACHEDIR:-$PWD/singularity_cache}"
mkdir -p "$NXF_SINGULARITY_CACHEDIR"

# Beocat modules — VERIFY exact names with: module spider nextflow / module spider singularity
module purge
module load Nextflow
module load SingularityCE 2>/dev/null || module load Singularity

nextflow run "$PIPELINE_DIR" \
    -profile beocat \
    --input   "$DATA_DIR/samplesheet_hybrid.csv" \
    --outdir  "$PWD/phinder_test_results" \
    --skip_vibrant --skip_diamond \
    -resume

# ------------------------------------------------------------------------------
# DB notes:
#  * --skip_vibrant / --skip_diamond  : those steps need user DBs (vibrant_db, prophage_db);
#    left off for this first smoke test.
#  * CheckV + Pharokka DBs are DOWNLOADED at runtime by the pipeline. If Beocat COMPUTE
#    nodes have no internet, pre-stage on a login node and pass them instead:
#        --checkv_db /path/to/checkv-db  --pharokka_db /path/to/pharokka-db
#    Also pre-pull containers into $NXF_SINGULARITY_CACHEDIR on a login node first.
# ------------------------------------------------------------------------------
