# Data Package Regularization Systematic Testing - Session Handoff
**Date**: October 16, 2025
**Session**: Systematic testing protocol for data package export/import with regularization preservation

---

## 1. Current Task & Objective

### Primary Goal
Systematically test the data package export/import system to validate that regularization data (Make/Model mappings) is correctly preserved across package export/import cycles.

### Context
Following recent bug fixes for:
1. Package export temp cleanup (prevents 51GB duplicate files in container temp directory)
2. Cache invalidation during import (ensures filter cache rebuilds with imported data)

We need clean, reproducible evidence that the package system correctly preserves expensive regularization computations, avoiding the need to recompute ~125+ auto-regularization mappings on every import.

### Why This Matters
- **Regularization is expensive**: Auto-population analyzes curated years (2011-2022) to identify unambiguous Make/Model/Fuel/VehicleType combinations
- **User manual work is valuable**: Users extend auto-regularization with manual corrections for ambiguous cases
- **Packages must preserve both**: Auto-populated AND manually-corrected regularization data must survive export/import cycles
- **Performance critical**: Without preservation, every import would require minutes of recomputation + user re-entering manual corrections

---

## 2. Progress Completed ✅

### Phase 1: Clean Slate (COMPLETE)
**Actions Taken**:
- Deleted app container: `rm -rf ~/Library/Containers/com.endoquant.SAAQAnalyzer/`
- Deleted old test packages: `rm -f ~/Desktop/SAAQ_Data/Vehicles/Package_Testing/*.saaqpackage`
- Verified clean state

**Evidence**:
```
📄 New database detected - setting page_size to 32KB for optimal performance
✅ Database AGGRESSIVELY optimized for M3 Ultra: 8GB cache, 32GB mmap, 16 threads
🔧 Creating enumeration tables...
✅ Created 17 enumeration tables
```

### Phase 2: Fresh Database Import (COMPLETE)
**Actions Taken**:
- Imported 14 CSV files (2011-2024, 1000 records each = 14,000 total)
- CSV import completed in ~3 seconds
- App quit cleanly for database inspection

**Database State Verified**:
```
✅ Loaded regularization info for 0 Make/Model pairs
✅ Loaded 921 uncurated Make/Model pairs
✅ Filter cache initialized with enumeration data
✅ Using enumeration-based years (14 items) for vehicle
✅ Using enumeration-based regions (17 items)
✅ Using enumeration-based MRCs (104 items)
✅ Using enumeration-based municipalities (917 items)
```

**Key Findings**:
- Regularization table **exists** (no "no such table" error)
- Regularization table is **empty** (0 Make/Model pairs - expected for fresh import)
- 921 uncurated Make/Model pairs detected in 2023-2024 data
- Filter cache working correctly
- Database contains 14,000 vehicle records

---

## 3. Key Decisions & Patterns

### Architectural Understanding Corrected

**Regularization Auto-Population Logic** (3-Tier System):

**Tier 1: Complete Auto-Assignment (~125 pairs)**
- Exact string match: Uncurated Make/Model = Canonical Make/Model
- Unambiguous vehicle type: Only ONE type in canonical data
- Unambiguous fuel types: Each year has only ONE fuel type option
- **Action**: Auto-populate all fields, mark "Complete"
- **Example**: MAZDA/3 in 2023-2024 matches canonical 2011-2022 data with consistent AU (passenger car) + Gasoline for all years

**Tier 2: Partial Auto-Assignment (~230 pairs - "Needs Review")**
- Exact string match: Make/Model matches
- BUT: Multiple vehicle types OR multiple fuel types exist
- **Action**: Auto-populate what's unambiguous, flag for manual review
- **Example**: MAZDA/CX5 might be AU or CA depending on trim level

**Tier 3: Manual Assignment (~553 pairs - "Unassigned")**
- No string match (e.g., "VOLV0" ≠ "VOLVO")
- OR: Genuinely new model not in canonical data
- **Action**: Requires full manual intervention

### Regularization Table Structure
**Triplet-Based Design**:
- **Pairs**: Make/Model combinations with regularization rules (355 records in previous test)
- **Triplets**: Year-specific fuel type assignments (Make/Model/Year → Fuel Type) (1627 records in previous test)
- **Total mappings**: Pairs + Triplets = 1982 database records

