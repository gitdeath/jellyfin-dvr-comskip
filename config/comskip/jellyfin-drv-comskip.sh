#!/usr/bin/env bash

# Define paths and variables
comchap="/config/comskip/comchap"
comskip="/opt/Comskip/comskip"
lockfile="/tmp/comchap.lock"
comskip_ini="/config/comskip/comskip.ini"
ffmpeg="/usr/local/bin/ffmpeg"
output_root="/media/livetv"
log_dir="/config/log"
verbose=1

# Function to set up logging
setup_logging() {
    if [[ $verbose -eq 1 ]]; then
        log_file="$log_dir/$(date '+%Y_%m_%d')_post_processing.log"
        echo "" >> "$log_file"
        echo "==== Starting new run at $(date) ====" >> "$log_file"
        exec > >(tee -a "$log_file") 2>&1
    fi
}

# Function to merge .ts files using ffmpeg
merge_ts_files() {
    local dir="$1"
    local merged_file="$dir/merged.ts"
    echo "Merging .ts files in $dir to $merged_file"
    ffmpeg -i "concat:$(ls -v "$dir"/*.ts | tr '\n' '|')" -c copy "$merged_file"
    echo "$merged_file"
}

# Function to process the video file
process_video() {
    local video_file="$1"
    local original_filename=$(basename "$video_file")
    local output_directory=$(dirname "$video_file")
    local output_file="${output_directory}/${original_filename%.*}.mkv"

    # Ensure the output directory exists
    if ! mkdir -p "$output_directory"; then
        echo "Failed to create output directory: $output_directory"
        exit 1  # Exit the script with a non-zero status indicating failure
    fi

    # Check for lock file and retry logic
    attempt=0
    while [[ -f "$lockfile" && $attempt -lt 15 ]]; do
        echo "Waiting for comchap to finish processing. Attempt: $((attempt + 1)) of 15..."
        sleep 600  # 10 minutes
        ((attempt++))
    done

    if [[ -f "$lockfile" ]]; then
        echo "Error: comchap is still running after 15 attempts. Exiting."
        exit 1
    fi

    # Merge .ts files if more than one exists
    local video_dir=$(dirname "$video_file")
    if [[ $(find "$video_dir" -maxdepth 1 -name "*.ts" | wc -l) -gt 1 ]]; then
        video_file="$(merge_ts_files "$video_dir")"
    fi

    # Prepare comchap parameters
    comchap_params=("--comskip=$comskip" "--lockfile=$lockfile" "--comskip-ini=$comskip_ini" "--ffmpeg=$ffmpeg")

    if [[ $verbose -eq 1 ]]; then
        comchap_params+=("--verbose")
    fi

    # Run comchap with specified parameters
    "${comchap}" "${comchap_params[@]}" "$video_file" "$output_file"

    # Debugging: Check existence of output file
    echo "Checking if output file was created: $output_file"
    ls -l "$output_file"

    # Check if comchap failed to generate output file
    if [[ ! -f "$output_file" ]]; then
        echo "Error running comchap or output file not created: $output_file"
        exit 1
    fi

    # Clean up original .ts and .nfo files
    find "$(dirname "$video_file")" -type f \( -name "*.ts" -o -name "*.nfo" \) -delete

    # Move output directory (Time) to output_root
    mv "$output_directory" "$output_root"

    # Force Jellyfin to scan
    curl -X POST http://localhost:8096/library/refresh
}

# Main script logic
if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <video_file>"
    exit 1
fi

video_file="$1"

# Check if video file exists
if [[ ! -f "$video_file" ]]; then
    echo "Error: Video file '$video_file' not found."
    exit 1
fi

# Set up logging if verbose mode is enabled
setup_logging

# Process the video file
process_video "$video_file"
