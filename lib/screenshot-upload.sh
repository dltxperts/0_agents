#!/bin/bash
# Universal screenshot upload script for Linux and macOS
# Uploads screenshots to Tailscale server u3775

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FILENAME="screenshot-${TIMESTAMP}.png"
LOCAL_DIR="$HOME/Pictures/screenshots"
LOCAL_FILE="${LOCAL_DIR}/${FILENAME}"
REMOTE_USER="screenshot"
REMOTE_HOST="u3775"
REMOTE_PATH="/tmp/screenshots"

# Create local directory if it doesn't exist
mkdir -p "$LOCAL_DIR"

# Detect OS
OS="$(uname -s)"

# Take screenshot based on OS
take_screenshot() {
    case "$OS" in
        Linux*)
            # Use gnome-screenshot area selection
            if command -v gnome-screenshot &> /dev/null; then
                gnome-screenshot -a -f "$LOCAL_FILE" 2>/dev/null
            else
                echo "Error: No screenshot tool found"
                return 1
            fi
            ;;
        Darwin*)
            # macOS - interactive area selection
            screencapture -i "$LOCAL_FILE" 2>/dev/null
            # Check if user cancelled (Esc key)
            if [ ! -f "$LOCAL_FILE" ]; then
                return 1
            fi
            ;;
        *)
            echo "Error: Unsupported OS: $OS"
            return 1
            ;;
    esac
}

# Copy to clipboard based on OS
copy_to_clipboard() {
    local text="$1"
    case "$OS" in
        Linux*)
            if command -v xclip &> /dev/null; then
                # Copy to both PRIMARY (middle-click) and CLIPBOARD (Ctrl+V)
                echo -n "$text" | xclip -selection primary
                echo -n "$text" | xclip -selection clipboard
            elif command -v wl-copy &> /dev/null; then
                # Wayland: copy to both primary and clipboard
                echo -n "$text" | wl-copy
                echo -n "$text" | wl-copy --primary
            else
                echo "Warning: No clipboard tool found (xclip or wl-copy)"
                return 1
            fi
            ;;
        Darwin*)
            echo -n "$text" | pbcopy
            return 0
            ;;
    esac
}

# Show notification based on OS
show_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"

    case "$OS" in
        Linux*)
            if command -v notify-send &> /dev/null; then
                notify-send "$title" "$message" -u "$urgency" -t 3000
            fi
            ;;
        Darwin*)
            osascript -e "display notification \"$message\" with title \"$title\""
            ;;
    esac
}

# Main logic
take_screenshot

# Check if screenshot was taken successfully
if [ ! -f "$LOCAL_FILE" ]; then
    show_notification "Screenshot Failed" "Could not capture screenshot" "critical"
    exit 1
fi

# Upload via SCP directly as screenshot user
scp "$LOCAL_FILE" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" 2>/dev/null

if [ $? -eq 0 ]; then
    # Set readable permissions for group members
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "chmod 644 ${REMOTE_PATH}/${FILENAME}" 2>/dev/null

    # Create the file path (just the server path, no scp prefix)
    FILE_PATH="${REMOTE_PATH}/${FILENAME}"

    # Copy path to clipboard
    copy_to_clipboard "$FILE_PATH"

    # Show success notification
    show_notification "Screenshot Uploaded" "Path copied: ${FILE_PATH}"
else
    show_notification "Upload Failed" "Could not upload to $REMOTE_HOST" "critical"
    exit 1
fi
