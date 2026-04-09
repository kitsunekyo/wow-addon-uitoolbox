#!/bin/bash

# Deploy script to generate a zip file of the addon with semver versioning from git tags
# Excludes: README.md, knowledge/, AGENTS.md, .git/, .opencode/, etc.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
ADDON_NAME="EnhancedInterface"

# Create build directory if it doesn't exist
mkdir -p "${BUILD_DIR}"

# Get the latest git tag (semver version)
VERSION=$(cd "${SCRIPT_DIR}" && git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")

# Remove 'v' prefix if present (e.g., v1.0.0 -> 1.0.0)
VERSION="${VERSION#v}"

OUTPUT_FILE="${BUILD_DIR}/${ADDON_NAME}-${VERSION}.zip"

# Create a Python script to handle the zipping
TEMP_SCRIPT=$(mktemp)
cat > "${TEMP_SCRIPT}" << 'PYTHON_SCRIPT'
import os
import zipfile
import sys

def should_exclude(path, name):
    """Check if a file/directory should be excluded"""
    excluded = {
        '.git', '.opencode', '.gitignore', '.DS_Store',
        'README.md', 'AGENTS.md', 'knowledge', 'package.sh',
        'sync.sh'
    }
    return name in excluded or path.endswith('.pyc')

def add_to_zip(zip_file, folder_path, addon_name, arcname=''):
    """Recursively add files to zip, excluding unwanted items"""
    for item in os.listdir(folder_path):
        item_path = os.path.join(folder_path, item)
        arc_path = os.path.join(arcname, item) if arcname else item
        
        if should_exclude(item_path, item):
            continue
            
        if os.path.isdir(item_path):
            add_to_zip(zip_file, item_path, addon_name, arc_path)
        else:
            zip_file.write(item_path, arc_path)

script_dir = sys.argv[1]
addon_name = sys.argv[2]
output_file = sys.argv[3]

addon_path = os.path.join(script_dir, addon_name)

with zipfile.ZipFile(output_file, 'w', zipfile.ZIP_DEFLATED) as zf:
    add_to_zip(zf, addon_path, addon_name, addon_name)

size = os.path.getsize(output_file)
size_kb = size / 1024
print(f"✓ Addon packaged successfully: {output_file}")
print(f"File size: {size_kb:.1f} KB")
PYTHON_SCRIPT

python3 "${TEMP_SCRIPT}" "${SCRIPT_DIR}" "${ADDON_NAME}" "${OUTPUT_FILE}"
rm "${TEMP_SCRIPT}"