**Example Structure**:
```
MAZDA/3 pair has:
- 1 Vehicle Type assignment: AU
- 19 year-specific fuel type assignments (2004-2022, each year = 1 triplet)
Total: 1 pair + 19 triplets = 20 database records
```

### Test Dataset Limitation Understanding
The 1K test dataset (14,000 total records):
- Has sparse data: ~71 records per year
- Limited overlap between curated (2011-2022) and uncurated (2023-2024) years
- **Cannot test auto-population with existing CSVs** (no regularization manager has been opened yet)
- **Must launch Regularization Manager** to trigger auto-analysis and mapping generation

### Bug Fixes Validated

**Bug #1: Package Export Temp Cleanup** ✅
- **Location**: `SAAQAnalyzerApp.swift:1258-1267`
- **Fix**: Explicit cleanup after FileWrapper creation
- **Impact**: Prevents accumulation of 51GB packages in container temp directory

**Bug #2: Cache Invalidation During Import** ✅
- **Location**: `DataPackageManager.swift:334-335`
- **Fix**: Call `invalidateCache()` before `initializeCache()`
- **Impact**: Filter cache rebuilds correctly from imported data

**Schema Fixes Applied** ✅
- Fixed index SQL typo: `experience_global_id` (was missing `_id` suffix)
- Removed legacy `geo_code` fallback in municipality query

---

## 4. Active Files & Locations

### Core Implementation Files

**`SAAQAnalyzer/DataLayer/DataPackageManager.swift`**
- Purpose: Package export/import operations
- Key functions:
  - `importDataPackage(from:mode:)` - Main entry point (line 256)
  - `importDatabaseReplace(from:timestamp:)` - Fast path (line 549)
  - `importDatabase(from:timestamp:content:)` - Merge path (line 585)
- Bug fix location: Lines 334-335 (cache invalidation)

**`SAAQAnalyzer/SAAQAnalyzerApp.swift`**
- Purpose: UI and user interaction for package operations
- Key sections:
  - Custom confirmation sheet (lines 335-351)
  - `PackageImportConfirmationView` (lines 2318-2458)
  - `ImportModeOption` helper view (lines 2461-2508)
  - Temp cleanup (lines 1258-1267)
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
- **Critical**: Must call `invalidateCache()` before re-initialization

**`SAAQAnalyzer/DataLayer/DatabaseManager.swift`**
- Purpose: Core database operations
- Key functions:
  - `createTablesIfNeeded()` - Creates schema on fresh database (line 773)
  - `reconnectDatabase()` - Reopens connection after import (line 747)
  - `getDatabaseStats()` - Used for smart mode selection
- Bug fixes:
  - Fixed index SQL for `experience_global_id` (line 904)
  - Removed legacy `geo_code` fallback (lines 4284-4293)

**`SAAQAnalyzer/DataLayer/RegularizationManager.swift`**
- Purpose: Manages Make/Model regularization auto-population and manual editing
- Key operations:
  - Analyzes curated years (2011-2022) to build canonical hierarchy
  - Identifies unambiguous combinations for auto-assignment
  - Populates `make_model_regularization` table
  - Uses canonical hierarchy cache (0.12s vs 13.4s without cache - 109x improvement)

**`SAAQAnalyzer/UI/FilterPanel.swift`**
- Purpose: Left panel with filter controls
- Key observation:
  - Already observes `dataVersion` changes (lines 289-292, 314-316)
  - Automatically reloads filter options when `dataVersion` increments

### Test Data Locations

**Vehicle Test Data** (existing):
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_1K` - 1K records/year ✅ (Used in Phase 2)
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_10K` - 10K records/year
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_100K` - 100K records/year
- `~/Desktop/SAAQ_Data/Vehicle_Registration_Test_1M` - 1M records/year

**Current Database**:
- Path: `~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite`
- State: Contains 14,000 vehicle records (1000/year × 14 years)
- Regularization: Table exists but empty (no mappings generated yet)
- App: Currently quit (database unlocked for inspection)

**Test Package Directory**:
- `~/Desktop/SAAQ_Data/Vehicles/Package_Testing/` (currently empty)

---

## 5. Current State

### Completed Steps
1. ✅ **Clean slate established**: All containers and old packages deleted
2. ✅ **Fresh database created**: 14,000 vehicle records imported from 1K CSV dataset
3. ✅ **Database state verified**: Regularization table exists but empty (expected)
4. ✅ **App cleanly quit**: Database unlocked for inspection

### Current Database State
```sql
-- Vehicles table
SELECT COUNT(*) FROM vehicles;
-- Result: 14000

