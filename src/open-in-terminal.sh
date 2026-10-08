#!/bin/bash
# Automator passes the selected Finder folders as separate arguments.
# Keep this script compatible with the Bash 3.2 supplied by older macOS releases.

if [ "$#" -eq 0 ]; then
    printf '%s\n' 'Open in Terminal: select at least one folder.' >&2
    exit 1
fi

result=0
for folder in "$@"; do
    if [ ! -d "$folder" ]; then
        printf 'Open in Terminal: not a folder: %s\n' "$folder" >&2
        result=1
        continue
    fi

    # Finder supplies absolute paths. Also accept relative paths safely: making
    # them absolute prevents a folder name beginning with "-" becoming an option.
    case "$folder" in
        /*) ;;
        *) folder="$PWD/$folder" ;;
    esac

    # Pass a folder URL to Terminal through Launch Services. Never interpolate
    # a folder name into a shell command or ask Terminal to execute a file.
    if ! /usr/bin/open -b com.apple.Terminal "$folder"; then
        printf 'Open in Terminal: could not open folder: %s\n' "$folder" >&2
        result=1
    fi
done

exit "$result"
