# License Filter Experience Level Enumeration Implementation

**Date**: October 15, 2025
**Session Focus**: Converting experience levels from TEXT to integer enumeration architecture
**Status**: 🔴 **INCOMPLETE** - Code complete, but UI not showing filters and license class filter still broken
**Branch**: `rhoge-dev`
**Context Used**: 82% (164k/200k tokens)

---

## 1. Current Task & Objective

### Overall Goal
Fix critical bugs in license data filtering where two filter types are completely non-functional:
1. **Experience Levels filter**: Not appearing in UI at all
2. **License Classes filter**: Appearing in UI but has no effect on query results (all records returned regardless of selection)

### Root Cause Identified
Both filters violate the integer enumeration architecture that the rest of the system uses:
- **Experience Levels**: Stored as TEXT in 4 columns, attempted string binding in queries
- **License Classes**: Uses boolean INTEGER columns (correct storage), but missing query logic in OptimizedQueryManager

### Architectural Decision
Instead of workaround fixes, implement proper integer enumeration for experience levels:
- Create `experience_level_enum` table
- Convert 4 TEXT columns to 4 INTEGER foreign key columns in `licenses` table
- Update CSV import to populate enum table
- Update query system to use integer foreign keys
- Fix license class query logic (separate issue, still pending)

---

## 2. Progress Completed

### ✅ **Database Schema (DatabaseManager.swift)**

**Lines 1011**: Created `experience_level_enum` table
```swift
"CREATE TABLE IF NOT EXISTS experience_level_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, level_text TEXT UNIQUE NOT NULL);"
```

**Lines 829-838**: Replaced TEXT columns with INTEGER foreign keys in `licenses` table
```swift
// OLD (removed):
experience_1234 TEXT,
experience_5 TEXT,
experience_6abce TEXT,
experience_global TEXT,

// NEW:
experience_1234_id INTEGER,
experience_5_id INTEGER,
experience_6abce_id INTEGER,
experience_global_id INTEGER,
```

### ✅ **CSV Import (DatabaseManager.swift:4981-5242)**

**Line 4988**: Updated INSERT SQL statement
```swift
INSERT OR REPLACE INTO licenses (
    year, license_sequence,
    has_learner_permit_123, has_learner_permit_5, has_learner_permit_6a6r,
    has_driver_license_1234, has_driver_license_5, has_driver_license_6abce,
    has_driver_license_6d, has_driver_license_8, is_probationary,
    year_id, age_group_id, gender_id, admin_region_id, mrc_id, license_type_id,
    experience_1234_id, experience_5_id, experience_6abce_id, experience_global_id
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
```

**Line 5020**: Added experience level cache
```swift
var experienceLevelEnumCache: [String: Int] = [:]
```

**Line 5056**: Added cache loading
```swift
loadEnumCache(table: "experience_level_enum", keyColumn: "level_text", cache: &experienceLevelEnumCache)
```

**Lines 5220-5242**: Updated binding logic to use enum IDs
```swift
// experience_1234_id
if let exp = record["EXPERIENCE_1234"], !exp.isEmpty,
   let expId = getOrCreateEnumId(table: "experience_level_enum", column: "level_text", value: exp, cache: &experienceLevelEnumCache) {
    sqlite3_bind_int(stmt, 18, Int32(expId))
} else { sqlite3_bind_null(stmt, 18) }

// experience_5_id
if let exp = record["EXPERIENCE_5"], !exp.isEmpty,
   let expId = getOrCreateEnumId(table: "experience_level_enum", column: "level_text", value: exp, cache: &experienceLevelEnumCache) {
    sqlite3_bind_int(stmt, 19, Int32(expId))
} else { sqlite3_bind_null(stmt, 19) }

// experience_6abce_id
if let exp = record["EXPERIENCE_6ABCE"], !exp.isEmpty,
   let expId = getOrCreateEnumId(table: "experience_level_enum", column: "level_text", value: exp, cache: &experienceLevelEnumCache) {
    sqlite3_bind_int(stmt, 20, Int32(expId))
} else { sqlite3_bind_null(stmt, 20) }

// experience_global_id
if let exp = record["EXPERIENCE_GLOBALE"], !exp.isEmpty,
   let expId = getOrCreateEnumId(table: "experience_level_enum", column: "level_text", value: exp, cache: &experienceLevelEnumCache) {
    sqlite3_bind_int(stmt, 21, Int32(expId))
} else { sqlite3_bind_null(stmt, 21) }
```

