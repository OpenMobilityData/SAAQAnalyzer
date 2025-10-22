# Git Hooks

This directory contains version-controlled git hooks for the SAAQAnalyzer project.

## Installation

After cloning the repository or pulling changes that reset `.git/hooks/`, run:

```bash
./hooks/install-hooks.sh
```

This will copy the hooks from this directory to `.git/hooks/` and make them executable.

## Available Hooks

### pre-commit

**Purpose**: Automatically increments the Xcode build number (`CURRENT_PROJECT_VERSION`) to match the git commit count.

**What it does**:
1. Counts total commits in the repository
2. Calculates next build number (commit_count + 1)
3. Updates `CURRENT_PROJECT_VERSION` in `project.pbxproj` using `agvtool`
4. Stages the modified project file
5. Displays confirmation message

**Benefits**:
- ✅ Unique build number for every commit
- ✅ Monotonically increasing (App Store requirement)
- ✅ Automatic - no manual intervention
- ✅ Consistent across all developers

**Example output**:
```
✅ Build number updated to: 257
```

## Why Version-Controlled Hooks?

Git hooks normally live in `.git/hooks/` which is **not version controlled**. This means:
- Hooks are lost when repository is re-cloned
- Hooks are lost after git operations that reset `.git/`
- Each developer must manually set up hooks

By storing hooks in `hooks/` (version controlled) with an install script, we ensure:
- Hooks survive repo clones
- Easy setup for new developers
- Consistent behavior across team

## Troubleshooting

**Hook not running?**
- Run `./hooks/install-hooks.sh` again
- Verify `.git/hooks/pre-commit` exists and is executable: `ls -la .git/hooks/pre-commit`

**Build number out of sync?**
- Manually update: `xcrun agvtool new-version -all $(git rev-list --count HEAD)`
- Next commit will continue from corrected value
