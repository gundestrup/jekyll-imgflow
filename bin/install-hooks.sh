#!/bin/bash
# Install git hooks for jekyll-imgflow
#
# pre-commit:  rubocop + semgrep (fast, ~5s)
# pre-push:    rubocop + rspec (full quality gate before pushing)
#              + docker image version check when pushing a v* tag
#
# Usage: bin/install-hooks.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

mkdir -p "$HOOKS_DIR"

# pre-commit: fast style + security check
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
# Pre-commit hook — fast style + security check
# Full tests run on pre-push and in CI

echo "🔍 Running RuboCop..."
if ! bundle exec rubocop --force-exclusion; then
    echo "❌ Style checks failed"
    echo "Fix the issues or use 'git commit --no-verify' to skip"
    exit 1
fi

echo "🔍 Running Semgrep security scan..."
if ! semgrep scan --config .semgrep.yml --error lib/ 2>&1; then
    echo "❌ Semgrep scan failed"
    echo "Fix the issues or use 'git commit --no-verify' to skip"
    exit 1
fi

echo "✅ Style and security checks passed"
exit 0
HOOK
chmod +x "$HOOKS_DIR/pre-commit"

# pre-push: full quality gate (rubocop + rspec, mirrors CI) + docker image check on tags
cat > "$HOOKS_DIR/pre-push" << 'HOOK'
#!/bin/bash
# Pre-push hook — full quality gate before pushing
# Runs the same checks as CI (rake ci) to catch failures locally
# Reads stdin (list of refs being pushed) to detect release tag pushes

# Read the list of refs being pushed
PUSHING_TAG=false
while read -r local_ref local_sha remote_ref remote_sha; do
    if [[ "$remote_ref" == refs/tags/v* ]]; then
        PUSHING_TAG=true
    fi
done

echo "🔍 Running pre-push checks (rubocop + rspec, mirrors CI)..."
echo ""

if bundle exec rake ci 2>&1 | grep -q "✅ CI checks passed"; then
    echo ""
    echo "✅ Pre-push checks passed (same as CI)"
else
    echo ""
    echo "❌ Pre-push checks failed"
    echo ""
    echo "Fix the issues or use 'git push --no-verify' to skip"
    exit 1
fi

# Only check Docker image pins when pushing a release tag
if [ "$PUSHING_TAG" = true ]; then
    echo ""
    echo "🏷️  Release tag detected — checking Docker image pins..."
    echo ""
    if bundle exec rake check_docker_images 2>&1 | grep -q "⚠️"; then
        echo ""
        echo "❌ Docker image pins are outdated"
        echo "   Update docker-compose.base.yml and re-run: rake start_services"
        echo "   Skip with: git push --no-verify"
        exit 1
    else
        echo "✅ Docker image pins are current"
    fi
fi

exit 0
HOOK
chmod +x "$HOOKS_DIR/pre-push"

echo "✅ Installed git hooks:"
echo "   pre-commit:  rubocop + semgrep (fast, ~5s)"
echo "   pre-push:    rubocop + rspec (mirrors CI, includes external tests)"
echo "                + docker image version check when pushing v* tags"
echo ""
echo "   Skip with: git commit --no-verify  /  git push --no-verify"
