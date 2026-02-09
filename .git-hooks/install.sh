#!/bin/bash
# Install git hooks to enforce worktree workflow
# Run from repo root: .git-hooks/install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_DIR="$(git rev-parse --git-dir)"
HOOKS_DIR="$GIT_DIR/hooks"

echo "Installing git hooks to enforce worktree workflow..."
echo "Git hooks directory: $HOOKS_DIR"
echo ""

# Ensure hooks directory exists
mkdir -p "$HOOKS_DIR"

# Install each hook
for hook in "$SCRIPT_DIR"/{pre-commit,pre-push}; do
    if [[ -f "$hook" ]]; then
        hook_name=$(basename "$hook")
        target="$HOOKS_DIR/$hook_name"
        
        # Backup existing hook if present
        if [[ -f "$target" ]]; then
            echo "⚠️  Backing up existing $hook_name to $hook_name.backup"
            mv "$target" "$target.backup"
        fi
        
        # Create symlink
        ln -sf "$hook" "$target"
        chmod +x "$target"
        echo "✅ Installed: $hook_name"
    fi
done

echo ""
echo "Git hooks installed successfully!"
echo ""
echo "What they do:"
echo "  • pre-commit: Block commits to main/master"
echo "  • pre-push:   Warn when pushing from main/master"
echo ""
echo "To bypass (use sparingly): git commit --no-verify"
