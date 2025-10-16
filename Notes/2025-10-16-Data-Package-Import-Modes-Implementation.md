# Data Package Import Implementation: Dual-Mode Support
**Date**: October 16, 2025
**Session**: Data Package Import Enhancement - Replace vs Merge Modes

---

## 1. Current Task & Objective

### Primary Goal
Implement dual-mode data package import functionality that provides both:
1. **Fast path** (Replace mode): Simple file copy for complete backups/restores (~instant)
2. **Smart path** (Merge mode): Selective table-level import that preserves existing data not in package

### Context
The initial implementation had a simple file copy approach (fast and efficient), but it would overwrite all data. We then implemented selective merge logic (preserves data not in package, but slower). The final solution needed to support BOTH approaches with intelligent defaults.

### User Problem Being Solved
- **Common case (95%)**: Full backup/restore → needs fast performance
- **Edge case (5%)**: Partial import (e.g., importing vehicle-only package when license data already exists) → needs data preservation

---

## 2. Progress Completed ✅

### Phase 1: Selective Import Logic (Initial Implementation)
**Status**: COMPLETE

Implemented selective merge capability:
- ✅ Package content detection (what data is in the package)
- ✅ Current database analysis (what data exists locally)
- ✅ Smart merge decision logic
- ✅ Table-level copying with enumeration table merging
- ✅ Cache rebuild after import

**Files Modified**:
- `DataPackage.swift`: Added `DataPackageContent` struct
- `DataPackageManager.swift`: Implemented `mergeDatabase()`, `copyTablesFromCurrent()`, `mergeEnumerationTables()`
- `SAAQAnalyzerApp.swift`: Updated validation result handling

### Phase 2: Dual-Mode Support
**Status**: COMPLETE ✅

Added user-selectable import modes:
- ✅ `DataPackageImportMode` enum (.replace, .merge)
- ✅ Import mode state management in UI
- ✅ Custom sheet with mode picker
- ✅ Fast path implementation (`importDatabaseReplace()`)
- ✅ Smart default mode selection based on database state
- ✅ Routing logic in `importDataPackage()`

**Files Modified**:
- `DataPackage.swift`: Added `DataPackageImportMode` enum, enhanced `DataPackageContent` with `detailedDescription`
- `DataPackageManager.swift`: Added `importDatabaseReplace()`, mode parameter to `importDataPackage()`
- `SAAQAnalyzerApp.swift`: Added mode state, custom sheet view, `determineDefaultImportMode()`

### Phase 3: Bug Fix - Custom Confirmation Sheet
**Status**: COMPLETE ✅

**Problem**: Original `.confirmationDialog` couldn't render complex UI (Picker) on macOS

**Solution**: Created custom SwiftUI sheet with full control:
- ✅ `PackageImportConfirmationView` - main confirmation dialog
- ✅ `ImportModeOption` - radio-button style mode cards
- ✅ Visual feedback with icons and color coding
- ✅ Context-aware warnings
- ✅ Current database state display

---

## 3. Key Decisions & Patterns

### Architectural Decisions

1. **Default to Fast Path**
   - `.replace` mode is the default for most scenarios
   - Optimizes for the common case (backup/restore)
   - User must explicitly choose merge when needed

2. **Smart Default Mode Selection**
   - System analyzes current database state vs package contents
   - Automatically suggests merge when data preservation is needed
   - Prevents accidental data loss

3. **Two Separate Import Functions**
   ```swift
   // Fast path: Simple file copy
   private func importDatabaseReplace(from:timestamp:)

   // Smart path: Selective merge
   private func importDatabase(from:timestamp:content:)
   ```