### ✅ **Filter Cache (FilterCacheManager.swift)**

**Line 24**: Added cache storage
```swift
private var cachedExperienceLevels: [FilterItem] = []
```

**Line 87**: Added to initialization
```swift
try await loadExperienceLevels()
```

**Lines 455-458**: Added loader function
```swift
private func loadExperienceLevels() async throws {
    let sql = "SELECT id, level_text FROM experience_level_enum ORDER BY level_text;"
    cachedExperienceLevels = try await executeFilterItemQuery(sql)
}
```

**Lines 565-568**: Added public accessor
```swift
func getAvailableExperienceLevels() async throws -> [FilterItem] {
    if !isInitialized { try await initializeCache() }
    return cachedExperienceLevels
}
```

**Line 650**: Added to cache invalidation
```swift
cachedExperienceLevels.removeAll()
```

### ✅ **Optimized Query System (OptimizedQueryManager.swift)**

**Line 21**: Added to struct
```swift
struct OptimizedFilterIds: Sendable {
    // ... other fields ...
    let experienceLevelIds: [Int]
}
```

**Line 99**: Added variable declaration
```swift
var experienceLevelIds: [Int] = []
```

**Lines 286-290**: Added filter conversion
```swift
for experienceLevel in filters.experienceLevels {
    if let id = try await enumManager.getEnumId(table: "experience_level_enum", column: "level_text", value: experienceLevel) {
        experienceLevelIds.append(id)
    }
}
```

**Line 311**: Added to debug output
```swift
print("   Experience Levels: \(experienceLevelIds.count) -> \(experienceLevelIds)")
```

**Line 329**: Added to struct instantiation
```swift
return OptimizedFilterIds(
    // ... other fields ...
    experienceLevelIds: experienceLevelIds
)
```

**Lines 844-857**: Added query filter logic
```swift
// Experience level filter - check ALL 4 experience columns (one per license class)
// A person can have different experience levels for different license classes
if !filterIds.experienceLevelIds.isEmpty {
    let placeholders = Array(repeating: "?", count: filterIds.experienceLevelIds.count).joined(separator: ",")
    // Match if ANY of the 4 experience columns contains one of the selected experience levels
    whereClause += " AND (experience_1234_id IN (\(placeholders)) OR experience_5_id IN (\(placeholders)) OR experience_6abce_id IN (\(placeholders)) OR experience_global_id IN (\(placeholders)))"
    // Bind the same IDs 4 times (once for each column)
    for _ in 0..<4 {
        for id in filterIds.experienceLevelIds {
            bindValues.append((bindIndex, id))
            bindIndex += 1
        }
    }
}
```

---

## 3. Key Decisions & Patterns

### Architectural Pattern: Integer Enumeration
**Decision**: All categorical data uses integer foreign keys, never TEXT comparison in queries.

**Pattern**:
1. Create `{field}_enum` table with `id` and value columns
2. Store foreign key IDs in data tables
3. Populate enum tables during CSV import (on-demand via `getOrCreateEnumId()`)
4. Cache enum mappings in FilterCacheManager
5. Convert filter strings to IDs in OptimizedQueryManager
6. Use integer IN clauses in SQL queries

**Rationale**:
- 5.6x faster queries (measured)
- Smaller database size
- Consistent architecture throughout system
- Type safety and referential integrity

### Experience Levels: Multi-Column Design
**Decision**: Use 4 separate foreign key columns instead of a single column.

