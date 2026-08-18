# Release script for jekyll-imgflow
set -e

# Parse arguments
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🔍 DRY RUN MODE - No changes will be made"
    echo ""
fi

echo "🚀 Jekyll ImgFlow Release Script"
echo "================================="
echo ""

# Get version from version.rb
VERSION=$(grep 'VERSION = ' lib/jekyll-imgflow/version.rb | sed 's/.*VERSION = \"\(.*\)\".*/\1/')
echo "📦 Version: $VERSION"
echo ""

# Check for uncommitted changes
echo "🔍 Checking git status..."
if [[ -n $(git status -s) ]]; then
    echo "⚠️  Warning: Uncommitted changes detected"
    git status -s
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Release cancelled"
        exit 1
    fi
else
    echo "✅ Working directory clean"
fi
echo ""

# Check if CHANGELOG has entry for this version
echo "🔍 Checking CHANGELOG.md..."
if ! grep -q "## \[$VERSION\]" CHANGELOG.md; then
    echo "❌ CHANGELOG.md missing entry for version $VERSION"
    echo ""
    echo "Please add a changelog entry:"
    echo ""
    echo "## [$VERSION] - $(date +%Y-%m-%d)"
    echo ""
    echo "### Added"
    echo "- New features..."
    echo ""
    echo "### Fixed"
    echo "- Bug fixes..."
    echo ""
    exit 1
fi
echo "✅ CHANGELOG.md has entry for v$VERSION"
echo ""

# Check version consistency (first matching versioned header in CHANGELOG)
echo "🔍 Checking version consistency..."
CHANGELOG_VERSION=$(grep -m 1 "## \[$VERSION\]" CHANGELOG.md | sed 's/.*\[\(.*\)\].*/\1/')
if [[ "$VERSION" != "$CHANGELOG_VERSION" ]]; then
    echo "⚠️  Warning: Version mismatch"
    echo "   version.rb: $VERSION"
    echo "   CHANGELOG:  $CHANGELOG_VERSION"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Release cancelled"
        exit 1
    fi
else
    echo "✅ Version consistent across files"
fi
echo ""

# Check dependencies
echo "🔍 Checking dependencies..."
if bundle outdated --strict 2>/dev/null; then
    echo "✅ All dependencies up to date"
else
    echo "⚠️  Some dependencies are outdated"
    echo "   Run 'bundle update' to update"
fi
echo ""

# Confirm
if [[ "$DRY_RUN" == true ]]; then
    echo "📋 DRY RUN: Would release v$VERSION"
    echo ""
else
    read -p "Ready to release v$VERSION? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Release cancelled"
        exit 1
    fi
fi

echo ""
if [[ "$DRY_RUN" == true ]]; then
    echo "📋 DRY RUN: Skipping quality checks"
    echo "📋 DRY RUN: Skipping gem build"
    echo "📋 DRY RUN: Would commit and push to GitHub"
    echo "📋 DRY RUN: Would create tag v$VERSION"
    echo ""
    echo "✅ Dry run completed successfully"
    exit 0
fi

echo "1️⃣  Running quality checks..."
bundle exec rake quality || {
    echo "❌ Quality checks failed! Fix issues before releasing."
    exit 1
}

echo "2️⃣  Building gem to verify..."
gem build jekyll-imgflow.gemspec || {
    echo "❌ Gem build failed!"
    exit 1
}
rm -f jekyll-imgflow-*.gem

echo "3️⃣  Extracting release notes..."
RELEASE_NOTES=$(awk -v header="## [$VERSION]" '
  index($0, header) == 1 { in_section=1; next }
  in_section && /^## \[/ { exit }
  in_section { print }
' CHANGELOG.md)
echo "Release notes extracted for GitHub release"

echo "4️⃣  Adding all files..."
git add -u

echo "5️⃣  Committing changes..."
read -p "Enter commit message: " COMMIT_MSG
if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG="Release v$VERSION"
fi
git commit -m "$COMMIT_MSG" || echo "Nothing to commit"

echo "6️⃣  Creating tag v$VERSION..."
git tag -a "v$VERSION" -m "Version $VERSION"

echo "7️⃣  Pushing to GitHub..."
git push origin main
git push origin "v$VERSION"

echo ""
echo "✅ Code pushed to GitHub!"
echo ""
echo "📋 Next step: Create GitHub release"
echo "   URL: https://github.com/gundestrup/jekyll-imgflow/releases/new?tag=v$VERSION"
echo ""
echo "   Release notes (copied to clipboard if possible):"
echo "   ────────────────────────────────────────"
echo "$RELEASE_NOTES"
echo "   ────────────────────────────────────────"
echo ""

# Try to copy release notes to clipboard
if command -v pbcopy &> /dev/null; then
    echo "$RELEASE_NOTES" | pbcopy
    echo "✅ Release notes copied to clipboard!"
elif command -v xclip &> /dev/null; then
    echo "$RELEASE_NOTES" | xclip -selection clipboard
    echo "✅ Release notes copied to clipboard!"
fi

echo ""
echo "🔍 Post-release verification..."
echo "   Waiting 30 seconds for GitHub Actions to start..."
sleep 5

echo ""
echo "   The workflow will automatically:"
echo "   ✓ Build the gem"
echo "   ✓ Publish to RubyGems.org (via OIDC)"
echo ""
echo "   Verify at:"
echo "   • GitHub Actions: https://github.com/gundestrup/jekyll-imgflow/actions"
echo "   • RubyGems (in ~5 min): https://rubygems.org/gems/jekyll-imgflow"
echo ""
