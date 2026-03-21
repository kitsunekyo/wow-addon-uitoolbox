#!/usr/bin/env bash
# sync.sh -- Copy UIToolbox to the WoW retail AddOns folder and wipe SavedVariables.
# Run this from WSL after making changes, then /reload in-game.

WOW_RETAIL="/mnt/c/Program Files (x86)/World of Warcraft/_retail_"
ADDONS_DIR="$WOW_RETAIL/Interface/AddOns"
WTF_DIR="$WOW_RETAIL/WTF"
ADDON_NAME="UIToolbox"
SRC="$(cd "$(dirname "$0")" && pwd)/$ADDON_NAME"
DEST="$ADDONS_DIR/$ADDON_NAME"

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

# Remove all SavedVariables for this addon so stale settings can't interfere.
# WoW stores them in two locations:
#   Account-wide:   WTF/Account/<ACCOUNT>/SavedVariables/<ADDON>.lua(.bak)
#   Per-character:  WTF/Account/<ACCOUNT>/<SERVER>/<CHAR>/SavedVariables/<ADDON>.lua(.bak)
if [ -d "$WTF_DIR" ]; then
    mapfile -t SV_FILES < <(find "$WTF_DIR" -type f \( -name "${ADDON_NAME}.lua" -o -name "${ADDON_NAME}.lua.bak" \))
    if [ ${#SV_FILES[@]} -gt 0 ]; then
        echo "Removing SavedVariables for $ADDON_NAME:"
        for f in "${SV_FILES[@]}"; do
            rm -f "$f" && echo "  deleted: $f"
        done
    else
        echo "No SavedVariables found for $ADDON_NAME (nothing to remove)."
    fi
else
    echo "WARNING: WTF directory not found at: $WTF_DIR — SavedVariables not cleared."
fi

echo ""
echo "Now type /reload in WoW to pick up the changes."
