#!/bin/bash

# ============================================
# Interactive Alignment Script using NVIDIA Clara Parabricks fq2bam
# Author: Murilo Porfírio & としろ
# ============================================

# ===================== Introduction =====================
echo "==================================================="
echo " FASTQ to BAM Alignment using Parabricks fq2bam "
echo "==================================================="
echo ""

# Confirm start
echo "Do you want to start the interactive setup? (yes/no)"
read CONFIRM_START
if [[ "$CONFIRM_START" != "yes" ]]; then
  echo "Script terminated."
  exit 0
fi

# ===================== Input FASTQ Directory =====================
echo "Enter FULL path to the directory containing your FASTQ files:"
read INPUT_DIR
if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Error: Directory '$INPUT_DIR' not found."
  exit 1
fi

echo "FASTQ files available:"
ls "$INPUT_DIR"/*.fastq.gz
echo ""

echo "Enter the FASTQ filenames (space separated, in R1 R2 order for each sample):"
read -a FASTQ_FILES
NUM_FILES=${#FASTQ_FILES[@]}
if (( $NUM_FILES % 2 != 0 )); then
  echo "Error: You must provide an even number of FASTQ files (R1 and R2 for each sample)."
  exit 1
fi

# ===================== Reference Genome =====================
echo ""
echo "Reference Genome:"
echo "Provide the full path to your reference genome FASTA file (example: hg38.fa)."
read GENOME_FA

if [[ ! -f "$GENOME_FA" ]]; then
  echo "Error: File '$GENOME_FA' not found."
  exit 1
fi
if [[ ! -s "$GENOME_FA" ]]; then
  echo "Error: File '$GENOME_FA' is empty."
  exit 1
fi
HEADER_CHECK=$(grep "^>" "$GENOME_FA" | wc -l)
if [[ "$HEADER_CHECK" -eq 0 ]]; then
  echo "Error: File '$GENOME_FA' does not contain any FASTA headers (lines starting with '>')."
  exit 1
fi
echo "Reference genome file check: OK"

# ===================== KnownSites VCFs =====================
echo ""
echo "KnownSites VCF files (for BQSR):"
echo "These are VCF files with known variants for your genome build."
echo "Common examples: dbSNP, Mills Indels, 1000G SNPs."
echo "Do you have knownSites VCF files to use? (yes/no)"
read USE_KNOWNSITES
KNOWN_SITES_PARAM=""
KNOWN_SITES_MOUNT=""

if [[ "$USE_KNOWNSITES" == "yes" ]]; then
  echo "How many knownSites VCF files do you want to use?"
  read NUM_KS
  for ((ks=1; ks<=NUM_KS; ks++)); do
    echo "Enter FULL path to knownSites VCF file #$ks:"
    read KS_FILE
    if [[ ! -f "$KS_FILE" ]]; then
      echo "Error: File '$KS_FILE' not found."
      exit 1
    fi
    KS_DIR=$(dirname "$KS_FILE")
    KS_BASENAME=$(basename "$KS_FILE")
    KNOWN_SITES_PARAM="$KNOWN_SITES_PARAM --knownSites /knownsites$ks/$KS_BASENAME"
    KNOWN_SITES_MOUNT="$KNOWN_SITES_MOUNT -v $KS_DIR:/knownsites$ks"
  done
fi

# ===================== Docker User UID =====================
echo ""
echo "Docker User Mode:"
echo "To avoid permission issues on output files, you can run Docker as a specific user."
echo "Enter the numeric UID (e.g., 1006), or 'no' to run as root, or 'exit' to quit:"
read CUSTOM_UID
if [[ "$CUSTOM_UID" == "exit" ]]; then
  echo "Script terminated."
  exit 0
fi
if [[ "$CUSTOM_UID" =~ ^[0-9]+$ ]]; then
  USE_USER="--user $CUSTOM_UID"
  USER_MODE="UID $CUSTOM_UID"
else
  USE_USER=""
  USER_MODE="root"
fi

# ===================== GPU Selection =====================
echo ""
echo "GPU Selection:"
echo "Checking available GPUs..."
TOTAL_GPUS=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
echo "Total GPUs available: $TOTAL_GPUS"

echo ""
echo "=== Current GPU Usage ==="
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv

echo ""
echo "Enter the GPU indexes you want to use (comma-separated, e.g., 0 or 1,3,4):"
read SELECTED_GPUS
GPU_PARAM="device=$SELECTED_GPUS"

# ===================== Low Memory Mode =====================
echo ""
echo "Low Memory Mode (--low-memory):"
echo "Use this if your GPU has less than 40GB VRAM (ex: T4, V100, A100 20GB)."
echo "It reduces GPU memory usage but may slow down the process."
echo "Do you want to enable low memory mode? (yes/no)"
read USE_LOW_MEMORY
if [[ "$USE_LOW_MEMORY" == "yes" ]]; then
  LOW_MEMORY_PARAM="--low-memory"
else
  LOW_MEMORY_PARAM=""
fi

# ===================== Temporary Directory =====================
echo ""
echo "Temporary Directory (--tmp-dir):"
echo "Parabricks creates large temporary files. For better performance, use a fast local SSD if available."
echo "Enter the directory path for temporary files, or type 'default' to skip:"
read TMP_DIR
if [[ "$TMP_DIR" != "default" ]]; then
  TMP_DIR_PARAM="--tmp-dir /tmp_dir"
  TMP_DIR_MOUNT="-v $TMP_DIR:/tmp_dir"
else
  TMP_DIR_PARAM=""
  TMP_DIR_MOUNT=""
fi

# ===================== CPU Threads =====================
echo ""
echo "CPU Threads (--bwa-cpu-thread-pool):"
echo "Defines how many CPU threads BWA should use. Recommended: at least 16 threads per GPU."
echo "Enter number of CPU threads:"
read CPU_THREADS
CPU_THREADS_PARAM="--bwa-cpu-thread-pool $CPU_THREADS"

# ===================== GPU Sort and Write =====================
echo ""
echo "GPU Accelerated Sorting and Writing (--gpusort --gpuwrite):"
echo "Improves speed by using the GPU for BAM sorting and writing."
echo "Do you want to enable GPU sorting and writing? (yes/no)"
read GPU_OPTIMIZE
if [[ "$GPU_OPTIMIZE" == "yes" ]]; then
  GPU_OPT_PARAM="--gpusort --gpuwrite"
else
  GPU_OPT_PARAM=""
fi

# ===================== GPUDirect Storage =====================
echo ""
echo "GPUDirect Storage (GDS --use-gds):"
echo "Allows direct disk-to-GPU data transfer, skipping CPU memory."
echo "Only enable this if your system is configured for GDS (rare in standard servers)."
echo "Do you want to enable GDS? (yes/no)"
read USE_GDS
if [[ "$USE_GDS" == "yes" ]]; then
  GDS_PARAM="--use-gds"
else
  GDS_PARAM=""
fi

# ===================== Output Directory =====================
TIMESTAMP=$(date +"%d-%m-%Y_%Hh%Mm")
OUTPUT_DIR="$INPUT_DIR/4-parabricks_output_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

# ===================== Recap =====================
echo ""
echo "========== RECAP =========="
echo "FASTQ directory: $INPUT_DIR"
echo "FASTQ files:"
for file in "${FASTQ_FILES[@]}"; do echo "- $file"; done
echo ""
echo "Reference genome: $GENOME_FA"
echo ""
if [[ "$USE_KNOWNSITES" == "yes" ]]; then
  echo "KnownSites VCF files:"
  echo "$KNOWN_SITES_PARAM" | sed 's/--knownSites /\n- /g'
else
  echo "KnownSites: Not provided"
fi
echo ""
echo "Docker will run as: $USER_MODE"
echo "Selected GPUs: $SELECTED_GPUS"
echo "Low memory mode: $LOW_MEMORY_PARAM"
echo "Temporary directory: $TMP_DIR"
echo "CPU threads: $CPU_THREADS"
echo "GPU sort/write: $GPU_OPT_PARAM"
echo "GDS: $GDS_PARAM"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "==========================="
echo ""
echo "Do you want to start the alignment now? (yes/no)"
read FINAL_CONFIRM
if [[ "$FINAL_CONFIRM" != "yes" ]]; then
  echo "Execution cancelled."
  exit 0
fi

# ===================== Run fq2bam =====================
echo ""
echo "Starting alignment with Parabricks fq2bam..."

for ((i=0; i<NUM_FILES; i+=2)); do
  SAMPLE_R1=${FASTQ_FILES[$i]}
  SAMPLE_R2=${FASTQ_FILES[$((i+1))]}
  SAMPLE_NAME=$(basename "$SAMPLE_R1" | cut -d '_' -f1)

  OUTPUT_BAM="/outputdir/${SAMPLE_NAME}_aligned.bam"
  RECAL_FILE="/outputdir/${SAMPLE_NAME}_recal.txt"

  echo ""
  echo "Processing sample: $SAMPLE_NAME"

  docker run --rm --gpus "$GPU_PARAM" $USE_USER \
    -v "$INPUT_DIR":/workdir \
    -v "$OUTPUT_DIR":/outputdir \
    -v "$(dirname "$GENOME_FA")":/refdir \
    $KNOWN_SITES_MOUNT \
    $TMP_DIR_MOUNT \
    nvcr.io/nvidia/clara/clara-parabricks:4.5.1-1 \
    pbrun fq2bam \
    --ref /refdir/$(basename "$GENOME_FA") \
    --in-fq /workdir/$SAMPLE_R1 /workdir/$SAMPLE_R2 \
    --out-bam $OUTPUT_BAM \
    --out-recal-file $RECAL_FILE \
    $KNOWN_SITES_PARAM \
    $LOW_MEMORY_PARAM \
    $TMP_DIR_PARAM \
    $CPU_THREADS_PARAM \
    $GPU_OPT_PARAM \
    $GDS_PARAM
done

echo ""
echo "===================================================="
echo " All samples processed! Output BAM files are in:"
echo " $OUTPUT_DIR"
echo "===================================================="
exit 0
