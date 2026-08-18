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
TODAY=$(date +%Y-%m-%d)

if grep -q "## \[$NEW_VERSION\]" CHANGELOG.md; then
    echo "Version $NEW_VERSION already exists in CHANGELOG.md"
    exit 1
fi

echo "Bumping version: $CURRENT → $NEW_VERSION"
echo ""

# Update the single source of truth for the version.
sed -i.bak "s/VERSION = \".*\"/VERSION = \"$NEW_VERSION\"/" "$VERSION_FILE"
rm "${VERSION_FILE}.bak"
echo "✅ Updated $VERSION_FILE"

# Move the current Unreleased notes into the new version section and create
# a fresh Unreleased section above it. This keeps release notes intact.
TEMP_FILE=$(mktemp)
awk -v version="$NEW_VERSION" -v today="$TODAY" '
  /^## \[Unreleased\]$/ && !moved {
    print "## [Unreleased]"
    print ""
    print "## [" version "] - " today
    moved = 1
    next
  }
  { print }
' CHANGELOG.md > "$TEMP_FILE"
mv "$TEMP_FILE" CHANGELOG.md
echo "✅ Moved Unreleased notes into v$NEW_VERSION"

# Synchronize the path-gem version in Gemfile.lock without changing resolved
# dependency versions. CI runs Bundler in frozen mode and requires this match.
bundle lock >/dev/null
echo "✅ Updated Gemfile.lock"

echo ""
echo "Next steps:"
echo "  1. Edit CHANGELOG.md and review the v$NEW_VERSION notes"
echo "  2. Run: ./release.sh"
echo "     (This will quality-check, commit, tag, push, and create the GitHub release)"
echo "  3. GitHub Actions will publish the gem to RubyGems via OIDC"
echo ""