**Columns**:
- `experience_1234_id` - Experience for classes 1-2-3-4
- `experience_5_id` - Experience for class 5
- `experience_6abce_id` - Experience for classes 6A-6B-6C-6E
- `experience_global_id` - Global experience level

**Rationale**: A person can have different experience levels for different license classes. The SAAQ data provides this granularity, so we preserve it.

**Query Pattern**: Use OR logic across all 4 columns:
```sql
WHERE (experience_1234_id IN (...) OR experience_5_id IN (...) OR experience_6abce_id IN (...) OR experience_global_id IN (...))
```

### License Classes: Boolean Columns (NOT Enumerated)
**Decision**: License classes use INTEGER boolean flags, not enumeration.

**Columns**:
```swift
has_learner_permit_123 INTEGER NOT NULL DEFAULT 0,
has_learner_permit_5 INTEGER NOT NULL DEFAULT 0,
has_learner_permit_6a6r INTEGER NOT NULL DEFAULT 0,
has_driver_license_1234 INTEGER NOT NULL DEFAULT 0,
has_driver_license_5 INTEGER NOT NULL DEFAULT 0,
has_driver_license_6abce INTEGER NOT NULL DEFAULT 0,
has_driver_license_6d INTEGER NOT NULL DEFAULT 0,
has_driver_license_8 INTEGER NOT NULL DEFAULT 0,
is_probationary INTEGER NOT NULL DEFAULT 0,
```

**Rationale**: A person can hold multiple license classes simultaneously (e.g., Class 5 AND Class 6A). Boolean flags are the correct storage pattern for this.

**Query Pattern**: Should use OR logic across boolean columns:
```sql
WHERE (has_driver_license_1234 = 1 OR has_driver_license_5 = 1 OR ...)
```

**Helper Function**: `DatabaseManager.getDatabaseColumn(for:)` maps filter display names to column names.

---

## 4. Active Files & Locations

### Primary Files Modified

**DatabaseManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/DatabaseManager.swift`)
- Line 1011: experience_level_enum table creation
- Lines 829-838: licenses table schema (foreign key columns)
- Lines 4981-5242: importLicenseBatch() - CSV import with enum population
- Lines 3649-3666: License class mapping helper (getDatabaseColumn)

**FilterCacheManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/FilterCacheManager.swift`)
- Lines 24, 87, 455-458, 565-568, 650: Experience level cache infrastructure

**OptimizedQueryManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/OptimizedQueryManager.swift`)
- Lines 21, 99: Struct and variable declarations
- Lines 286-290, 311, 329: Filter conversion logic
- Lines 844-857: Query WHERE clause logic

### Reference Files (Not Modified)

**DataModels.swift** - Contains FilterConfiguration struct with `experienceLevels` and `licenseClasses` properties

**FilterPanel.swift** - UI code that calls DatabaseManager query functions (lines 469-473)

---

## 5. Current State

### ✅ Code Complete
All backend code has been written and compiles successfully:
- Database schema updated
- CSV import logic updated
- Filter cache infrastructure updated
- Query conversion and execution updated

### ❌ UI Issues (Critical)

**Issue #1: Experience Levels Not Appearing in FilterPanel**
- **Symptom**: No experience level filter section visible in the UI
- **Root Cause**: FilterPanel.swift likely missing UI code to display the filter
- **Expected**: Should appear in license-specific filter section, similar to age groups/genders
- **Location**: FilterPanel.swift needs investigation (license-specific section)

**Issue #2: License Classes Filter Not Working**
- **Symptom**: Filter appears in UI but has no effect on query results
- **Root Cause**: Missing query logic in OptimizedQueryManager (lines 844-857 handle experience levels, but license classes were skipped)
- **Expected**: Should filter WHERE clause like: `WHERE (l.has_driver_license_5 = 1 OR ...)`
- **Location**: OptimizedQueryManager.swift:844 area (insert AFTER experience level filter, BEFORE query construction)

### 🔄 Database State
**Current**: Database still has old schema (TEXT columns)
**Required**: Delete database and re-import to create new schema with integer foreign keys

**Database Location**:
```
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

