#!/usr/bin/env bash
# sync.sh -- Copy UIToolbox to the WoW retail AddOns folder.
# Run this from WSL after making changes, then /reload in-game.

ADDONS_DIR="/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns"
SRC="$(cd "$(dirname "$0")" && pwd)/UIToolbox"
DEST="$ADDONS_DIR/UIToolbox"

if [ ! -d "$ADDONS_DIR" ]; then
    echo "ERROR: WoW AddOns directory not found at: $ADDONS_DIR"
    exit 1
fi

# Use rsync if available, otherwise fall back to cp.
if command -v rsync &>/dev/null; then
    rsync -av --delete "$SRC/" "$DEST/"
else
    mkdir -p "$DEST"
    cp -rv "$SRC/." "$DEST/"
fi

echo ""
echo "Synced to: $DEST"
echo "Now type /reload in WoW to pick up the changes."
