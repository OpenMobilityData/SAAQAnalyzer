# Git Hooks

This directory contains version-controlled git hooks for the SAAQAnalyzer project.

## Installation (Recommended)

**Best method** - Use Git's `core.hooksPath` configuration to point directly to this version-controlled directory:

```bash
git config core.hooksPath hooks/
```

This eliminates the need to copy files and works immediately after cloning. **This is the preferred approach.**

## Alternative Installation

If you prefer the traditional approach, copy hooks to `.git/hooks/`:

```bash
./hooks/install-hooks.sh
```

**Note**: This method requires re-running after operations that reset `.git/hooks/`.

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

By storing hooks in `hooks/` (version controlled) and using `core.hooksPath`, we ensure:
- ✅ Hooks survive repo clones (just need one `git config` command)
- ✅ Easy setup for new developers (documented in README)
- ✅ Consistent behavior across team
- ✅ No copying required - hooks run directly from version control

## Troubleshooting

**Hook not running?**
- **If using core.hooksPath**: Verify configuration: `git config core.hooksPath` (should output `hooks/`)
- **If using install script**: Run `./hooks/install-hooks.sh` again and verify `.git/hooks/pre-commit` exists
- Check hook is executable: `ls -la hooks/pre-commit` (should show `rwxr-xr-x`)

**Build number out of sync?**
- Check current commit count: `git rev-list --count HEAD`
- Manually sync: `xcrun agvtool new-version -all $(git rev-list --count HEAD)`
- Next commit will auto-increment from corrected value

**After fresh clone, build number not incrementing?**
- Run: `git config core.hooksPath hooks/`
- This is required once per clone and persists for that repository
