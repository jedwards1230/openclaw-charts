# Git Hooks - Worktree Workflow Enforcement

Git hooks to enforce worktree-based development and prevent accidental commits to main/master branches.

## Quick Start

```bash
# Install hooks (run from repo root)
.git-hooks/install.sh
```

## What Gets Installed

### `pre-commit`
- **Blocks** commits to `main` or `master` branches
- Suggests worktree workflow
- Can be bypassed with `--no-verify` (use sparingly!)

### `pre-push`
- **Warns** when pushing from `main` or `master`
- Prompts for confirmation
- Catches cases where hook was bypassed

## Worktree Workflow

### Creating a Worktree

```bash
# From repo root
git worktree add worktrees/my-feature -b my-feature origin/main
cd worktrees/my-feature

# Make changes, commit freely
git add .
git commit -m "My changes"
git push -u origin my-feature
```

### After PR Merge

```bash
# Return to repo root
cd ../..

# Remove worktree
git worktree remove worktrees/my-feature

# Clean up branch
git branch -d my-feature

# Update main
git fetch origin
git checkout main
git merge --ff-only origin/main
```

## Why This Pattern?

### Problems it prevents:
- ❌ Accidental commits to main/master
- ❌ Forgetting to create feature branch
- ❌ Working on main and discovering it too late
- ❌ Complicated git history from fixing mistakes

### Benefits:
- ✅ Main/master stays pristine (just for pulling updates)
- ✅ Easy context-switching between features
- ✅ Clear separation: base repo vs active work
- ✅ Simple cleanup after PR merge
- ✅ Prevents git mistakes before they happen

## Limitations

Git hooks are **client-side only**:
- Each person installs manually
- Can be bypassed with `--no-verify`
- Can't prevent all git operations (checkout, reset, etc.)

**Recommendation**: Use hooks as training wheels, not locks. Combine with:
- Server-side branch protection (GitHub/GitLab)
- Code review culture
- Documentation (AGENTS.md patterns)

## Uninstall

```bash
# Remove symlinks
rm .git/hooks/pre-commit
rm .git/hooks/pre-push

# Restore backups if they exist
mv .git/hooks/pre-commit.backup .git/hooks/pre-commit
mv .git/hooks/pre-push.backup .git/hooks/pre-push
```

## Customization

Edit hooks in `.git-hooks/` (version controlled), not `.git/hooks/` (local only).

After editing, reinstall:
```bash
.git-hooks/install.sh
```
