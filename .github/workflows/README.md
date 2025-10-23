# GitHub Actions Workflows

This directory contains automated workflows for the SAAQAnalyzer project.

## increment-build-number.yml

**Purpose**: Automatically increments the Xcode build number based on merge commits to `main`.

**Trigger**: Runs on every push to the `main` branch (typically from merged pull requests).

**What it does**:
1. Counts all merge commits to `main` branch
2. Sets `CURRENT_PROJECT_VERSION` to match merge commit count
3. Commits the updated `project.pbxproj` back to `main`
4. Uses `[skip ci]` tag to prevent infinite workflow loops

**Benefits**:
- ✅ **Zero setup required** - Works automatically for all developers and clones
- ✅ **Milestone-based** - Build number only increments on merges to main
- ✅ **Automatic** - No manual intervention or git config commands needed
- ✅ **App Store compatible** - Monotonically increasing build numbers
- ✅ **Meaningful** - Build number = number of releases/milestones

**Build Number Calculation**:
```bash
# Build number = count of merge commits to main
git rev-list --count --merges origin/main
```

**Example Workflow**:
1. Developer creates PR from `feature-branch` → `main`
2. PR is merged to `main` (creates merge commit)
3. GitHub Actions workflow runs automatically
4. Build number increments (e.g., 30 → 31)
5. Change committed to `main` with `[skip ci]` tag
6. All future clones automatically have correct build number

**Viewing Workflow Runs**:
- Go to: https://github.com/OpenMobilityData/SAAQAnalyzer/actions
- Click on "Increment Build Number" workflow
- View logs for each run

**Troubleshooting**:

**Workflow not running?**
- Check Actions tab on GitHub for errors
- Verify workflow file syntax: `.github/workflows/increment-build-number.yml`
- Ensure GitHub Actions are enabled in repository settings

**Build number out of sync locally?**
- Pull latest from main: `git pull origin main`
- The workflow commits the build number change to main
- Your local branch will get the updated number on next pull

**Need to manually sync?**
```bash
# Count merge commits
MERGE_COUNT=$(git rev-list --count --merges origin/main)

# Update build number
xcrun agvtool new-version -all "$MERGE_COUNT"

# Commit (optional)
git add SAAQAnalyzer.xcodeproj/project.pbxproj
git commit -m "chore: Sync build number to $MERGE_COUNT"
```

## Differences from Git Hooks

**Git Hooks** (old approach):
- ❌ Required `git config core.hooksPath hooks/` after every clone
- ✅ Incremented on every commit (more granular)
- ❌ Developer-side setup required

**GitHub Actions** (new approach):
- ✅ Zero setup required - works automatically
- ✅ Increments only on main branch merges (milestones)
- ✅ Server-side automation
- ✅ Centralized and consistent across all developers

## Migration from Git Hooks

The git hooks in `hooks/` directory are now deprecated in favor of GitHub Actions.

**For existing clones with hooks configured**:
```bash
# Remove hooks path configuration (optional cleanup)
git config --unset core.hooksPath

# Pull latest changes from main to get GitHub Actions build number
git pull origin main
```

The hooks directory is retained in the repository for reference but is no longer actively used.