-- Regularization table (empty - no auto-population yet)
SELECT COUNT(*) FROM make_model_regularization;
-- Result: 0

-- Enumeration tables populated
SELECT COUNT(*) FROM year_enum;        -- 14 items
SELECT COUNT(*) FROM make_enum;        -- ~197 items
SELECT COUNT(*) FROM model_enum;       -- ~2000+ items
SELECT COUNT(*) FROM admin_region_enum; -- 17 items
SELECT COUNT(*) FROM mrc_enum;         -- 104 items
SELECT COUNT(*) FROM municipality_enum; -- 917 items
```

### Uncurated Data Available
- 921 uncurated Make/Model pairs in 2023-2024 data
- These are candidates for auto-regularization when Regularization Manager is opened

---

## 6. Next Steps (Priority Order)

### IMMEDIATE: Phase 3 - Generate Regularization Mappings

**Prerequisites**: Database is ready (Phase 2 complete)

**Actions**:
1. **Launch SAAQAnalyzer app**
2. **Open Regularization Manager** (Settings → Regularization)
3. **Wait for auto-analysis** to complete (should be fast with 1K dataset)
4. **Record console output** showing:
   - Number of Complete auto-regularizations
   - Number of Partial auto-regularizations
   - Number of Unassigned pairs
   - Total mapping count (pairs + triplets)

**Expected Console Output**:
```
Loaded [N] mappings ([X] pairs, [Y] triplets)
Generated base canonical hierarchy: [M] makes, [P] models in 0.0XXs
Found [Z] exact matches for auto-regularization
Detailed regularization statistics: Mappings=[N], Total=[T], Make/Model=X.X%, FuelType=Y.Y%, VehicleType=Z.Z%
```

**Expected Results** (based on earlier tests with similar dataset):
- ~125 Complete pairs (MAZDA/3, KIA/FORTE, TOYOTA/COROLLA, etc.)
- ~230 Needs Review pairs
- ~553 Unassigned pairs
- Total: ~908 uncurated pairs analyzed
- Mappings: ~355 pairs + ~1627 triplets = ~1982 total database records

**Verification Commands** (run after auto-population):
```bash
# Verify regularization table is populated
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite <<EOF
-- Total mappings count
SELECT COUNT(*) as total_mappings FROM make_model_regularization;

-- Breakdown by structure
SELECT
    COUNT(DISTINCT make_id || '_' || model_id) as unique_pairs,
    COUNT(*) as total_records
FROM make_model_regularization;

-- Sample first 5 mappings
SELECT * FROM make_model_regularization LIMIT 5;
EOF
```

### Phase 4: Export Data Package with Regularization

**Actions**:
1. **File → Export Data Package**
2. **Save as**: `~/Desktop/SAAQ_Data/Vehicles/Package_Testing/SAAQData_1K_Fresh_With_Regularization.saaqpackage`
3. **Monitor console** for cleanup message: `🗑️  Cleaned up temp staging area`

**Verification**:
```bash
# Check package was created
ls -lh ~/Desktop/SAAQ_Data/Vehicles/Package_Testing/SAAQData_1K_Fresh_With_Regularization.saaqpackage

# Verify package contains regularization data
cd ~/Desktop/SAAQ_Data/Vehicles/Package_Testing/
mkdir -p temp_extract && cd temp_extract
cp ../SAAQData_1K_Fresh_With_Regularization.saaqpackage ./test.zip
unzip -q test.zip

# Check regularization count in package
sqlite3 saaq_data.sqlite "SELECT COUNT(*) as mappings_in_package FROM make_model_regularization;"

# Should match Phase 3 count!

