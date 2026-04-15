#!/usr/bin/env bash
# version-bump.sh — Bump addon version, update CHANGELOG, and create git tag.
# Usage: ./version-bump.sh <version>
# Example: ./version-bump.sh 0.1.2

set -euo pipefail

# --- Setup -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOC_FILE="$REPO_ROOT/EnhancedInterface/EnhancedInterface.toc"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>" >&2
    echo "Example: $0 0.1.2" >&2
    exit 1
fi

NEW_VERSION="$1"

# Validate version format (basic check)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Invalid version format. Expected X.Y.Z (e.g., 0.1.2)" >&2
    exit 1
fi

# --- Preflight checks -------------------------------------------------------

if [ ! -f "$TOC_FILE" ]; then
    echo "ERROR: TOC file not found: $TOC_FILE" >&2
    exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "ERROR: CHANGELOG file not found: $CHANGELOG_FILE" >&2
    exit 1
fi

# Check for uncommitted changes
if ! git -C "$SCRIPT_DIR" diff-index --quiet HEAD --; then
    echo "ERROR: Uncommitted changes detected. Please commit or stash first." >&2
    exit 1
fi

# Check if tag already exists
if git -C "$SCRIPT_DIR" rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
    echo "ERROR: Tag v$NEW_VERSION already exists." >&2
    exit 1
fi

# --- Update TOC file -------------------------------------------------------

echo "Updating version in $TOC_FILE..."
sed -i "s/^## Version: .*/## Version: $NEW_VERSION/" "$TOC_FILE"

# Verify the change
CURRENT_VERSION=$(grep "^## Version:" "$TOC_FILE" | cut -d' ' -f3)
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    echo "ERROR: Failed to update version in TOC file" >&2
    exit 1
fi

echo "✓ Updated .toc version to $NEW_VERSION"

# --- Generate new CHANGELOG --------------------------------------------------

echo "Generating changelog from git history..."

# Get current date
RELEASE_DATE=$(date +%Y-%m-%d)

# Extract commits since last tag
LAST_TAG=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$LAST_TAG" ]; then
    # No previous tag, use all commits
    COMMITS=$(git -C "$SCRIPT_DIR" log --oneline --pretty=format:"%h %s" -- EnhancedInterface/)
else
    # Commits since last tag
    COMMITS=$(git -C "$SCRIPT_DIR" log "${LAST_TAG}..HEAD" --oneline --pretty=format:"%h %s" -- EnhancedInterface/)
fi

# Generate changelog section
CHANGELOG_SECTION=$(cat <<EOF
## [$NEW_VERSION] - $RELEASE_DATE

EOF
)

# Categorize commits
FEATURES=""
FIXES=""
DOCS=""
REFACTOR=""
OTHER=""

while IFS= read -r line; do
    if [ -z "$line" ]; then
        continue
    fi
    
    COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)
    
    if [[ "$COMMIT_MSG" =~ ^feat: ]]; then
        FEATURES+="- $(echo "$COMMIT_MSG" | sed 's/^feat: //')"$'\n'
    elif [[ "$COMMIT_MSG" =~ ^fix: ]]; then
        FIXES+="- $(echo "$COMMIT_MSG" | sed 's/^fix: //')"$'\n'
    elif [[ "$COMMIT_MSG" =~ ^docs: ]]; then
        DOCS+="- $(echo "$COMMIT_MSG" | sed 's/^docs: //')"$'\n'
    elif [[ "$COMMIT_MSG" =~ ^refactor: ]]; then
        REFACTOR+="- $(echo "$COMMIT_MSG" | sed 's/^refactor: //')"$'\n'
    else
        OTHER+="- $COMMIT_MSG"$'\n'
    fi
done <<< "$COMMITS"

# Build categorized section
if [ -n "$FEATURES" ]; then
    CHANGELOG_SECTION+="### Added"$'\n'"${FEATURES}"$'\n'
fi

if [ -n "$FIXES" ]; then
    CHANGELOG_SECTION+="### Fixed"$'\n'"${FIXES}"$'\n'
fi

if [ -n "$REFACTOR" ]; then
    CHANGELOG_SECTION+="### Changed"$'\n'"${REFACTOR}"$'\n'
fi

if [ -n "$DOCS" ]; then
    CHANGELOG_SECTION+="### Documentation"$'\n'"${DOCS}"$'\n'
fi

if [ -n "$OTHER" ]; then
    CHANGELOG_SECTION+="### Other"$'\n'"${OTHER}"$'\n'
fi

# Prepend new section to CHANGELOG
TEMP_CHANGELOG=$(mktemp)
echo -e "$CHANGELOG_SECTION" > "$TEMP_CHANGELOG"
# Skip the first three lines of the old changelog (title and empty lines)
tail -n +4 "$CHANGELOG_FILE" >> "$TEMP_CHANGELOG"
mv "$TEMP_CHANGELOG" "$CHANGELOG_FILE"

echo "✓ Updated CHANGELOG.md"

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