---

## 6. Next Steps (Priority Order)

### CRITICAL: Fix UI Issues

**Step 1: Add Experience Level Filter to FilterPanel.swift**
- Search for license-specific filter section (near age groups/genders)
- Add experience level picker using same pattern
- Bind to `filters.experienceLevels` property
- Load options from `filterCacheManager.getAvailableExperienceLevels()`

**Step 2: Add License Class Query Logic to OptimizedQueryManager.swift**
- Location: After line 857 (after experience level filter), before line 859 (query construction)
- Pattern to follow (from DatabaseManager.swift:1666-1682):
```swift
// License class filter using boolean columns (has_driver_license_*)
if !filters.licenseClasses.isEmpty {
    var classConditions: [String] = []

    for licenseClass in filters.licenseClasses {
        if let column = self.databaseManager?.getDatabaseColumn(for: licenseClass) {
            classConditions.append("l.\(column) = 1")
        } else {
            print("⚠️ Warning: Unmapped license class filter '\(licenseClass)'")
        }
    }

    if !classConditions.isEmpty {
        whereClause += " AND (\(classConditions.joined(separator: " OR ")))"
    }
}
```
- **Important**: No parameter binding needed (direct column checks), table alias is `l`

### Step 3: Test with Fresh Database

**Delete existing database**:
```bash
rm ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite*
```

**Re-import license CSV files**:
- Use the app's import UI
- Import all 12 years (2011-2022)
- Verify `experience_level_enum` table is populated
- Verify licenses table has integer foreign keys (not TEXT)

**Verify database schema**:
```sql
-- Check enum table
SELECT COUNT(*) FROM experience_level_enum;
SELECT * FROM experience_level_enum LIMIT 10;

-- Check licenses table has foreign keys
PRAGMA table_info(licenses);
-- Should show: experience_1234_id, experience_5_id, etc. (INTEGER)

-- Test query
SELECT COUNT(*), e.level_text
FROM licenses l
JOIN experience_level_enum e ON l.experience_global_id = e.id
GROUP BY e.level_text;
```

### Step 4: Test Filters in UI

**Experience Level Filter**:
1. Switch to license data type
2. Select one experience level (e.g., "1-5 years")
3. Run query
4. **Expected**: Record count < 12,000 (total records)
5. **Expected**: Console shows experience level IDs in bind values

**License Class Filter**:
1. Switch to license data type
2. Select one license class (e.g., "Class 5")
3. Run query
4. **Expected**: Record count < 12,000
5. **Expected**: Console shows WHERE clause with `has_driver_license_5 = 1`

### Step 5: Commit Changes

**Suggested commit message**:
```
feat: Implement integer enumeration for experience levels

Converted experience levels from TEXT storage to proper integer
enumeration architecture, consistent with rest of system:

- Created experience_level_enum table
- Replaced 4 TEXT columns with 4 INTEGER foreign key columns in licenses table
- Updated CSV import to populate enum table and bind integer IDs
- Added FilterCacheManager support for experience level loading
- Added OptimizedQueryManager filter conversion and query logic
- Fixed license class filter query logic (was missing from OptimizedQueryManager)

BREAKING CHANGE: Database schema changed. Delete existing database
and re-import license CSV files.

Architecture: Uses 4 separate foreign key columns (experience_1234_id,
experience_5_id, experience_6abce_id, experience_global_id) because
a person can have different experience levels for different license classes.
Query uses OR logic across all 4 columns.

License classes remain as boolean INTEGER columns (correct pattern for
multi-valued flags).

Files changed:
- DatabaseManager.swift (schema + import)
- FilterCacheManager.swift (cache infrastructure)
- OptimizedQueryManager.swift (query logic)
- FilterPanel.swift (UI - pending verification)
```

---

## 7. Important Context

### Issues Discovered & Resolved

