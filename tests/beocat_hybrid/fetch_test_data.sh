#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Fetch a real HYBRID phage test dataset for phinder and build a samplesheet.
#
# Isolate: Pseudomonas phage BRkr  (ENA biosample SAMD00596621)
#   short reads (paired, DNBSEQ) : DRR459602_1 / DRR459602_2
#   long reads  (ONT MinION)     : DRR459603_1
#
# Both come from the SAME isolate, so the hybrid assembly is scientifically valid.
# Run this on a Beocat LOGIN node (it has internet); compute nodes may not.
#
# Usage:
#   bash fetch_test_data.sh [OUTDIR]
#   SUBSAMPLE=0 bash fetch_test_data.sh   # download full data, skip subsampling
# ---------------------------------------------------------------------------
set -euo pipefail

OUTDIR="${1:-$PWD/test_hybrid_data}"
SUBSAMPLE="${SUBSAMPLE:-1}"      # 1 = subsample (fast test), 0 = keep full data
# Subsample fractions (Pseudomonas phage ~90 kb assumed):
#   short 2.49 Gb -> ~0.004 ≈ 100x ; long 72 Mb -> ~0.2 ≈ 150x (filtlong trims further)
SHORT_FRAC="${SHORT_FRAC:-0.004}"
LONG_FRAC="${LONG_FRAC:-0.2}"
SEED="${SEED:-100}"

ENA=ftp.sra.ebi.ac.uk/vol1/fastq
mkdir -p "$OUTDIR"
cd "$OUTDIR"

echo ">> downloading short reads (DRR459602, paired) ..."
wget -nc -q "https://$ENA/DRR459/DRR459602/DRR459602_1.fastq.gz"
wget -nc -q "https://$ENA/DRR459/DRR459602/DRR459602_2.fastq.gz"
echo ">> downloading long reads (DRR459603, ONT) ..."
wget -nc -q "https://$ENA/DRR459/DRR459603/DRR459603_1.fastq.gz"

R1=DRR459602_1.fastq.gz; R2=DRR459602_2.fastq.gz; LR=DRR459603_1.fastq.gz

if [[ "$SUBSAMPLE" == "1" ]]; then
    if ! command -v seqtk >/dev/null; then
        echo "!! seqtk not found (try: module load SeqTK  or  conda install -c bioconda seqtk)." >&2
        echo "!! Re-run with SUBSAMPLE=0 to use the full (large, slow) dataset instead." >&2
        exit 1
    fi
    echo ">> subsampling short reads (frac=$SHORT_FRAC) and long reads (frac=$LONG_FRAC) ..."
    seqtk sample -s"$SEED" DRR459602_1.fastq.gz "$SHORT_FRAC" | gzip > brkr_R1.fastq.gz
    seqtk sample -s"$SEED" DRR459602_2.fastq.gz "$SHORT_FRAC" | gzip > brkr_R2.fastq.gz
    seqtk sample -s"$SEED" DRR459603_1.fastq.gz "$LONG_FRAC"  | gzip > brkr_long.fastq.gz
    R1=brkr_R1.fastq.gz; R2=brkr_R2.fastq.gz; LR=brkr_long.fastq.gz
fi

# Write the hybrid samplesheet with ABSOLUTE paths (one hybrid sample).
SS="$OUTDIR/samplesheet_hybrid.csv"
{
    echo "sample,fastq_1,fastq_2,long_fastq,fasta,platform"
    echo "brkr_hybrid,$OUTDIR/$R1,$OUTDIR/$R2,$OUTDIR/$LR,,hybrid"
} > "$SS"

echo
echo ">> done. samplesheet:"
cat "$SS"
echo
echo ">> next: edit run_beocat_test.sh if needed, then  sbatch run_beocat_test.sh"
