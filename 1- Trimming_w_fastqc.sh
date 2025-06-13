#!/bin/bash

echo "Script started."
echo "If you pasted this script into the terminal, press Enter to continue (this prevents accidental auto-execution)."
read

echo "How many patients do you want to process? (or type 'exit' to quit)"
read N
if [[ "$N" == "exit" ]]; then exec bash; fi
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "Invalid value. Please enter an integer."
  exec bash
fi

TOTAL_FILES=$((N * 2))
echo "This corresponds to $TOTAL_FILES files (R1 and R2 per patient). Is that correct? (yes/no or 'exit')"
read CONFIRM_TOTAL
if [[ "$CONFIRM_TOTAL" == "exit" ]]; then exec bash; fi
if [[ "$CONFIRM_TOTAL" != "yes" ]]; then
  echo "Script aborted. Please check your input before proceeding."
  exec bash
fi

echo "Are all files in the same directory? (yes/no or 'exit')"
read SAME_DIR
if [[ "$SAME_DIR" == "exit" ]]; then exec bash; fi
if [[ "$SAME_DIR" != "yes" ]]; then
  echo "Please consolidate all files into a single directory before continuing."
  exec bash
fi

echo "Enter the full path to the directory with the files (no trailing slash, or type 'exit' to quit):"
read INPUT_DIR
if [[ "$INPUT_DIR" == "exit" ]]; then exec bash; fi
if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Error: directory '$INPUT_DIR' not found."
  exec bash
fi

echo "Listing .fastq or .fastq.gz files in '$INPUT_DIR'..."
find "$INPUT_DIR" -maxdepth 1 -type f \( -name "*.fastq" -o -name "*.fastq.gz" \)

echo "Do you want to process all the files listed above? (yes/no or 'exit')"
read PROCESS_ALL
if [[ "$PROCESS_ALL" == "exit" ]]; then exec bash; fi

if [[ "$PROCESS_ALL" != "yes" ]]; then
  echo "Enter the EXACT names of the files you want to trim, separated by space (or 'exit' to quit):"
  read -a FILES
  if [[ "${FILES[0]}" == "exit" ]]; then exec bash; fi
else
  FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f \( -name "*.fastq" -o -name "*.fastq.gz" \) -printf "%f\n"))
fi

TIMESTAMP=$(date +"%d-%m-%Y_%Hh%Mm")
OUTPUT_DIR="$INPUT_DIR/2-trimmed_files_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

echo "Trimmed files will be saved in: $OUTPUT_DIR"
echo "Do you want to continue? (yes/no or 'exit')"
read CONTINUE
if [[ "$CONTINUE" == "exit" ]]; then exec bash; fi
if [[ "$CONTINUE" != "yes" ]]; then
  echo "Process cancelled."
  exec bash
fi

TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
DEFAULT_RAM_GB=4
SUGGESTED_RAM_GB=$((TOTAL_RAM_GB / 2))

echo ""
echo "This script typically uses around ${DEFAULT_RAM_GB}GB of RAM."
echo "The server has $TOTAL_RAM_GB GB. We suggest using up to ${SUGGESTED_RAM_GB}GB."
echo "How much RAM would you like to allocate (in GB)? (or 'exit')"
read RAM
if [[ "$RAM" == "exit" ]]; then exec bash; fi
if ! [[ "$RAM" =~ ^[0-9]+$ ]]; then
  echo "Invalid value for RAM."
  exec bash
fi

echo ""
echo "This script uses the Trim Galore! tool, which internally calls Cutadapt for trimming."
echo "Although Cutadapt supports multithreading, the Docker image currently used does not expose that option."
echo "Therefore, the trimming will run in single-threaded mode by default."
echo "If you need multithreading, consider using a newer Docker image that supports the --cores parameter for Cutadapt."

echo ""
echo "Do you want to run Docker with a specific user (--user UID)?"
echo "Enter the desired UID (e.g., 1006), or 'no' to continue as default:"
read CUSTOM_UID
if [[ "$CUSTOM_UID" == "exit" ]]; then exec bash; fi
if [[ "$CUSTOM_UID" =~ ^[0-9]+$ ]]; then
  USE_USER="--user $CUSTOM_UID"