# Clean up
cd .. && rm -rf temp_extract
```

### Phase 5: Clean Import Test

**Actions**:
1. **Quit app** (Cmd+Q)
2. **Delete container**: `rm -rf ~/Library/Containers/com.endoquant.SAAQAnalyzer/`
3. **Launch app** (fresh container, empty database)
4. **File → Import Data Package**
5. **Select**: `SAAQData_1K_Fresh_With_Regularization.saaqpackage`
6. **Mode**: Replace (should be auto-selected for empty database)

**Watch Console During Import**:
```
Using REPLACE mode (fast path)
Database replaced successfully (fast path)
Rebuilding filter cache from imported database
🔄 Loading filter cache from enumeration tables...
✅ Loaded regularization info for [N] Make/Model pairs  ← Should match Phase 3
✅ Loaded 921 uncurated Make/Model pairs
✅ Filter cache initialized with enumeration data
UI refresh triggered (dataVersion: 1)
```

**Critical Success Indicator**:
```
✅ Loaded regularization info for [N] Make/Model pairs
```
Where `N` should match the count from Phase 3 (NOT zero!)

### Phase 6: Post-Import Verification

**Verification Commands**:
```bash
# Check imported database
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite <<EOF
-- Vehicle count should match original
SELECT COUNT(*) as total_vehicles FROM vehicles;
-- Expected: 14000

-- Regularization mappings should match Phase 3
SELECT COUNT(*) as total_mappings FROM make_model_regularization;
-- Expected: Same as Phase 3 (~1982)

-- Breakdown should match Phase 3
SELECT
    COUNT(DISTINCT make_id || '_' || model_id) as unique_pairs,
    COUNT(*) as total_records
FROM make_model_regularization;
-- Expected: ~355 pairs, ~1982 total
EOF
```

**UI Verification**:
1. **Open Regularization Manager**
2. **Verify counts match Phase 3**:
   - Complete: ~125 pairs
   - Needs Review: ~230 pairs
   - Unassigned: ~553 pairs
3. **Console should show**: `Loaded [N] mappings ([X] pairs, [Y] triplets)` (not "Generating...")

### Phase 7: Success Criteria & Documentation

**Test PASSES if**:
✅ Phase 3 auto-regularization count = Phase 6 imported mapping count
✅ Phase 4 package extraction count = Phase 3 database count
✅ Phase 6 Regularization Manager UI shows same Complete/Partial/Unassigned counts as Phase 3
✅ No recomputation triggered after import (console shows "Loaded" not "Generating")
✅ Filter cache rebuilds correctly (14 years, 17 regions, etc.)
✅ Temp package cleanup message appears during export

**Test FAILS if**:
❌ Phase 6 shows fewer mappings than Phase 3 (data loss)
❌ Phase 6 triggers recomputation (expensive operation not avoided)
❌ Phase 6 regularization counts don't match Phase 3 (incomplete restoration)

**Documentation**:
- Create comprehensive test results document
- Record all verification checkpoint numbers
- Include console output excerpts
- Determine success/failure
- Document any discrepancies

---

## 7. Important Context & Gotchas

### Console Log Interpretation

**Expected Success Pattern**:
```
# At app launch (fresh database)
⚠️ Could not load regularization info: queryFailed("Failed to get regularization display info: no such table: make_model_regularization")
✅ Loaded 0 uncurated Make/Model pairs

# After auto-population (Phase 3)
✅ Loaded regularization info for [N] Make/Model pairs
✅ Loaded 921 uncurated Make/Model pairs

