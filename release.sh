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

# Check for untracked files. Release commits only stage tracked changes, so
# fail early instead of silently omitting or accidentally including new files.
echo "🔍 Checking git status..."
UNTRACKED=$(git ls-files --others --exclude-standard)
if [[ -n "$UNTRACKED" ]]; then
    echo "❌ Untracked files detected; commit or remove them before releasing:"
    echo "$UNTRACKED"
    exit 1
fi
echo "✅ No untracked files"
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

if ! grep -q "jekyll-imgflow ($VERSION)" Gemfile.lock; then
    echo "❌ Gemfile.lock does not reference jekyll-imgflow $VERSION"
    echo "Run ./bump_version.sh or bundle lock before releasing."
    exit 1
fi
echo "✅ Gemfile.lock matches v$VERSION"
echo ""

# Check that this version has not already been tagged.
if git rev-parse --verify --quiet "refs/tags/v$VERSION" >/dev/null || \
   git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then
    echo "❌ Tag v$VERSION already exists"
    exit 1
fi
echo "✅ Tag v$VERSION is available"
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

if [[ "$DRY_RUN" == true ]]; then
    echo "📋 DRY RUN: Would commit, tag, push, and create GitHub release v$VERSION"
    echo "✅ Dry run completed successfully"
    exit 0
fi

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
echo "8️⃣  Creating GitHub release page..."
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI (gh) is required to create the release page"
    exit 1
fi
if ! gh release create "v$VERSION" --title "v$VERSION" --notes "$RELEASE_NOTES"; then
    echo "❌ GitHub release page creation failed"
    exit 1
fi

echo "✅ GitHub release page created"
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