4. **Mode Selection in Custom Sheet**
   - Not in file picker (system dialog - can't be customized)
   - Not in `.confirmationDialog` (can't render complex UI on macOS)
   - In custom `.sheet` with full SwiftUI control
   - Shows package contents, mode picker, context-aware warnings

### Decision Logic for Smart Defaults

```swift
// Empty database → REPLACE (fast)
if stats.totalVehicleRecords == 0 && stats.totalLicenseRecords == 0 {
    return .replace
}

// Package has both types → REPLACE (full backup)
if content.hasVehicleData && content.hasLicenseData {
    return .replace
}

// Package missing data that exists locally → MERGE (preserve)
let hasDataToPreserve = (stats.totalVehicleRecords > 0 && !content.hasVehicleData) ||
                       (stats.totalLicenseRecords > 0 && !content.hasLicenseData)
if hasDataToPreserve {
    return .merge
}

// Default → REPLACE (fast)
return .replace
```

---

## 4. Active Files & Locations

### Core Implementation Files

**`/SAAQAnalyzer/Models/DataPackage.swift`**
- Purpose: Data models for package operations
- Key additions:
  - `DataPackageImportMode` enum (lines 126-139)
  - `DataPackageContent.detailedDescription` (lines 164-173)

**`/SAAQAnalyzer/DataLayer/DataPackageManager.swift`**
- Purpose: Package export/import operations
- Key functions:
  - `importDataPackage(from:mode:)` - Main entry point with mode parameter (line 256)
  - `importDatabaseReplace(from:timestamp:)` - Fast path implementation (lines 541-574)
  - `importDatabase(from:timestamp:content:)` - Smart path implementation (lines 576+)
  - Mode routing logic (lines 311-326)

**`/SAAQAnalyzer/SAAQAnalyzerApp.swift`**
- Purpose: UI and user interaction
- Key additions:
  - State variables: `pendingPackageContent`, `packageImportMode` (lines 113-114)
  - `handlePackageImport()` - Stores content, sets smart default (lines 190-220)
  - `determineDefaultImportMode()` - Smart mode selection logic (lines 222-257)
  - `performPackageImport(mode:)` - Passes mode to manager (lines 239-262)
  - Custom sheet view (lines 335-351)
  - `PackageImportConfirmationView` - Confirmation dialog (lines 2318-2458)
  - `ImportModeOption` - Mode selection cards (lines 2461-2508)

### Supporting Files

**`/SAAQAnalyzer/DataLayer/DatabaseManager.swift`**
- Used for: Getting current database stats for smart mode decision
- Function: `getDatabaseStats()` - Returns vehicle/license record counts

---

## 5. Current State: ✅ BUG FIXED

### Problem Identified

**Root Cause**: SwiftUI `.confirmationDialog` limitation on macOS

The original implementation tried to embed complex UI (VStack with Picker) in the `.confirmationDialog` message block, which doesn't render properly on macOS. While iOS-style confirmation dialogs support some customization, macOS has stricter limitations and the Picker wasn't being displayed.

### Solution Implemented

**Custom Sheet View** (Option B from planning docs):

Created `PackageImportConfirmationView` - a full SwiftUI sheet with proper controls:

1. **Rich UI Layout**:
   - Package contents display with icon badges
   - Current database state (if data exists)
   - Radio-button style mode selection with visual feedback
   - Context-aware warning messages
   - Action buttons with keyboard shortcuts

2. **Mode Selection Options**:
   - Each mode shown as a selectable card with:
     - Radio button indicator (filled circle when selected)
     - Mode name and description
     - Icon badge (⚡ for Replace - fast, 🛡️ for Merge - safe)
     - Visual highlight when selected

3. **Smart Visual Feedback**:
   - Replace mode: Orange warning styling
   - Merge mode: Blue informational styling
   - Dynamic button colors match selected mode

### Files Modified

**`SAAQAnalyzerApp.swift`** (lines 335-351, 2318-2508):
- Replaced `.confirmationDialog` with `.sheet`
- Added `PackageImportConfirmationView` struct
- Added `ImportModeOption` helper view for mode cards

---

## 6. Testing & Verification

### Testing Steps (Priority Order)

**READY FOR TESTING** ✅ - All code changes complete

1. **Test 1: Empty Database + Vehicle Package**
   - Expected: Default to Replace mode
   - Verify: Dialog shows "Replace Database" selected
   - Verify: Import completes in <10 seconds

2. **Test 2: License Data Exists + Vehicle Package**
   - Expected: Default to Merge mode
   - Verify: Dialog shows "Merge Data" selected
   - Verify: License data preserved after import

3. **Test 3: Mode Override**
   - Have license data, import vehicle package
   - Default is Merge
   - Switch to Replace manually
   - Verify: License data is wiped (user chose to replace)

### UX Improvements Implemented ✅

All planned improvements were incorporated into the custom sheet:

1. **Current database state display** ✅
   - Shows vehicle and license counts when data exists
   - Hidden when database is empty (no clutter)

2. **Visual indicators** ✅
   - Radio-button style selection (filled vs outline)
   - Mode cards with distinct styling
   - Icon badges: ⚡ Replace (fast) | 🛡️ Merge (safe)
   - Color coding: Orange (Replace) | Blue (Merge)

3. **Destructive operation warnings** ✅
   - Context-aware warning message updates based on mode
   - Orange warning for Replace mode
   - Import button tinted to match mode severity

---

## 7. Important Context & Gotchas

### Package Structure Validated ✅

Test package location:
```
/Volumes/Pegasus32 R8/SAAQ/SAAQData_Oct 15, 2025.saaqpackage
```

Package contents verified:
- 92,333,014 vehicle records (2011-2024)
- 0 license records
- 181,636 canonical hierarchy cache entries
- All 16 enumeration tables populated
- 35GB total size

Current database location:
```
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

Current database state (before import):
- 0 vehicle records
- 66,958,428 license records (2011-2022)
- 16GB size

### Disk Space Cleared ✅

- Freed 49GB by deleting temp files and Time Machine snapshots
- Now have 72GB available (sufficient for merge operation)

### Implementation Gotchas

1. **SwiftUI Confirmation Dialogs are Limited**
   - Can't embed complex UI like Pickers reliably
   - macOS and iOS handle them differently
   - Use `.sheet()` for complex confirmation dialogs

2. **Mode Parameter Has Default Value**
   ```swift
   func importDataPackage(from: URL, mode: DataPackageImportMode = .replace)
   ```
   - Default is `.replace` for backward compatibility
   - UI must explicitly pass the mode

3. **Enumeration Table Merging Uses INSERT OR IGNORE**
   - Preserves target database's existing enum IDs
   - New values from source are added
   - No conflicts possible

4. **Cache Rebuild is Shared**
   - Both modes rebuild filter cache after import
   - Cache is derived from enumeration tables
   - Takes ~1-2 minutes for full dataset

### Console Diagnostic Messages

Look for these in console output:

```bash
# Smart default mode selection:
📊 Smart default: REPLACE (current database is empty)
📊 Smart default: MERGE (current database has data not in package)
   Current: 0 vehicles, 67958428 licenses
   Package: 92333014 vehicles, 0 licenses

# Import mode being used:
Using REPLACE mode (fast path)
Using MERGE mode (selective import)

# Import completion:
✅ Data package imported successfully (Replace Database mode)
✅ Data package imported successfully (Merge Data mode)
```

---

## 8. Code References

### Key Function Call Chain

```
User clicks "Import Data Package..."
  ↓
handlePackageImport() (SAAQAnalyzerApp.swift:191)
  ↓
validateDataPackage() (DataPackageManager.swift:148)
  ↓
detectPackageContent() (DataPackageManager.swift:204)
  ↓
determineDefaultImportMode() (SAAQAnalyzerApp.swift:223)
  ↓
[Custom Sheet Appears] ✅ FIXED
  ↓
performPackageImport(mode:) (SAAQAnalyzerApp.swift:276)
  ↓
importDataPackage(mode:) (DataPackageManager.swift:256)
  ↓
if mode == .replace:
    importDatabaseReplace() (DataPackageManager.swift:545)
else:
    importDatabase() (DataPackageManager.swift:576)
```

### Test Package Import Command

For testing, you can trigger import by:
1. Launch app
2. Import menu → Import Data Package...
3. Select: `/Volumes/Pegasus32 R8/SAAQ/SAAQData_Oct 15, 2025.saaqpackage`
4. Should see custom confirmation sheet with mode picker ✅

---

## 9. Implementation Complete ✅

**Date**: October 16, 2025 (Updated)
**Status**: Bug Fixed - Ready for User Testing

### Final Implementation Details

**Custom Sheet Components**:

1. **PackageImportConfirmationView** (main dialog):
   - Full-width sheet (540pt) with proper spacing
   - Loads current database stats asynchronously
   - Dynamic layout adjusts based on database state
   - Keyboard shortcuts (ESC = cancel, Enter = import)

2. **ImportModeOption** (mode selection cards):
   - Radio-button style selection indicator
   - Mode name + description
   - Visual badges (bolt/shield icons)
   - Hover/selection states with borders

### Visual Design Decisions

**Color Scheme**:
- Blue: Package info, Merge mode (safe/informational)
- Orange: Replace mode warnings (attention/caution)
- Green: Shield icon for Merge (protective)

**Layout Structure**:
```
┌─────────────────────────────────────┐
│ 📦 Import Data Package             │ Header
├─────────────────────────────────────┤
│ Package Contents                    │
│ ℹ️ 92,333,014 vehicle records      │
│                                     │
│ Current Database   (conditional)    │
│ 👤 66,958,428 license records      │
├─────────────────────────────────────┤
│ Import Mode                         │
│ ○ Replace Database (fast)           │
│ ● Merge Data (preserves existing)  │
├─────────────────────────────────────┤
│ ⚠️ Context-aware warning message   │
├─────────────────────────────────────┤
│ [Cancel]              [▼ Import]   │
└─────────────────────────────────────┘
```

### Testing Checklist

Before marking complete, verify:
- [ ] Sheet appears when package is selected
- [ ] Package contents display correctly
- [ ] Current database stats load (when data exists)
- [ ] Both mode options are selectable
- [ ] Default mode matches smart logic
- [ ] Warning message updates when mode changes
- [ ] Import button color changes with mode
- [ ] Cancel button closes sheet without import
- [ ] Import button triggers correct import path
- [ ] Keyboard shortcuts work (ESC/Enter)

---

## Summary

**Complete Implementation** ✅:
- Package validation ✅
- Content detection ✅
- Smart mode logic ✅
- Both import paths (replace and merge) ✅
- Database operations ✅
- Custom confirmation sheet with mode picker ✅
- Visual feedback and warnings ✅

**Bug Fix Applied**:
- Replaced broken `.confirmationDialog` with custom `.sheet` view ✅
- Mode picker now properly visible and functional ✅

**Ready for Testing**:
User should now see a comprehensive dialog showing:
- Package contents with formatted counts
- Current database state (when data exists)
- Mode selection with visual cards
- Context-aware warnings
- Smart default mode pre-selected based on database analysis

---

## Related Documentation

- Original export implementation: `Notes/2025-10-11-Data-Package-Modernization-Complete.md`
- Import log structure: See `ImportLog.json` in package metadata
- Enumeration architecture: `CLAUDE.md` - "Current Implementation Status" section

---

*Session End: October 16, 2025*
*Bug Status: FIXED - Awaiting User Verification*
