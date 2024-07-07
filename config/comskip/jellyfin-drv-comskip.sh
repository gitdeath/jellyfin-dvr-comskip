#!/usr/bin/env bash

# Define paths and variables
comchap="/config/comskip/comchap"
comskip="/opt/Comskip/comskip"
lockfile="/tmp/comchap.lock"
comskip_ini="/config/comskip/comskip.ini"
ffmpeg="/usr/local/bin/ffmpeg"
output_root="/media/livetv"


# Function to extract output directory from .nfo file
get_output_directory() {
    local nfo_file="$1"
    local title=$(grep "<title>" "$nfo_file" | sed -e 's/<[^>]*>//g' | xargs)  # Use xargs to trim any leading/trailing whitespace
    echo "$output_root/$title"
}

# Function to process the video file
process_video() {
    local video_file="$1"
    local original_filename=$(basename "$video_file")
    local nfo_file="${video_file%.*}.nfo"
    local output_directory=$(get_output_directory "$nfo_file")
    local output_file="${output_directory}/${original_filename%.*}.mkv"

    # Ensure the output directory exists
    mkdir -p "$output_directory"

    # Check for lock file and retry logic
    attempt=0
    while [[ -f "$lockfile" && $attempt -lt 15 ]]; do
        echo "Waiting for comchap to finish processing. Attempt: $((attempt + 1)) of 10..."
        sleep 600  # 10 minutes
        ((attempt++))
    done

    if [[ -f "$lockfile" ]]; then
        echo "Error: comchap is still running after 10 attempts. Exiting."
        exit 1
    fi

    # Run comchap with specified parameters
    "$comchap" --comskip="$comskip" --lockfile="$lockfile" --comskip-ini="$comskip_ini" --ffmpeg="$ffmpeg" "$video_file" "$output_file"

    # Check if comchap failed to generate output file
    if [[ ! -f "$output_file" ]]; then
        echo "Error running comchap or output file not created: $output_file"
        exit 1
    fi

    # Clean up original files and directory
    rm -f "$video_file"  # Remove original video file
    rm -f "$nfo_file"    # Remove .nfo file
    rmdir "$(dirname "$video_file")"  # Remove parent directory if empty
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

# Process the video file
process_video "$video_file"
