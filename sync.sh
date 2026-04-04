#!/usr/bin/env bash
# sync.sh — Sync EnhancedInterface to the WoW retail AddOns folder.
# Removes the destination directory entirely before copying to guarantee
# no stale files remain. Run from WSL, then /reload in-game.

set -euo pipefail

ADDONS_DIR="/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns"
SRC="$(cd "$(dirname "$0")" && pwd)/EnhancedInterface"
DEST="$ADDONS_DIR/EnhancedInterface"

# --- Preflight checks -------------------------------------------------------

if [ ! -d "$ADDONS_DIR" ]; then
    echo "ERROR: WoW AddOns directory not found: $ADDONS_DIR" >&2
    exit 1
fi

if [ ! -d "$SRC" ]; then
    echo "ERROR: Source directory not found: $SRC" >&2
    exit 1
fi

# --- Sync -------------------------------------------------------------------

# Remove destination entirely to guarantee no stale files survive
if [ -d "$DEST" ]; then
    echo "Removing stale addon directory: $DEST"
    rm -rf "$DEST"
fi

echo "Copying: $SRC -> $DEST"
cp -r "$SRC" "$DEST"

# Report every file that was synced
echo ""
echo "Files synced:"
find "$DEST" -type f | sort | sed "s|$DEST/||"

echo ""
echo "Synced to: $DEST"
echo "Now type /reload in WoW to pick up the changes."
