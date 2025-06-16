#!/bin/bash

echo "Starting FASTQ file concatenation script."
echo "Press Enter to confirm you intentionally pasted this script into the terminal."
read

START_TIME=$(date +%s)

# Ask for number of patients
echo "How many patients will you be working with? (or type 'exit' to quit)"
read PATIENTS
if [[ "$PATIENTS" == "exit" ]]; then exec bash; fi
if ! [[ "$PATIENTS" =~ ^[0-9]+$ ]]; then
  echo "Invalid input. Please enter an integer."
  exec bash
fi

# Check if files are paired-end
echo "Are the files paired-end? (yes/no or 'exit')"
read PAIRED
if [[ "$PAIRED" == "exit" ]]; then exec bash; fi
if [[ "$PAIRED" != "yes" ]]; then
  echo "This script currently only supports paired-end data."
  exec bash
fi

# Ask for path to files
echo "Enter the full path to the directory containing the FASTQ files:"
read FILE_PATH
if [[ ! -d "$FILE_PATH" ]]; then
  echo "Directory not found: $FILE_PATH"
  exec bash
fi

# Confirm
echo "Listing FASTQ files in $FILE_PATH:"
ls "$FILE_PATH" | grep -E "\.fastq(\.gz)?$"
echo ""
echo "If not all required files are in the directory, move them there first."
echo "Continue? (yes/no or 'exit')"
read CONTINUE
if [[ "$CONTINUE" == "exit" ]]; then exec bash; fi
if [[ "$CONTINUE" != "yes" ]]; then echo "Cancelled."; exec bash; fi

# Output folder
TIMESTAMP=$(date +"%d-%m-%Y_%Hh%Mm")
OUTPUT_DIR="$FILE_PATH/2-concatenated_fastq_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"
LOG_FILE="$OUTPUT_DIR/concat_log.txt"

echo "Output directory: $OUTPUT_DIR" | tee "$LOG_FILE"

# Process each patient
for ((i=1; i<=PATIENTS; i++)); do
  echo ""
  echo "=== Patient $i ==="
  echo "Enter a unique sample name (e.g., HG008):"
  read SAMPLE_NAME

  echo "How many labels (lanes) does this sample have?"
  read LABELS
  if ! [[ "$LABELS" =~ ^[0-9]+$ ]]; then
    echo "Invalid number." | tee -a "$LOG_FILE"
    continue
  fi

  echo "Enter the exact filenames for the $LABELS R1 files, space-separated:"
  read -a R1_FILES

  echo "Enter the exact filenames for the $LABELS R2 files, space-separated:"
  read -a R2_FILES

  if [[ "${#R1_FILES[@]}" -ne "$LABELS" || "${#R2_FILES[@]}" -ne "$LABELS" ]]; then
    echo "Number of files provided doesn't match number of labels. Skipping $SAMPLE_NAME." | tee -a "$LOG_FILE"
    continue
  fi

  echo "Concatenating patient $SAMPLE_NAME..." | tee -a "$LOG_FILE"

  R1_OUT="$OUTPUT_DIR/${SAMPLE_NAME}_R1_combined.fastq.gz"
  R2_OUT="$OUTPUT_DIR/${SAMPLE_NAME}_R2_combined.fastq.gz"

  for r1 in "${R1_FILES[@]}"; do
    if [[ ! -f "$FILE_PATH/$r1" ]]; then
      echo "Missing file: $r1. Skipping $SAMPLE_NAME." | tee -a "$LOG_FILE"
      continue 2
    fi
    cat "$FILE_PATH/$r1" >> "$R1_OUT"
  done

  for r2 in "${R2_FILES[@]}"; do
    if [[ ! -f "$FILE_PATH/$r2" ]]; then
      echo "Missing file: $r2. Skipping $SAMPLE_NAME." | tee -a "$LOG_FILE"
      continue 2
    fi
    cat "$FILE_PATH/$r2" >> "$R2_OUT"
  done

  echo "Done: $SAMPLE_NAME" | tee -a "$LOG_FILE"
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo ""
echo "All valid samples processed."
echo "Check output directory: $OUTPUT_DIR"
echo "Log saved to: $LOG_FILE"
echo "Total time: $TOTAL_TIME seconds" | tee -a "$LOG_FILE"

exec bash
