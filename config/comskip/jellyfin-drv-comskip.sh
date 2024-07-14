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
	mkdir -p "$log_dir"
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
    ffmpeg -i "concat:$(ls -v "$dir"/*.ts | tr '\n' '|')" -c copy "$merged_file"
    echo "$merged_file"
}

# Function to convert .ts files to .mp4 in the original directory
convert_to_mp4() {
    local ts_file="$1"
    local mp4_file="${ts_file%.*}.mp4"  # Output file in the same directory as original .ts file
    ffmpeg -hwaccel qsv -c:v h264_qsv -i "$ts_file" -c:v h264_qsv -c:a aac -strict experimental -b:a 192k "$mp4_file"
    echo "$mp4_file"  # Only echo the resulting filename
}
# Function to process the video file
process_video() {
    local video_file="$1"
    local original_filename=$(basename "$video_file")
    local output_directory=$(dirname "$video_file")
    local parent_directory=$(basename "$(dirname "$video_file")")

    # Check for lock file and retry logic
    local attempt=0
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
        echo "Merging .ts files in $vidoe_dir to $merged_file"
        video_file=$(merge_ts_files "$video_dir")
    fi

    # Convert .ts to .mp4 in the original directory
    local mp4_file
    echo "Convert $ts_file to mp4"
    mp4_file=$(convert_to_mp4 "$video_file")

    # Prepare comchap parameters
    echo "Locate commercials"
    local comchap_params=("--comskip=$comskip" "--lockfile=$lockfile" "--comskip-ini=$comskip_ini" "--ffmpeg=$ffmpeg")

    if [[ $verbose -eq 1 ]]; then
        comchap_params+=("--verbose")
    fi

    # Run comchap with specified parameters on the .mp4 file  
    "${comchap}" "${comchap_params[@]}" "$mp4_file"
    comchap_exit_code=$?

    # Check the exit code of comchap
    if [[ $comchap_exit_code -ne 0 ]]; then
        echo "Error: comchap did not exit cleanly with exit code $comchap_exit_code"
        exit 1
    fi

    # Debugging: Check existence of the processed file (same as input .mp4)
    echo "Checking if processed file exists: $mp4_file"
    ls -l "$mp4_file"

    # Clean up original .ts and .nfo files (only if comchap exits cleanly)
    find "$video_dir" -type f \( -name "*.ts" -o -name "*.nfo" \) -delete

    # Ensure the output directory exists
    if ! mkdir -p "$output_root/$parent_directory"; then
        echo "Failed to create output directory: $output_root/$parent_directory"
        exit 1  # Exit the script with a non-zero status indicating failure
    fi

    # Move the processed .mp4 file to the output directory in output_root with original filename
    echo "Move $mp4_file to $output_root/$parent_directory/${original_filename%.*}.mp4"
    mv "$mp4_file" "$output_root/$parent_directory/${original_filename%.*}.mp4"

    # Remove parent directory if it is empty
    rmdir "$video_dir" &> /dev/null || echo "Failed to remove parent directory: $video_dir"

    # Force Jellyfin to scan
    curl -X POST http://localhost:8096/library/refresh?api_key<apikey>
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