**Build Error #1: Missing Variable Declaration**
- **Error**: `Cannot find 'experienceLevelIds' in scope`
- **Location**: OptimizedQueryManager.swift:288, 311, 329
- **Fix**: Added `var experienceLevelIds: [Int] = []` on line 99
- **Root Cause**: Forgot to declare variable in `convertFiltersToIds()` function

### Architecture Violations Found

**Original Bug Root Cause**:
The session started with experience levels being ignored in queries. Investigation revealed they were stored as TEXT and attempted to be bound as strings in queries. This violates the integer enumeration architecture used throughout the system.

**Why String Binding Won't Work**:
The optimized query path binds values like this:
```swift
for (index, value) in bindValues {
    if let intValue = value as? Int {
        sqlite3_bind_int(stmt, index, Int32(intValue))
    }
    // No else clause - strings just don't bind!
}
```

If you try to bind strings, they silently fail (no error, just no filtering).

### Design Patterns Established

**On-Demand Enum Population**:
The `getOrCreateEnumId()` helper function used during CSV import:
1. Checks cache for existing ID
2. If not found, INSERTs into enum table
3. SELECTs the ID back
4. Updates cache for next iteration

This pattern allows enum tables to grow organically as new values appear in CSV data.

**Multi-Column Boolean vs Single Enum**:
- Use **multiple boolean columns** when a record can have multiple simultaneous values (license classes, flags)
- Use **single enum foreign key** when a record has exactly one value (gender, age group, license type)
- Use **multiple enum foreign keys** when a record has distinct values for different contexts (experience levels per license class)

### Database Location & Management

**Sandbox Path**:
```
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

**Quick Inspection**:
```bash
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite

# Check schema
.schema licenses
.schema experience_level_enum

# Check data
SELECT COUNT(*) FROM licenses;
SELECT COUNT(*) FROM experience_level_enum;

# Test join
SELECT COUNT(*), e.level_text
FROM licenses l
LEFT JOIN experience_level_enum e ON l.experience_global_id = e.id
GROUP BY e.level_text;
```

### UI Integration Points

**FilterPanel.swift Expected Pattern**:
License-specific filters likely around lines 469-473 (mentioned in context). Should follow pattern:
```swift
// Age Groups (working example)
Section("Age Groups") {
    Picker("Age Groups", selection: $filters.ageGroups) {
        // ...
    }
}

// Experience Levels (MISSING - needs to be added)
Section("Experience Levels") {
    Picker("Experience Levels", selection: $filters.experienceLevels) {
        ForEach(experienceLevelOptions, id: \.self) { level in
            Text(level)
        }
    }
}
```

Load options in `onAppear` or similar:
```swift
experienceLevelOptions = try await filterCacheManager.getAvailableExperienceLevels()
    .map { $0.displayName }
```

### Helper Functions Reference

**DatabaseManager.getDatabaseColumn(for:)** (line 3664-3666):
```swift
private func getDatabaseColumn(for displayName: String) -> String? {
    return getLicenseClassMapping().first { $0.displayName == displayName }?.column
}
```

**License class mapping** (line 3649-3660):
```swift
[
    ("has_driver_license_1234", "1-2-3-4"),
    ("has_driver_license_5", "5"),
    ("has_driver_license_6abce", "6A-6B-6C-6E"),
    ("has_driver_license_6d", "6D"),
    ("has_driver_license_8", "8"),
    ("has_learner_permit_123", "Learner 1-2-3"),
    ("has_learner_permit_5", "Learner 5"),
    ("has_learner_permit_6a6r", "Learner 6A-6R"),
    ("is_probationary", "Probationary")
]
```

### Console Debug Output

**When working correctly, you should see**:
```
🔍 Filter ID conversion summary:
   Experience Levels: 1 -> [3]

🔍 Optimized license query: SELECT y.year, COUNT(*) as value FROM licenses l JOIN year_enum y ON l.year_id = y.id WHERE 1=1 AND (experience_1234_id IN (?) OR experience_5_id IN (?) OR experience_6abce_id IN (?) OR experience_global_id IN (?)) GROUP BY l.year_id, y.year ORDER BY y.year