elif [[ "$CUSTOM_UID" == "no" ]]; then
  USE_USER=""
else
  echo "Invalid input. Please enter a UID number or 'no'."
  exec bash
fi

# Trim Galore parameters
echo ""
echo "Set the base quality cutoff for trimming (default is 20)."
echo "Trims low-quality ends. Typical: 15–30. WES: 20; WGS: 25."
read QUALITY
if [[ -z "$QUALITY" ]]; then QUALITY=20; fi

echo ""
echo "Set the minimum read length to keep after trimming (default is 20)."
echo "Shorter reads are discarded. Typical: 20–75. WES: 30; WGS: 50."
read MIN_LENGTH
if [[ -z "$MIN_LENGTH" ]]; then MIN_LENGTH=20; fi

echo ""
echo "Would you like to manually specify the adapter type? (illumina/nextera/auto)"
read ADAPTER_TYPE
if [[ "$ADAPTER_TYPE" == "illumina" ]]; then
  ADAPTER_OPTION="--illumina"
elif [[ "$ADAPTER_TYPE" == "nextera" ]]; then
  ADAPTER_OPTION="--nextera"
else
  ADAPTER_OPTION=""
fi

echo ""
echo "Do you want to run FastQC after trimming? (yes/no)"
read RUN_FASTQC
if [[ "$RUN_FASTQC" == "yes" ]]; then
  FASTQC_OPTION="--fastqc"
else
  FASTQC_OPTION="--no_fastqc"
fi

echo ""
echo "========= FINAL SUMMARY ========="
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Files to be processed:"
for file in "${FILES[@]}"; do
  echo "- $file"
done
echo "RAM: $RAM GB"
echo "Docker UID: ${CUSTOM_UID:-default}"
echo "Quality: $QUALITY"
echo "Min length: $MIN_LENGTH"
echo "Adapter: ${ADAPTER_TYPE:-auto}"
echo "Run FastQC: $RUN_FASTQC"
echo "================================="
echo "Shall we begin? (yes/no or 'exit')"
read FINAL_CONFIRM
if [[ "$FINAL_CONFIRM" == "exit" ]]; then exec bash; fi
if [[ "$FINAL_CONFIRM" != "yes" ]]; then
  echo "Execution cancelled."
  exec bash
fi

START_TIME=$(date +%s)
LOG_FILE="$OUTPUT_DIR/trimming_log_$(date +"%Y-%m-%d_%H%M").log"
echo "Log file: $LOG_FILE"
echo "Starting trimming..." | tee -a "$LOG_FILE"

i=0
while [[ $i -lt ${#FILES[@]} ]]; do
  R1="${FILES[$i]}"
  R2="${FILES[$((i+1))]}"
  echo "Processing: $R1 and $R2" | tee -a "$LOG_FILE"

  docker run --rm \
    -v "$INPUT_DIR":/data \
    $USE_USER \
    biowardrobe2/trimgalore:v0.4.4 \
    trim_galore --paired \
      --quality "$QUALITY" \
      --length "$MIN_LENGTH" \
      $ADAPTER_OPTION \
      $FASTQC_OPTION \
      "/data/$R1" "/data/$R2" \
      -o "/data/2-trimmed_files_$TIMESTAMP" 2>&1 | tee -a "$LOG_FILE"

  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Error processing $R1 and $R2" | tee -a "$LOG_FILE"
  else
    echo "Completed $R1 and $R2" | tee -a "$LOG_FILE"
  fi

  i=$((i + 2))
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
echo "Trimming completed." | tee -a "$LOG_FILE"
echo "Total runtime: $TOTAL_TIME seconds" | tee -a "$LOG_FILE"

echo "------------------------------------------------------"
echo "All trimming steps are complete."
echo "Results saved in: $OUTPUT_DIR"
echo "Log file: $LOG_FILE"
echo "Total processing time: $TOTAL_TIME seconds"
echo "------------------------------------------------------"
