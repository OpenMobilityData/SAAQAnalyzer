# Data Package Export/Import System - Bug Fixes Complete
**Date**: October 16, 2025
**Session**: Critical bug fixes for package export temp cleanup and import cache invalidation

---

## 1. Current Task & Objective

### Primary Goal
Fix two critical bugs in the data package export/import system:

1. **Temp package cleanup** - Package exports were leaving massive duplicate files in container's temp directory
2. **Cache invalidation during import** - Filter cache not rebuilding during package import, causing stale/empty UI data

### Context
The dual-mode import system (Replace/Merge) was recently implemented but had critical bugs preventing production use with large datasets (35GB vehicle + 16GB license = ~51GB packages).

---

## 2. Progress Completed ✅

### Phase 1: Package Export Temp Cleanup (COMPLETE)
**Problem**: `DataPackageDocument.fileWrapper()` creates packages in container's temp directory but never cleans them up.

**Root Cause**:
- Line 1209: Package created at `FileManager.default.temporaryDirectory`
- FileWrapper created with `.immediate` flag (loads into memory)
- **Missing**: Cleanup after FileWrapper creation
- **Impact**: With 51GB packages, disk fills rapidly

**Solution Applied** (`SAAQAnalyzerApp.swift:1258-1267`):
```swift
// Clean up temp staging area immediately
// CRITICAL: Prevents accumulation of massive package files in container temp directory
// The FileWrapper has already copied the data into memory with .immediate flag
do {
    try FileManager.default.removeItem(at: packageURL)
    print("🗑️  Cleaned up temp staging area: \(packageURL.lastPathComponent)")
} catch {
    print("⚠️  Warning: Could not clean up temp package: \(error.localizedDescription)")
    // Don't throw - cleanup failure shouldn't break export
}
```

**Testing**: ✅ Verified working - console shows cleanup message, temp dir stays empty

---

### Phase 2: Cache Invalidation During Import (COMPLETE)
**Problem**: Filter cache not rebuilding during package import

**Root Cause**:
- `FilterCacheManager.initializeCache()` has guard: `guard !isInitialized else { return }`
- During import, cache already marked as initialized from app launch
- Calling `initializeCache()` returned early without rebuilding

**Solution Applied** (`DataPackageManager.swift:334-335`):
```swift
// CRITICAL: Invalidate cache first to allow reinitialization
filterCacheManager.invalidateCache()

try await filterCacheManager.initializeCache()
```

**Testing**: ✅ Verified working with 10K vehicle test package
- Console shows "Rebuilding filter cache from imported database"
- Filter panel updates immediately (no app relaunch needed)
- Filter dropdowns populated correctly (14 years, 17 regions, 104 MRCs, 917 municipalities)

---

### Phase 3: Schema Issues Fixed (COMPLETE)

#### Issue 3.1: Missing Index (Fixed)
**Problem**: Index creation failing during database setup
```
no such column: experience_global in "CREATE INDEX ... ON licenses(experience_global);"
```

**Root Cause**: Typo in index SQL - missing `_id` suffix

**Fix Applied** (`DatabaseManager.swift:904`):
```swift
// WRONG (old)
"CREATE INDEX IF NOT EXISTS idx_licenses_experience_distinct ON licenses(experience_global);"

// CORRECT (fixed)
"CREATE INDEX IF NOT EXISTS idx_licenses_experience_distinct ON licenses(experience_global_id);"
```

**Status**: ✅ Fixed in code + manually created in current database

---

#### Issue 3.2: Legacy Schema Fallback (Fixed)
**Problem**: `getMunicipalitiesFromDatabase()` had fallback to legacy `geo_code` column

**Root Cause**: Development artifact from migration period

**Fix Applied** (`DatabaseManager.swift:4284-4293`):
- Removed fallback query: `SELECT DISTINCT geo_code FROM vehicles`
- Simplified to only use `geographic_entities` table

**Status**: ✅ Removed legacy fallback

---

### Phase 4: Test Dataset Creation (COMPLETE)
Created graduated license test datasets matching vehicle data pattern:

**Created Directories**:
- `~/Desktop/SAAQ_Data/Permis_Conduire_Test_10K` - 10K records/year (18 MB total)
- `~/Desktop/SAAQ_Data/Permis_Conduire_Test_100K` - 100K records/year (177 MB total)
- `~/Desktop/SAAQ_Data/Permis_Conduire_Test_1M` - 1M records/year (1.9 GB total)

**Purpose**: Graduated testing approach from functionality verification to stress testing

---

## 3. Key Decisions & Patterns

### Architectural Decisions

1. **No Automatic Schema Migration**
   - Schema changes are development artifacts, not production workflow
   - Production path: fresh start → import CSVs → export/import optimized packages
   - Legacy schema only exists from development-phase packages

