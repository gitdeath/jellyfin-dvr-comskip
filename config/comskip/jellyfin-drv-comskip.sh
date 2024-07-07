#!/usr/bin/env bash

# Define paths and variables
comchap="/config/comskip/comchap"
output_root="/media/livetv"

# Function to extract output directory from .nfo file
get_output_directory() {
    local nfo_file="$1"
    local title=$(grep "<title>" "$nfo_file" | sed -e 's/<[^>]*>//g')
    echo "$output_root/$title"
}

# Function to process the video file
process_video() {
    local video_file="$1"
    local original_filename=$(basename "$video_file")
    local nfo_file="${video_file%.*}.nfo"
    local output_directory=$(get_output_directory "$nfo_file")
    local output_file="${output_directory}/${original_filename%.*}.mkv"

    # Run comchap with specified parameters
    "$comchap" "$video_file" "$output_file"

    # Check if comchap failed to generate EDL file or output file
    if [[ $? -ne 0 || ! -f "$output_file" ]]; then
        echo "Error running comchap or output file not created."
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
