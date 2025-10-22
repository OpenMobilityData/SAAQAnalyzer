#!/bin/bash
# Install git hooks from the hooks/ directory to .git/hooks/

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/hooks"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Installing git hooks..."

# Copy pre-commit hook
if [ -f "$HOOKS_DIR/pre-commit" ]; then
    cp "$HOOKS_DIR/pre-commit" "$GIT_HOOKS_DIR/pre-commit"
    chmod +x "$GIT_HOOKS_DIR/pre-commit"
    echo "✅ Installed pre-commit hook (auto-increments build number)"
else
    echo "❌ pre-commit hook not found in $HOOKS_DIR"
    exit 1
fi

echo ""
echo "🎉 Git hooks installed successfully!"
echo ""
echo "The pre-commit hook will automatically:"
echo "  - Update build number to match git commit count"
echo "  - Stage the updated project.pbxproj file"
echo ""
