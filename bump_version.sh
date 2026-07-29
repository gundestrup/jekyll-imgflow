#!/bin/bash
# Version bumping script for jekyll-imgflow

set -e

VERSION_FILE="lib/jekyll-imgflow/version.rb"

# Get current version
CURRENT=$(grep 'VERSION = ' "$VERSION_FILE" | sed 's/.*VERSION = "\(.*\)".*/\1/')
IFS='.' read -r -a parts <<< "$CURRENT"

MAJOR="${parts[0]}"
MINOR="${parts[1]}"
PATCH="${parts[2]}"

case "$1" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Usage: $0 {major|minor|patch}"
    echo ""
    echo "Current version: $CURRENT"
    echo ""
    echo "Examples:"
    echo "  $0 patch  # $CURRENT → ${MAJOR}.${MINOR}.$((PATCH + 1))"
    echo "  $0 minor  # $CURRENT → ${MAJOR}.$((MINOR + 1)).0"
    echo "  $0 major  # $CURRENT → $((MAJOR + 1)).0.0"
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

echo "Bumping version: $CURRENT → $NEW_VERSION"
echo ""

# Update version file
sed -i.bak "s/VERSION = \".*\"/VERSION = \"$NEW_VERSION\"/" "$VERSION_FILE"
rm "${VERSION_FILE}.bak"

echo "✅ Updated $VERSION_FILE"
echo ""

# Add CHANGELOG entry if it doesn't exist
if ! grep -q "## \[$NEW_VERSION\]" CHANGELOG.md; then
    echo "📝 Adding CHANGELOG entry for v$NEW_VERSION..."
    
    # Create temporary file with new entry
    TEMP_FILE=$(mktemp)
    
    # Add new version entry at the top (after "# Changelog")
    {
        head -n 2 CHANGELOG.md
        echo ""
        echo "## [$NEW_VERSION] - $(date +%Y-%m-%d)"
        echo ""
        echo "### Added"
        echo "- "
        echo ""
        echo "### Changed"
        echo "- "
        echo ""
        echo "### Fixed"
        echo "- "
        echo ""
        tail -n +3 CHANGELOG.md
    } > "$TEMP_FILE"
    
    mv "$TEMP_FILE" CHANGELOG.md
    echo "✅ CHANGELOG.md updated with template for v$NEW_VERSION"
else
    echo "ℹ️  CHANGELOG.md already has entry for v$NEW_VERSION"
fi

echo ""
echo "Next steps:"
echo "  1. Edit CHANGELOG.md and fill in changes for v$NEW_VERSION"
echo "  2. Run: ./release.sh"
echo "     (This will commit, tag, and push to GitHub)"
echo "  3. Create GitHub release (release notes will be auto-extracted)"
echo "     → Workflow will automatically publish to RubyGems! 🎉"
echo ""
