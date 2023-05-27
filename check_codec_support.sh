#!/bin/bash

# Check if a directory is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

# Provided directory
MOVIE_DIR="$1"

# Supported codecs
SUPPORTED_VIDEO_CODECS=("h264" "hevc" "vp9" "av1" "mjpeg" "png")
SUPPORTED_AUDIO_CODECS=("aac" "mp3" "wma" "wav" "ogg" "flac" "alac" "eac3" "ac3" "opus")
SUPPORTED_SUBTITLE_CODECS=("srt" "ass" "ssa" "subrip" "dvd_subtitle" "hdmv_pgs_subtitle" "mov_text")

# Check if a codec is in a list of supported codecs
function is_codec_supported {
    local codec=$1
    shift
    local supported_codecs=("$@")

    for supported_codec in ${supported_codecs[@]}; do
        if [[ $codec == $supported_codec ]]; then
            return 0
        fi
    done

    return 1
}

# Recursively check all movie files
find "$MOVIE_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) | while read -r movie; do
    mapfile -t codec_types < <(ffprobe -v error -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$movie")
    mapfile -t codecs < <(ffprobe -v error -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$movie")

    audio_supported=false
    unsupported_video=""
    unsupported_subtitle=""

    for index in ${!codecs[@]}; do
        codec=${codecs[$index]}
        codec_type=${codec_types[$index]}

        case $codec_type in
            video)
                supported_codecs=(${SUPPORTED_VIDEO_CODECS[@]})
                if ! is_codec_supported $codec ${supported_codecs[@]}; then
                    unsupported_video="$movie contains unsupported $codec_type codec: $codec"
                fi
                ;;
            audio)
                supported_codecs=(${SUPPORTED_AUDIO_CODECS[@]})
                if is_codec_supported $codec ${supported_codecs[@]}; then
                    audio_supported=true
                fi
                ;;
            subtitle)
                supported_codecs=(${SUPPORTED_SUBTITLE_CODECS[@]})
                if ! is_codec_supported $codec ${supported_codecs[@]}; then
                    unsupported_subtitle="$movie contains unsupported $codec_type codec: $codec"
                fi
                ;;
        esac
    done

    if ! $audio_supported; then
        echo "$movie contains no supported audio codecs"
    fi

    if [[ $unsupported_video ]]; then
        echo "$unsupported_video"
    fi

    if [[ $unsupported_subtitle ]]; then
        echo "$unsupported_subtitle"
    fi
done


