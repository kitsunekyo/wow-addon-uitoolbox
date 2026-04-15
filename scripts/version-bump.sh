#!/usr/bin/env bash
# version-bump.sh — Bump addon version, update CHANGELOG, and create git tag.
# Usage: ./version-bump.sh [--dry-run]
# Example: ./version-bump.sh
#          ./version-bump.sh --dry-run

set -euo pipefail

# --- Setup -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOC_FILE="$REPO_ROOT/EnhancedInterface/EnhancedInterface.toc"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

DRY_RUN=false
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=true
    else
        echo "Unknown argument: $arg" >&2
        echo "Usage: $0 [--dry-run]" >&2
        exit 1
    fi
done

# --- Determine current version and compute bump ------------------------------

CURRENT_VERSION=$(grep "^## Version:" "$TOC_FILE" | cut -d' ' -f3)
if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Could not parse current version from TOC: '$CURRENT_VERSION'" >&2
    exit 1
fi

MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)

# --- Preview commits ---------------------------------------------------------

LAST_TAG=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$LAST_TAG" ]; then
    COMMITS=$(git -C "$SCRIPT_DIR" log --oneline --pretty=format:"%h %s")
else
    COMMITS=$(git -C "$SCRIPT_DIR" log "${LAST_TAG}..HEAD" --oneline --pretty=format:"%h %s")
fi

FEATURES=""
FIXES=""

while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)
    if [[ "$COMMIT_MSG" =~ ^feat: ]]; then
        FEATURES+="- $(echo "$COMMIT_MSG" | sed 's/^feat: //')"$'\n'
    elif [[ "$COMMIT_MSG" =~ ^fix: ]]; then
        FIXES+="- $(echo "$COMMIT_MSG" | sed 's/^fix: //')"$'\n'
    fi
done <<< "$COMMITS"

echo "Changes since $LAST_TAG:"
echo ""
if [ -n "$FEATURES" ]; then
    echo "  ### Changes"
    printf '%s' "$FEATURES"
    echo ""
fi
if [ -n "$FIXES" ]; then
    echo "  ### Fixes"
    printf '%s' "$FIXES"
    echo ""
fi

echo "Current version: $CURRENT_VERSION"
echo ""
echo "  1) patch  →  $MAJOR.$MINOR.$((PATCH + 1))"
echo "  2) minor  →  $MAJOR.$((MINOR + 1)).0"
echo "  3) major  →  $((MAJOR + 1)).0.0"
echo ""
read -r -p "Bump type [1/2/3]: " BUMP_CHOICE

case "$BUMP_CHOICE" in
    1) NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    2) NEW_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    3) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
    *) echo "ERROR: Invalid choice '$BUMP_CHOICE'" >&2; exit 1 ;;
esac

echo ""

# --- Preflight checks -------------------------------------------------------

if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "ERROR: CHANGELOG file not found: $CHANGELOG_FILE" >&2
    exit 1
fi

# Check for uncommitted changes (skip in dry-run)
if ! $DRY_RUN && ! git -C "$SCRIPT_DIR" diff-index --quiet HEAD --; then
    echo "ERROR: Uncommitted changes detected. Please commit or stash first." >&2
    exit 1
fi

# Check if tag already exists
if git -C "$SCRIPT_DIR" rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
    echo "ERROR: Tag v$NEW_VERSION already exists." >&2
    exit 1
fi

# --- Update TOC file -------------------------------------------------------

if $DRY_RUN; then
    echo "[dry-run] Would update .toc version to $NEW_VERSION"
else
    echo "Updating version in $TOC_FILE..."
    sed -i "s/^## Version: .*/## Version: $NEW_VERSION/" "$TOC_FILE"

    # Verify the change
    CURRENT_VERSION=$(grep "^## Version:" "$TOC_FILE" | cut -d' ' -f3)
    if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
        echo "ERROR: Failed to update version in TOC file" >&2
        exit 1
    fi

    echo "✓ Updated .toc version to $NEW_VERSION"
fi

# --- Generate new CHANGELOG --------------------------------------------------

RELEASE_DATE=$(date +%Y-%m-%d)

# Generate changelog section (reuse FEATURES/FIXES/LAST_TAG from preview above)
CHANGELOG_SECTION="## [$NEW_VERSION] - $RELEASE_DATE"$'\n\n'

# Build categorized section
if [ -n "$FEATURES" ]; then
    CHANGELOG_SECTION+="### Changes"$'\n'"${FEATURES}"$'\n'
fi

if [ -n "$FIXES" ]; then
    CHANGELOG_SECTION+="### Fixes"$'\n'"${FIXES}"$'\n'
fi

# Prepend new section to CHANGELOG
if $DRY_RUN; then
    echo "[dry-run] Would prepend to CHANGELOG.md"
else
    TEMP_CHANGELOG=$(mktemp)
    printf '%s\n' "$CHANGELOG_SECTION" > "$TEMP_CHANGELOG"
    cat "$CHANGELOG_FILE" >> "$TEMP_CHANGELOG"
    mv "$TEMP_CHANGELOG" "$CHANGELOG_FILE"
    echo "✓ Updated CHANGELOG.md"
fi

# --- Review and confirm ------------------------------------------------------

if $DRY_RUN; then
    echo "[dry-run] No files written. Exiting."
    exit 0
fi

read -r -p "Press Enter to commit and tag, or Ctrl+C to abort: "

# --- Commit and tag ----------------------------------------------------------

echo "Committing changes..."
git -C "$SCRIPT_DIR" add "$TOC_FILE" "$CHANGELOG_FILE"
git -C "$SCRIPT_DIR" commit -m "chore: bump version to $NEW_VERSION"

echo "Creating git tag v$NEW_VERSION..."
git -C "$SCRIPT_DIR" tag "v$NEW_VERSION"

echo ""
echo "=========================================="
echo "✓ Version bump complete!"
echo "=========================================="
echo "Version:   $NEW_VERSION"
echo "TOC file:  $TOC_FILE"
echo "Changelog: $CHANGELOG_FILE"
echo "Tag:       v$NEW_VERSION"
echo ""
echo "Next steps:"
echo "  git push origin main --tags"
echo "  (This will trigger the CurseForge packager webhook)"