🔍 Bind values: (1, 3), (2, 3), (3, 3), (4, 3)
```

Notice: Same ID (3) bound 4 times, once for each experience column.

---

## 8. Known Issues Still Pending

### Issue #1: Experience Level Filter Not Appearing in UI
- **Status**: Backend complete, UI code missing
- **Impact**: User cannot select experience levels
- **Files to check**: FilterPanel.swift
- **Fix complexity**: Low (just add UI picker following existing pattern)

### Issue #2: License Class Filter Not Working
- **Status**: Backend logic missing from OptimizedQueryManager
- **Impact**: Filter has no effect, returns all records
- **Files to modify**: OptimizedQueryManager.swift:~857
- **Fix complexity**: Low (code pattern provided above, 15 lines)

### Issue #3: Database Schema Outdated
- **Status**: Code uses new schema, database still has old schema
- **Impact**: App will crash or fail imports until database is recreated
- **Fix**: Delete database and re-import (user action required)

---

## 9. Success Criteria

### Definition of Done

The implementation will be complete when:

1. ✅ **Code compiles** (DONE)
2. ⬜ **Experience level filter appears in FilterPanel UI**
3. ⬜ **Experience level filter changes query results** (fewer records when selected)
4. ⬜ **License class filter changes query results** (fewer records when selected)
5. ⬜ **Console shows correct SQL and bind values** for both filters
6. ⬜ **Database has new schema** (integer foreign keys, not TEXT)
7. ⬜ **experience_level_enum table is populated** with all unique values from CSV
8. ⬜ **No crashes or errors** during import or query

### Test Cases

**Test Case 1: Experience Level Filter**
- Select all years (2011-2022)
- Select ONE experience level (e.g., "1-5 years")
- Run query
- **Expected**: Record count < 12,000 (total across all years)
- **Expected**: Console shows 4 bind values (same ID repeated)

**Test Case 2: License Class Filter**
- Select all years
- Clear experience levels
- Select ONE license class (e.g., "Class 5")
- Run query
- **Expected**: Record count < 12,000
- **Expected**: Console shows `WHERE ... AND (l.has_driver_license_5 = 1)`

**Test Case 3: Combined Filters**
- Select both experience level AND license class
- Run query
- **Expected**: Smallest result set (AND logic)
- **Expected**: Both filters in WHERE clause

---

## 10. Session Context

**Token Usage**: 82% (164k/200k)
**Files Modified**: 3 (DatabaseManager.swift, FilterCacheManager.swift, OptimizedQueryManager.swift)
**Build Status**: ✅ Compiles successfully
**Git Status**: Uncommitted changes on `rhoge-dev` branch

**Key Insight from Session**:
The user's original question ("why do we need string binding?") led to the realization that experience levels were architecturally wrong. Rather than workaround the issue, we implemented the correct solution: full integer enumeration. This is consistent with the project's design philosophy of doing things the right way, not the quick way.

---

## 11. Quick Start for Next Session

```bash
# 1. Check current state
cd /Users/rhoge/Desktop/SAAQAnalyzer
git status

# 2. Verify build
# Open SAAQAnalyzer.xcodeproj in Xcode and build (Cmd+B)

# 3. Add license class filter query logic
# Edit OptimizedQueryManager.swift around line 857
# Copy pattern from DatabaseManager.swift:1666-1682
# Use table alias 'l', no parameter binding needed

# 4. Find and fix UI code in FilterPanel.swift
# Search for license-specific filters (ageGroups, genders)
# Add experienceLevels picker following same pattern

# 5. Delete database and re-import
rm ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite*
# Then launch app and import license CSV files

# 6. Test both filters and verify console output

# 7. Commit when working
git add -A
git commit -m "feat: Implement integer enumeration for experience levels"
```

---

**End of Handoff Document**
