#!/bin/bash
# Waybar module to show current image version and update availability

# Get current booted image info
CURRENT=$(bootc status --json 2>/dev/null | jq -r '.status.booted.image.image.image // empty' 2>/dev/null)
VERSION=$(bootc status --json 2>/dev/null | jq -r '.status.booted.image.image.tag // empty' 2>/dev/null)

if [ -z "$CURRENT" ]; then
    # Fallback for non-bootc or error
    echo '{"text": "", "tooltip": "Unable to get image status"}'
    exit 0
fi

# Check if update is available (staged)
STAGED=$(bootc status --json 2>/dev/null | jq -r '.status.staged.image.image.tag // empty' 2>/dev/null)

if [ -n "$STAGED" ] && [ "$STAGED" != "$VERSION" ]; then
    # Update staged, show indicator
    echo "{\"text\": \" $VERSION\", \"tooltip\": \"Current: $VERSION\\nUpdate staged: $STAGED\\nReboot to apply\", \"class\": \"update-available\"}"
else
    # No update, just show version
    echo "{\"text\": \"$VERSION\", \"tooltip\": \"Image: $CURRENT\\nVersion: $VERSION\", \"class\": \"current\"}"
fi