2. **Explicit Cache Invalidation Pattern**
   - When replacing database completely: `invalidate() → initialize()`
   - Ensures fresh reload from enumeration tables
   - Applies to package import and any future database replacement operations

3. **Custom Sheet for Complex UI**
   - `.confirmationDialog` has macOS limitations (can't embed Pickers)
   - Use `.sheet()` with custom SwiftUI views for complex interactions
   - Provides full control over layout, state, and user feedback

4. **Smart Default Import Mode**
   - Analyze current database vs package contents
   - Default to Replace (fast) for most scenarios
   - Auto-suggest Merge when data preservation needed

### Import Mode Decision Logic (`SAAQAnalyzerApp.swift:223-257`)
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
if hasDataToPreserve {
    return .merge
}

// Default → REPLACE (fast)
return .replace
```

---

## 4. Active Files & Locations

### Core Implementation Files

**`SAAQAnalyzer/DataLayer/DataPackageManager.swift`**
- Purpose: Package export/import operations
- Key modification (lines 328-340): Cache invalidation fix
- Import functions:
  - `importDataPackage(from:mode:)` - Main entry point (line 256)
  - `importDatabaseReplace(from:timestamp:)` - Fast path (line 549)
  - `importDatabase(from:timestamp:content:)` - Merge path (line 585)

**`SAAQAnalyzer/SAAQAnalyzerApp.swift`**
- Purpose: UI and user interaction for package operations
- Key modifications:
  - Custom confirmation sheet (lines 335-351)
  - `PackageImportConfirmationView` (lines 2318-2458)
  - `ImportModeOption` helper view (lines 2461-2508)
  - `DataPackageDocument.fileWrapper()` temp cleanup (lines 1258-1267)
  - `determineDefaultImportMode()` logic (lines 223-257)

**`SAAQAnalyzer/Models/DataPackage.swift`**
- Purpose: Data models for package operations
- Key structures:
  - `DataPackageImportMode` enum (lines 126-139)
  - `DataPackageContent` struct with `detailedDescription` (lines 164-173)

**`SAAQAnalyzer/DataLayer/FilterCacheManager.swift`**
- Purpose: Manages filter cache from enumeration tables
- Key functions:
  - `initializeCache()` - Has guard for `isInitialized` (line 56)
  - `invalidateCache()` - Resets flag and clears cached data

**`SAAQAnalyzer/DataLayer/DatabaseManager.swift`**
- Purpose: Core database operations
- Key modifications:
  - Fixed index SQL for `experience_global_id` (line 904)
  - Removed legacy `geo_code` fallback (lines 4284-4293)
- Key functions:
  - `createTablesIfNeeded()` - Creates schema on fresh database (line 773)
  - `reconnectDatabase()` - Reopens connection after import (line 747)
  - `getDatabaseStats()` - Used for smart mode selection

**`SAAQAnalyzer/UI/FilterPanel.swift`**
- Purpose: Left panel with filter controls
- Key observation:
  - Already observes `dataVersion` changes (lines 289-292, 314-316)
  - Automatically reloads filter options when `dataVersion` increments

---

### Test Data Locations

**Vehicle Test Data** (existing):
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_1K` - 1K records/year
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_10K` - 10K records/year
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_100K` - 100K records/year
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_1M` - 1M records/year

**License Test Data** (newly created):
- `~/Desktop/SAAQ_Data/Permis_Conduire_Test_10K` - 10K records/year
- `~/Desktop/SAAQ_Data/Permis_Conduire_Test_100K` - 100K records/year
- `~/Desktop/SAAQ_Data/Permis_Conduire_Test_1M` - 1M records/year

**Test Package**:
- `~/Desktop/SAAQ_Data/Vehicles/Package_Testing/SAAQData_Vehicle_10K_test.saaqpackage`
- Contains: 140,000 vehicle records (10K/year × 14 years)
- Schema: Optimized with integer foreign keys
- Status: Successfully exported and imported

---

## 5. Current State

### What's Working ✅

1. **Package Export**:
   - ✅ Temp staging area cleanup working
   - ✅ Console shows "🗑️ Cleaned up temp staging area" message
   - ✅ No accumulation in container temp directory

2. **Package Import**:
   - ✅ Cache invalidation working
   - ✅ FilterPanel updates immediately (no relaunch needed)
   - ✅ Correct data displayed after import

3. **Database Schema**:
   - ✅ `experience_global_id` index fixed
   - ✅ Legacy fallback removed from `getMunicipalitiesFromDatabase()`

### Known Limitations

1. **Legacy Schema Packages**:
   - Packages with old string columns (`geo_code`, `class`, `mrc`) won't work
   - Query errors: "no such column: geo_code"
   - **Workaround**: Use packages from optimized schema installations only

2. **Legacy Code Paths** (deferred decision):
   - Legacy query functions in `DatabaseManager.swift` still reference old columns
   - Migration code in `CategoricalEnumManager.swift` and `SchemaManager.swift` still present
   - **Status**: Kept as safety net, not causing issues with optimized schema
   - **Decision deferred**: Remove in future session after further testing

---

## 6. Next Steps (Priority Order)

### IMMEDIATE: Test with Optimized Schema Package

**Prerequisites**:
Current database already has optimized schema with 140K vehicle records

**Test Sequence** (Incremental Dataset Sizes):

1. **Small Dataset Test** (10K - current state):
   - ✅ Already tested with vehicle package
   - ✅ Verified: Cache rebuilds, UI updates, filters populate

2. **Medium Dataset Test** (100K records):
   - Import 100K vehicle data via CSV
   - Export as package
   - Delete database
   - Import via Replace mode
   - Verify cache rebuild and UI refresh
   - Time the cache rebuild phase

3. **Large Dataset Test** (1M records):
   - Import 1M vehicle data via CSV
   - Export as package
   - Test Replace mode import
   - Monitor cache rebuild time and memory usage

4. **Merge Mode Test**:
   - Database with license data only
   - Import vehicle-only package
   - Select Merge mode (should be default)
   - Verify: Vehicle data added, license data preserved
   - Verify: Cache rebuilds for both data types

---

### SECONDARY: Console Output Verification

During import, look for these console messages:

**Expected Success Messages**:
```
Using REPLACE mode (fast path)
Database replaced successfully (fast path)
Rebuilding filter cache from imported database
🔄 Loading filter cache from enumeration tables...
✅ Loaded [N] filter options
UI refresh triggered (dataVersion: X)
```

**Error Messages to Watch For**:
```
no such column: geo_code         # Legacy schema - package is old
FilterCacheManager not available # Manager initialization failed
```

---

### TERTIARY: Performance Benchmarking

Once functionality confirmed, benchmark cache rebuild times:

| Dataset Size | Records | Expected Cache Rebuild Time |
|--------------|---------|----------------------------|
| Small        | 10K     | < 1 second                 |
| Medium       | 100K    | 10-30 seconds              |
| Large        | 1M      | 1-2 minutes                |
| Very Large   | 10M+    | 3-5 minutes                |

---

### FUTURE: Legacy Code Cleanup (Deferred)

**Decision Point**: Keep or remove legacy query paths?

**Arguments for keeping**:
- Safety net if optimized queries have issues
- Migration code useful for future schema changes
- Not causing problems with current optimized schema

**Arguments for removing**:
- Simpler codebase
- No maintenance burden for unused code
- Clear commitment to optimized-only approach

**Locations**:
- `DatabaseManager.swift`: Legacy query functions (lines ~1309, 2158, 3939, 4042)
- `CategoricalEnumManager.swift`: Migration enumeration code (line 499+)
- `SchemaManager.swift`: Schema migration code (line 204+)

---

## 7. Important Context & Gotchas

### Package Import Flow (Complete)

```
User clicks "Import Data Package..."
  ↓
File picker → user selects package → clicks "Open"
  ↓
handlePackageImport() validates package
  ↓
Custom sheet appears (PackageImportConfirmationView)
  ├─ Shows package contents
  ├─ Shows current database state
  ├─ Mode picker (Replace/Merge)
  └─ Smart default pre-selected
  ↓
User confirms → performPackageImport(url, mode)
  ↓
importDataPackage(from:mode:)
  ├─ Progress: 0.1 "Reading package info..."
  ├─ Progress: 0.2 "Backing up current data..."
  ├─ Progress: 0.4 "Importing database..."
  │   ├─ Replace mode: importDatabaseReplace() - file copy
  │   └─ Merge mode: importDatabase() - selective copy
  ├─ Progress: 0.7 "Rebuilding filter cache..."
  │   ├─ **invalidateCache()** ← FIX APPLIED
  │   └─ **initializeCache()** ← Now works
  ├─ Progress: 0.9 "Finalizing import..."
  │   └─ **dataVersion++** ← Triggers UI refresh
  └─ Progress: 1.0 "Import completed"
  ↓
FilterPanel.onReceive(dataVersion)
  └─ Reloads filter options from cache
```

---

### Schema Evolution History

**Legacy Schema** (pre-October 2025):
- String columns: `geo_code`, `class`, `mrc`, `make`, `model`, `fuel_type`
- Direct string comparisons in queries
- No enumeration tables

**Optimized Schema** (current):
- Integer FK columns: `admin_region_id`, `vehicle_class_id`, `mrc_id`, `make_id`, `model_id`, `fuel_type_id`
- 17 enumeration tables with indexes
- 5.6x performance improvement
- Created by `createTablesIfNeeded()` on fresh database

**Migration Status**:
- ❌ None implemented
- ❌ None planned
- ✅ `CREATE TABLE IF NOT EXISTS` preserves existing schema
- ✅ Fresh databases always get optimized schema

---

### Cache Architecture

**FilterCacheManager Lifecycle**:
1. Created during `DatabaseManager` initialization (DatabaseManager.swift:306)
2. First access triggers `initializeCache()` → loads from enumeration tables
3. Sets `isInitialized = true` flag
4. Subsequent calls return early due to guard (line 56)
5. **Must call `invalidateCache()`** before re-initialization

**Cache Data Sources**:
- Year options: `year_enum` table
- Make/Model: `make_enum`, `model_enum` tables
- Geographic: `admin_region_enum`, `mrc_enum`, `municipality_enum` tables
- Vehicle: `vehicle_class_enum`, `vehicle_type_enum` tables
- Fuel: `fuel_type_enum` table
- License: `age_group_enum`, `gender_enum`, `license_type_enum` tables

**Cache Invalidation Triggers**:
- ✅ Package import (fixed in this session)
- ✅ CSV import (already working)
- ⚠️ Manual invalidation via Settings (not yet implemented)

---

### Common Console Error Messages

**Schema Mismatch Errors** (expected during package validation):
```
no such column: geo_code in "SELECT DISTINCT geo_code FROM vehicles"
```
**Diagnosis**: Package has legacy schema, incompatible with current app
**Solution**: Use package from optimized schema installation

**Index Creation Errors** (fixed):
```
no such column: experience_global in "CREATE INDEX ..."
```
**Diagnosis**: Typo in index SQL (missing `_id` suffix)
**Solution**: ✅ Fixed in DatabaseManager.swift:904

**Cache Initialization Errors**:
```
FilterCacheManager not available
```
**Diagnosis**: FilterCacheManager wasn't initialized during DatabaseManager setup
**Solution**: Check DatabaseManager initialization sequence (line 306)

---

### Disk Space Requirements

**For Merge Operations**:
- Needs temporary copy of source database
- Temporary copy deleted after merge completes
- **Required space**: ~2x largest database size

**Example** (production):
- Vehicle database: 35GB
- License database: 16GB
- Merge operation: Needs ~70GB free (2x × 35GB)

---

### Confirmation Dialog Evolution

**Attempt #1** (Failed):
- Used `.confirmationDialog` with VStack + Picker
- macOS limitation: Complex UI doesn't render
- Result: Mode picker invisible

**Attempt #2** (Success):
- Custom `.sheet` with full SwiftUI control
- `PackageImportConfirmationView` with proper layout
- Radio-button style mode selection
- Visual feedback with icons and color coding

---

### Testing Resources

**Test Package Location**:
```
~/Desktop/SAAQ_Data/Vehicles/Package_Testing/SAAQData_Vehicle_10K_test.saaqpackage
```

**Database Location**:
```
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

**Console Monitoring**:
```bash
# Filter for package import messages
log stream --predicate 'subsystem == "com.endoquant.SAAQAnalyzer" AND category == "dataPackage"' --level debug

# Filter for cache messages
log stream --predicate 'subsystem == "com.endoquant.SAAQAnalyzer" AND category == "cache"' --level debug
```

---

## Summary

### What Was Fixed

1. ✅ **Temp package cleanup** - Added explicit cleanup after FileWrapper creation
2. ✅ **Cache invalidation** - Added `invalidateCache()` call before rebuild
3. ✅ **Confirmation dialog** - Custom sheet with mode picker displays properly
4. ✅ **Smart mode selection** - Automatic default based on database analysis
5. ✅ **Index typo** - Fixed `experience_global_id` index creation
6. ✅ **Legacy fallback** - Removed `geo_code` fallback in municipality query

### What Remains

1. ⚠️ **Testing required** - Verify fixes with larger datasets (100K, 1M, 10M+)
2. ⚠️ **Legacy schema handling** - No automatic migration (by design)
3. ⚠️ **Performance benchmarking** - Cache rebuild times for various sizes
4. 🔮 **Future decision** - Keep or remove legacy query code paths

### Critical Path Forward

1. Test with incrementally larger optimized-schema packages
2. Monitor cache rebuild performance at each scale
3. Verify both Replace and Merge modes work correctly
4. Decide on legacy code cleanup after thorough testing

---

## Success Criteria

- ✅ Import completes without errors
- ✅ Console shows "Rebuilding filter cache from imported database"
- ✅ Console shows "🗑️ Cleaned up temp staging area"
- ✅ FilterPanel updates immediately (no app relaunch)
- ✅ Filter dropdowns populated with correct data
- ✅ No "no such column" errors (schema compatibility)

---

*Session End: October 16, 2025*
*Status: Bug fixes complete, ready for systematic testing with larger datasets*
