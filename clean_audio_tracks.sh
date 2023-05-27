#!/bin/bash


# Get the current date and time
DATE=$(date '+%Y-%m-%d_%H-%M-%S')

# Get the script's name without the extension
SCRIPT_NAME=$(basename "$0" .sh)
SCRIPT_DIR=$(dirname "$0")  # Directory where the script is located
LOG_DIR="$SCRIPT_DIR/log"  # Log directory

# Check if log directory exists, create it if it doesn't
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"

# Create the log file's name
LOG_FILE="log_${SCRIPT_NAME}_${DATE}.log"

# Redirect stdout and stderr to the log file
exec > >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Default directory
DIR="."
# Initialize THREADS with default value
THREADS=1

# List of supported audio codecs
SUPPORTED_AUDIO_CODECS=("aac" "mp3" "wma" "wav" "ogg" "flac" "alac" "eac3" "ac3" "opus")

# List of supported languages
SUPPORTED_LANGUAGES=("eng" "und" null)  # Add more languages if needed

# Colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
AMBER='\033[38;5;208m'
NC='\033[0m' # No Color


usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Search for video files and remove unsupported audio sources."
    echo
    echo "Options:"
    echo "  -d, --dir=DIR         specify the directory to search (default: current directory)"
    echo "  --dry-run             output the files that will be modified and which audio sources will be removed without actually modifying the files"
    echo "  --no-progress         disable progress reporting"
    echo "  -t, --threads=NUM     specify the number of threads (default: 1)"
    echo "  -h, --help            display this help message and exit"
    echo
    echo "Supported audio codecs: ${SUPPORTED_AUDIO_CODECS[*]}"
    echo "Supported languages: ${SUPPORTED_LANGUAGES[*]}"
}


# Handle command-line arguments
for i in "$@"; do
    case $i in
        -f=*|--file=*)
            FILE="${i#*=}"
            shift
        ;;
        -d=*|--dir=*)
            DIR="${i#*=}"
            shift
        ;;
        --dry-run)
            DRY_RUN="true"
            shift
        ;;
        --no-progress)
            NO_PROGRESS="true"
            shift
        ;;
        -t=*|--threads=*)
            THREADS="${i#*=}"
            shift
        ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            # Unknown option
            echo "Unknown option: $i"
            usage
            exit 1
        ;;
    esac
done



# Function to check if an array contains a value
contains() {
    local value="$1"
    shift
    for item; do
        [[ "$item" == "$value" ]] && return 0
    done
    return 1
}


process_video_file() {
    local file="$1"

    local streams_info=$(ffprobe -v quiet -print_format json -show_streams "$file" | jq -s -R -r @base64)
    local streams_count=$(echo "$streams_info" | base64 --decode | jq '.streams | length')

    local has_supported_audio="false"
    local english_audio_to_convert=""
    local streams_to_remove=""
    local audio_stream_index=0

    for (( i=0; i<$streams_count; i++ )); do
        local codec_name=$(echo "$streams_info" | base64 --decode | jq -r ".streams[$i].codec_name")
        local codec_type=$(echo "$streams_info" | base64 --decode | jq -r ".streams[$i].codec_type")
        local language=$(echo "$streams_info" | base64 --decode | jq -r ".streams[$i].tags.language")
        local title=$(echo "$streams_info" | base64 --decode | jq -r ".streams[$i].tags.title" | tr '[:upper:]' '[:lower:]')

        if [ "$codec_type" = "audio" ];then

            if contains "$codec_name" "${SUPPORTED_AUDIO_CODECS[@]}" && contains "$language" "${SUPPORTED_LANGUAGES[@]}"; then
                has_supported_audio="true"
                printf "Audio stream $audio_stream_index (codec: $codec_name, language: $language) found in $file\n"
            elif contains "$language" "${SUPPORTED_LANGUAGES[@]}" && [[ "$title" != *"commentary"* ]]; then
                english_audio_to_convert+=" -map 0:a:$audio_stream_index"
                printf "${GREEN}English audio stream $audio_stream_index (codec: $codec_name, language: $language) will be converted to AC3 in $file${NC}\n"
            else
                streams_to_remove+=" -map -0:a:$audio_stream_index"
                printf "${AMBER}Audio streams $audio_stream_index (codec: $codec_name, language: $language) will be removed from $file${NC}\n"
            fi
            ((audio_stream_index++))
        fi
    done

    
    if [ -n "$english_audio_to_convert" ] || [ -n "$streams_to_remove" ]; then
		
        local tmp_file="${file%.*}_tmp.${file##*.}"
        local log_file="$LOG_DIR/${file%.*}_ffmpeg.log"  # Unique log file for each ffmpeg process
		

        if [ "$DRY_RUN" != "true" ]; then
            # Start ffmpeg process in background
            ffmpeg -y -nostdin -hide_banner -probesize 50M -analyzeduration 100M -i "$file" \
                   -map 0 $english_audio_to_convert $streams_to_remove \
				   -c:s copy \
                   -c:v copy -c:a ac3 "$tmp_file" > "$log_file" 2>&1 && mv "$tmp_file" "$file" &
            local ffmpeg_pid=$!

            # Start tail process in background
            tail --pid=$ffmpeg_pid -f "$log_file" &
            local tail_pid=$!

            # Wait for ffmpeg to finish and then kill tail process
            wait $ffmpeg_pid
            kill $tail_pid
        fi
    fi
}

if [ -n "$FILE" ]; then
    # Process only the specified file
    process_video_file "$FILE"
else
    pids=()
	
    # Find all video files in the directory, excluding the "/transmission/*" folder
    find "$DIR" \( -path "./transmission" -prune \) -o \( -type f -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) -print0 | while IFS= read -r -d '' file; do
        process_video_file "$file" &  # Send process to background
        pids+=($!)  # Store PID of background job

        # Allow only THREADS jobs at a time
        while (( $(jobs -p | wc -l) >= THREADS )); do
            wait -n  # Wait for any job to complete
        done
    done

    # Wait for all PIDs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Wait a bit to let any final output be printed
    sleep 2

    echo "All jobs completed"

fi