# After import (Phase 6) - SUCCESS
✅ Loaded regularization info for [N] Make/Model pairs  ← Same N as Phase 3
No exact matches found for auto-regularization  ← Expected: already complete
```

**Failure Pattern to Watch For**:
```
# After import (Phase 6) - FAILURE
⚠️ Could not load regularization info: queryFailed(...)  ← Table missing
# OR
✅ Loaded regularization info for 0 Make/Model pairs  ← Data lost
```

### Regularization Manager Console Messages

**When opening Regularization Manager**:
```
Detailed regularization statistics: Mappings=[N], Total=[T], Make/Model=X.X%, FuelType=Y.Y%, VehicleType=Z.Z%
Updated regularization year configuration: Curated=2011–2022 (12 years), Uncurated=2023–2024 (2 years)
Loaded [N] mappings ([X] pairs, [Y] triplets)
Finding uncurated Make/Model pairs in 2 uncurated years: [2023, 2024]
Found [Z] uncurated Make/Model pairs
Generating canonical hierarchy from 12 curated years: [2011-2022]
Generated base canonical hierarchy: [M] makes, [P] models in 0.0XXs
```

**Key Messages**:
- `"No exact matches found for auto-regularization"` - Expected after import (all mappings already exist)
- `"Found [Z] exact matches for auto-regularization"` - Expected during fresh auto-population

### Database Schema Notes

**Regularization Table**:
```sql
CREATE TABLE make_model_regularization (
    make_id INTEGER,
    model_id INTEGER,
    canonical_make_id INTEGER,
    canonical_model_id INTEGER,
    canonical_vehicle_type_id INTEGER,
    canonical_fuel_type_id INTEGER,
    model_year INTEGER,
    -- ... additional fields
)
```

**Critical Indexes** (for performance):
```sql
CREATE INDEX idx_make_model_reg_make_model ON make_model_regularization(make_id, model_id);
CREATE INDEX idx_make_model_reg_year ON make_model_regularization(model_year);
```

### Filter Cache Architecture

**FilterCacheManager Lifecycle**:
1. Created during `DatabaseManager` initialization (DatabaseManager.swift:306)
2. First access triggers `initializeCache()` → loads from enumeration tables
3. Sets `isInitialized = true` flag
4. Subsequent calls return early due to guard (line 56)
5. **Must call `invalidateCache()`** before re-initialization

**Cache Data Sources** (from enumeration tables):
- Year options: `year_enum`
- Make/Model: `make_enum`, `model_enum`
- Geographic: `admin_region_enum`, `mrc_enum`, `municipality_enum`
- Vehicle: `vehicle_class_enum`, `vehicle_type_enum`
- Fuel: `fuel_type_enum`
- License: `age_group_enum`, `gender_enum`, `license_type_enum`

**Cache Invalidation Triggers**:
- ✅ Package import (fixed in this session - DataPackageManager.swift:334)
- ✅ CSV import (already working)
- ⚠️ Manual invalidation via Settings (not yet implemented)

### Import Mode Logic

**Smart Default Selection** (`SAAQAnalyzerApp.swift:223-257`):
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

### Disk Space Requirements

**For Replace Operations**:
- Simply overwrites existing database file
- **Required space**: Size of package being imported

**For Merge Operations**:
- Needs temporary copy of source database
- Temporary copy deleted after merge completes
- **Required space**: ~2x largest database size

**Example** (production):
- Vehicle database: 35GB
- License database: 16GB
- Merge operation: Needs ~70GB free (2x × 35GB)

### Performance Expectations

**Cache Rebuild Time** (after import):
| Dataset Size | Records | Expected Cache Rebuild Time |
|--------------|---------|----------------------------|
| Small        | 14K     | < 1 second                 |
| Medium       | 140K    | 1-5 seconds                |
| Large        | 1.4M    | 10-30 seconds              |
| Very Large   | 14M+    | 1-2 minutes                |

**Regularization Auto-Population Time**:
| Dataset Size | Canonical Models | Auto-Population Time |
|--------------|------------------|---------------------|
| Small        | ~1500            | 0.02s (with cache)  |
| Medium       | ~5000            | 0.05s (with cache)  |
| Large        | ~12000           | 0.12s (with cache)  |
| Without cache| ~12000           | 13.4s (109x slower) |

### Temp Cleanup Verification

**During package export**, watch for console message:
```
🗑️  Cleaned up temp staging area: SAAQData_timestamp.saaqpackage
```

**If missing**, check:
```bash
# Inspect container temp directory for accumulation
ls -lh ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/tmp/
du -sh ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/tmp/
```

**Expected**: Empty or minimal (< 1 MB)

### Legacy Schema Considerations

**Not Applicable** - All tests use optimized schema:
- Integer foreign keys for Make/Model/Fuel/VehicleType
- 17 enumeration tables with indexes
- No legacy string columns (`geo_code`, `class`, `mrc`)

**Migration Status**:
- ❌ None implemented
- ❌ None planned
- ✅ Fresh databases always get optimized schema

---

## 8. Test Execution Checklist

Use this checklist to track progress through the systematic test:

### Pre-Test Setup
- [x] Clean slate: Deleted all containers and old packages
- [x] Fresh database: Imported 14,000 vehicle records from 1K CSV dataset
- [x] Verified: Regularization table exists but empty
- [x] App quit: Database unlocked for inspection

### Phase 3: Generate Regularization
- [ ] Launch app
- [ ] Open Regularization Manager
- [ ] Record console output (mappings generated)
- [ ] Record UI counts (Complete/Partial/Unassigned)
- [ ] Verify database with SQL query
- [ ] **Record numbers**: Total mappings = _____, Pairs = _____, Triplets = _____

### Phase 4: Export Package
- [ ] Export data package to test directory
- [ ] Verify temp cleanup console message
- [ ] Extract and verify package contents
- [ ] **Verify**: Package mapping count matches Phase 3

### Phase 5: Clean Import
- [ ] Quit app
- [ ] Delete container
- [ ] Launch app (fresh container)
- [ ] Import package (Replace mode)
- [ ] Watch console for cache rebuild messages

### Phase 6: Verify Import
- [ ] Check console: "Loaded regularization info for [N] pairs"
- [ ] **Verify**: N matches Phase 3 count
- [ ] Run SQL verification queries
- [ ] Open Regularization Manager
- [ ] **Verify**: UI counts match Phase 3

### Phase 7: Document Results
- [ ] Test PASSES or FAILS determination
- [ ] Record all checkpoint numbers
- [ ] Save console output excerpts
- [ ] Create test results document

---

## 9. Quick Reference Commands

### Database Inspection
```bash
# Current state check
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite <<EOF
SELECT COUNT(*) as vehicles FROM vehicles;
SELECT COUNT(*) as reg_mappings FROM make_model_regularization;
SELECT COUNT(DISTINCT make_id || '_' || model_id) as pairs FROM make_model_regularization;
EOF
```

### Package Verification
```bash
# Extract and inspect package
cd ~/Desktop/SAAQ_Data/Vehicles/Package_Testing/
mkdir -p temp_extract && cd temp_extract
cp ../*.saaqpackage ./test.zip
unzip -q test.zip
sqlite3 saaq_data.sqlite "SELECT COUNT(*) FROM make_model_regularization;"
cd .. && rm -rf temp_extract
```

### Temp Directory Monitoring
```bash
# Watch temp directory during export
watch -n 1 'ls -lh ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/tmp/ | tail -20'

# Check temp directory size after export
du -sh ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/tmp/
```

### Console Log Filtering
```bash
# Filter for package-related messages
log stream --predicate 'subsystem == "com.endoquant.SAAQAnalyzer" AND category == "dataPackage"' --level debug

# Filter for cache messages
log stream --predicate 'subsystem == "com.endoquant.SAAQAnalyzer" AND category == "cache"' --level debug

# Filter for regularization messages
log stream --predicate 'subsystem == "com.endoquant.SAAQAnalyzer" AND category == "regularization"' --level debug
```

---

## 10. Related Documentation

**Previous Session Notes**:
- `2025-10-16-Package-Export-Import-Fixes-Complete.md` - Bug fixes that enabled this test
- `2025-10-16-Data-Package-Import-Modes-Implementation.md` - Replace/Merge mode implementation
- `2025-10-16-Data-Package-Import-Cache-Rebuild-Fix.md` - Cache invalidation fix

**Relevant CLAUDE.md Sections**:
- "Data Import Process" - CSV preprocessing and validation
- "Regularization System Architecture" - How auto-population works
- "Filter Cache Architecture" - Cache invalidation patterns
- "Data Package Export/Import System" - Package format and operations

---

## Summary

The systematic test protocol is ready to execute from **Phase 3: Generate Regularization Mappings**.

**Current State**: Fresh database with 14,000 vehicle records, empty regularization table, app quit

**Next Action**: Launch app → Open Regularization Manager → Record auto-population results

**Critical Validation**: Regularization mapping count must survive the export/import cycle without data loss or unnecessary recomputation.

**Success Metric**: Phase 6 imported mappings = Phase 3 generated mappings (with "Loaded" not "Generating" in console)

---

*Session End: October 16, 2025*
*Status: Phase 2 complete, ready for Phase 3 execution*
*Database: Fresh with 14K records, regularization table empty (awaiting auto-population)*
