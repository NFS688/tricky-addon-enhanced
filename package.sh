#!/bin/sh
# Package TA_utl module ZIP with auto version bump
# Usage: ./package.sh [output_dir]
#   Bumps minor version (v4.8 → v4.9) and versionCode, updates module.prop + update.json

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PROP="$REPO_DIR/module.prop"
UPDATE_JSON="$REPO_DIR/update.json"

MODULE_ID=$(grep '^id=' "$PROP" | cut -d= -f2)
OLD_VERSION=$(grep '^version=' "$PROP" | cut -d= -f2)
OLD_CODE=$(grep '^versionCode=' "$PROP" | cut -d= -f2)

if [ -z "$MODULE_ID" ] || [ -z "$OLD_VERSION" ] || [ -z "$OLD_CODE" ]; then
    echo "ERROR: Cannot parse module.prop" >&2
    exit 1
fi

# Parse version: v{major}.{minor}-{suffix}
MAJOR=$(echo "$OLD_VERSION" | sed 's/^v//' | cut -d. -f1)
MINOR=$(echo "$OLD_VERSION" | cut -d. -f2 | cut -d- -f1)
SUFFIX=$(echo "$OLD_VERSION" | sed 's/^[^-]*//')

NEW_MINOR=$((MINOR + 1))
NEW_VERSION="v${MAJOR}.${NEW_MINOR}${SUFFIX}"
NEW_CODE=$((OLD_CODE + 1))

echo "Version: $OLD_VERSION → $NEW_VERSION (code: $OLD_CODE → $NEW_CODE)"

# Update module.prop
sed -i "s/^version=.*/version=$NEW_VERSION/" "$PROP"
sed -i "s/^versionCode=.*/versionCode=$NEW_CODE/" "$PROP"

# Update update.json
RELEASE_URL="https://github.com/Enginex0/tricky-addon-enhanced/releases/download/${NEW_VERSION}/${MODULE_ID}-${NEW_VERSION}.zip"
sed -i "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION\"/" "$UPDATE_JSON"
sed -i "s/\"versionCode\": [0-9]*/\"versionCode\": $NEW_CODE/" "$UPDATE_JSON"
sed -i "s|\"zipUrl\": \".*\"|\"zipUrl\": \"$RELEASE_URL\"|" "$UPDATE_JSON"

# Package
OUT_DIR="${1:-$REPO_DIR/release}"
mkdir -p "$OUT_DIR"
ZIP_NAME="${MODULE_ID}-${NEW_VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"

cd "$REPO_DIR"
zip -r "$ZIP_PATH" . \
    -x ".git/*" \
    -x ".claude/*" \
    -x ".mcp-vector-search/*" \
    -x ".gitignore" \
    -x "CLAUDE.md" \
    -x "*.zip" \
    -x "*.db" -x "*.db-shm" -x "*.db-wal" \
    -x "webui-mockup/*" \
    -x "native/*" \
    -x "logs_llm/*" \
    -x "evidence_*.png" \
    -x "*.swp" -x "*~" \
    -x "release/*" \
    -x "package.sh" \
    -x ".mcp.json" \
    -x "*.map"

echo ""
echo "Packaged: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"
echo "Files: $(unzip -l "$ZIP_PATH" | tail -1)"
