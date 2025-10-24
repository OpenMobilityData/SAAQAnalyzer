# License Data Modernization - Analysis and Implementation Plan

**Date**: October 15, 2025
**Session Status**: Analysis Complete, Ready for Implementation
**Branch**: `rhoge-dev`
**Token Usage**: 159k/200k (80%)

---

## 1. Current Task & Objective

### Overall Goal
Bring driver's license data handling up to feature parity with the modernized vehicle registration architecture implemented in September-October 2025.

### Background
The application initially supported both vehicle registration and driver's license data. However, architectural improvements over the past months focused exclusively on vehicle data:
- Integer-based enumeration system
- Optimized query performance (416x speedup)
- Regularization framework for Make/Model/FuelType/VehicleType
- Curated years filtering with UI toggles
- Advanced metrics (RWI, Percentage, Coverage)
- Analytics/Filters UI separation

**Result**: License data support fell behind and is now partially broken.

### Specific Issues Identified

1. **Schema Mismatch** (CRITICAL)
   - Licenses table migrated to integer foreign keys (`age_group_id`, `gender_id`, `license_type_id`)
   - CSVImporter still tries to write to old string columns (`age_group`, `gender`, `license_type`)
   - Old license data was cleared during migration
   - **Import is completely broken** - writes to non-existent columns

2. **Missing Features**
   - Limited metrics (COUNT only, no Percentage/Coverage/Average)
   - No curated years filtering for licenses
   - No regularization infrastructure (placeholder needed)
   - FilterPanel shows correctly in UI but enum tables are empty

3. **Architecture Gaps**
   - No midpoint calculation for age groups/experience ranges
   - No average metric support (requires range-to-number conversion)
   - No hierarchical filtering (not needed for licenses)

---

## 2. Progress Completed

### ✅ Analysis Phase (This Session)

**Codebase Review:**
- Reviewed git logs (30+ commits) and handoff documents (60+ files in Notes/)
- Analyzed vehicle architecture evolution:
  - Integer enumeration system (CategoricalEnumManager)
  - Optimized queries (OptimizedQueryManager)
  - Regularization framework (RegularizationManager)
  - Canonical hierarchy cache (109x performance improvement)
- Compared vehicle vs license implementations across all layers

**Current License Support Status:**
- ✅ Integer enumeration schema exists (age_group_enum, gender_enum, license_type_enum)
- ✅ Optimized integer queries implemented (OptimizedQueryManager.swift:760-894)
- ✅ FilterCacheManager loads license enums (FilterCacheManager.swift:411-426)
- ✅ FilterPanel UI structure correct (FilterPanel.swift:462-103, lines 1757-1873)
- ✅ Database indexes in place for performance
- ❌ CSVImporter writes to wrong columns (broken)
- ❌ Enum tables empty (no data imported since migration)
- ❌ Limited metrics (COUNT only)
- ❌ No curated years support

**Database State Verified:**
```bash
# Database location
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite

# Tables exist with correct schema
licenses table: ✅ (schema migrated, data: 0 records)
age_group_enum: ✅ (empty)
gender_enum: ✅ (empty)
license_type_enum: ✅ (empty)

# Schema is integer-based (correct)
age_group_id INTEGER
gender_id INTEGER
license_type_id INTEGER

# Old string columns removed (cause of import failure)
age_group TEXT ❌ (removed)
gender TEXT ❌ (removed)
license_type TEXT ❌ (removed)
```

---

## 3. Key Decisions & Patterns

### Architectural Philosophy

**License Data Characteristics:**
- No explicit numeric values (only ranges and categories)
- No hierarchical relationships (flat structure)
- Multiple boolean columns for license classes (unique to licenses)
- Regularization needs unknown until 2023-2024 data arrives

**Supported Metrics (User-Specified):**
1. **Count** ✅ (already working in optimized path)
2. **Percentage in Superset** (needed)
3. **Coverage** (analyze NULL values)
4. **Average with Midpoints** (convert ranges to numbers)
   - Age groups: "16-19" → 17.5, "75+" → 80.0
   - Experience: "Moins de 2 ans" → 1.0, "10 ans ou plus" → 15.0

**Not Applicable:**
- Road Wear Index (vehicle-specific)
- Sum/Min/Max of numeric fields (none exist)
- Hierarchical filtering (no Make→Model equivalent)

### Design Patterns Established

**1. Integer Enumeration Pattern (from vehicles)**
```swift
// Enum table structure
CREATE TABLE age_group_enum (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    range_text TEXT UNIQUE NOT NULL
);

// Foreign key in main table
CREATE TABLE licenses (
    age_group_id INTEGER,
    FOREIGN KEY (age_group_id) REFERENCES age_group_enum(id)
);
```

**2. Midpoint Calculation Pattern (NEW for licenses)**
```swift
// Age group midpoints
func getAgeGroupMidpoint(range: String) -> Double? {
    switch range {
    case "16-19": return 17.5
    case "20-24": return 22.0
    case "25-34": return 29.5
    case "35-44": return 39.5
    case "45-54": return 49.5
    case "55-64": return 59.5
    case "65-74": return 69.5
    case "75+": return 80.0  // Reasonable estimate
    default: return nil
    }
}

// SQL CASE statement for averages
SELECT year, AVG(
    CASE age_group.range_text
        WHEN '16-19' THEN 17.5
        WHEN '20-24' THEN 22.0
        -- ... etc
    END
) as value
```

**3. CSV Import with Enumeration Population (from vehicles)**
```swift
// Pattern from DatabaseManager.importVehicleBatch():
// 1. Check if enum value exists
// 2. If not, INSERT OR IGNORE into enum table
// 3. Get enum ID
// 4. Write enum ID to main table

// This pattern needs to be applied to license import
```

---

## 4. Active Files & Locations

### Files Requiring Updates (Priority Order)

**CRITICAL - Import Fix:**
1. **`CSVImporter.swift`** (lines 758-856: `importLicenseBatch`)
   - Currently: Writes to string columns (age_group, gender, license_type)
   - Needs: Write to integer columns (age_group_id, gender_id, license_type_id)
   - Pattern: Follow `DatabaseManager.importVehicleBatch()` enumeration logic

2. **`DatabaseManager.swift`**
   - Add: `importLicenseBatch()` method with enum population
   - Pattern: Copy from vehicle import (lines 3300-3500 approx)
   - Location for new method: Near other license methods (~line 1497)

**HIGH - Query Enhancement:**
3. **`OptimizedQueryManager.swift`** (lines 760-894: `queryLicenseDataWithIntegers`)
   - Currently: COUNT only
   - Add: Percentage, Coverage, Average metrics
   - Pattern: Follow vehicle query switch (lines 539-645)

4. **`DatabaseManager.swift`** (lines 1497-1772: `queryLicenseData`)
   - Currently: COUNT only (legacy path)
   - Add: Same metrics as optimized path for consistency

**MEDIUM - Data Models:**
5. **`DataModels.swift`**
   - Add: `AgeGroupEnum.midpointValue` computed property
   - Add: Experience level enum with midpoints
   - Location: Near other enum definitions (lines 280-303)

6. **`DataModels.swift`** (lines 1425-1434: `availableMetricTypes`)
   - Currently: Filters out most metrics for licenses
   - Update: Allow Count, Percentage, Coverage, Average

**LOW - Future Enhancement:**
7. **`DatabaseManager.swift`** (schema creation)
   - Add: `license_regularization` table placeholder (minimal)
   - Pattern: Similar to `make_model_regularization` structure
   - Location: In `createTablesIfNeeded()` (line 773+)

8. **`FilterCacheManager.swift`**
   - Add: Curated years filtering for license enums
   - Methods: `getAvailableAgeGroups(limitToCuratedYears:)`
   - Pattern: Follow vehicle Make/Model filtering (lines 470-509)

### Reference Files (Working Examples)

**Vehicle Import Pattern:**
- `DatabaseManager.swift:3300-3500` - Vehicle batch import with enum population

**Optimized Query Pattern:**
- `OptimizedQueryManager.swift:325-745` - Vehicle queries with all metrics

**Enum Population Pattern:**
- `CategoricalEnumManager.swift` - How enumerations are managed

**Regularization Table Example:**
- `DatabaseManager.swift:827-849` - Canonical hierarchy cache structure

---

## 5. Current State: Where We Are

### Database State
- ✅ Integer schema is correct
- ✅ Indexes in place
- ❌ **License import is broken** (writes to wrong columns)
- ❌ Enum tables are empty (no data to query)
- ❌ 0 license records in database

### Code State
- ✅ FilterPanel UI ready (shows correct sections for license mode)
- ✅ Basic COUNT query works (if data existed)
- ✅ Integer query path exists
- ❌ CSVImporter incompatible with current schema
- ❌ Limited metric support
- ❌ No curated years integration

### What's Working
1. UI switches correctly between vehicle/license modes
2. FilterPanel structure loads appropriate sections
3. Optimized query infrastructure exists
4. Database schema is properly designed

### What's Broken
1. **License import completely non-functional** (schema mismatch)
2. Enum tables never populated (can't display filter options)
3. FilterPanel shows empty lists (no enum data to load)
4. Queries fail silently (no data to query)

---

## 6. Next Steps (Priority Order)

### **Phase 1: Fix Import & Restore Basic Functionality** (CRITICAL - 4-6 hours)

**Step 1.1: Fix CSVImporter (2-3 hours)**
```swift
// Location: CSVImporter.swift:758-856 (importLicenseBatch)
// Current (BROKEN):
sqlite3_bind_text(insertStmt, 3, record["AGE_1ER_JUIN"] ?? "", ...)  // age_group column

// New (WORKING):
// 1. Get or create age group enum
let ageGroupText = record["AGE_1ER_JUIN"] ?? ""
let ageGroupId = try await getOrCreateAgeGroupEnum(ageGroupText)

// 2. Bind integer ID instead
sqlite3_bind_int(insertStmt, 3, Int32(ageGroupId))
```

**Implementation Pattern:**
- Create `getOrCreateAgeGroupEnum()` in DatabaseManager
- Create `getOrCreateGenderEnum()` in DatabaseManager
- Create `getOrCreateLicenseTypeEnum()` in DatabaseManager
- Update `importLicenseBatch()` to use these helpers
- Follow vehicle import pattern exactly

**Step 1.2: Test Import (30 min)**
- Re-import one year of license data
- Verify enum tables populate
- Verify licenses table has data with integer IDs
- Check FilterPanel shows populated dropdowns

**Step 1.3: Verify Queries (30 min)**
- Test COUNT metric works
- Verify FilterPanel loads filter options
- Test switching between vehicle/license modes

---

### **Phase 2: Implement Missing Metrics** (MEDIUM - 4-6 hours)

**Step 2.1: Add Percentage Metric (2 hours)**
Location: `OptimizedQueryManager.swift:760-894`

Pattern: Follow vehicle percentage implementation
```swift
case .percentage:
    // Dual-query pattern
    // 1. Run numerator query (filtered count)
    // 2. Run baseline query (less filtered count)
    // 3. Calculate percentage: (numerator/baseline) * 100
```

**Step 2.2: Add Coverage Metric (1 hour)**
Pattern: Follow vehicle coverage (DatabaseManager.swift)
```sql
-- Percentage coverage
SELECT year,
    (CAST(COUNT(age_group_id) AS REAL) / CAST(COUNT(*) AS REAL) * 100.0) as value
FROM licenses
GROUP BY year
```

**Step 2.3: Add Average with Midpoints (2-3 hours)**

A. Add midpoint helpers to DataModels.swift:
```swift
extension AgeGroupEnum {
    var midpointValue: Double {
        switch range {
        case "16-19": return 17.5
        case "20-24": return 22.0
        // ... etc
        default: return 50.0  // fallback
        }
    }
}
```

B. Implement SQL CASE for averages:
```sql
SELECT year, AVG(
    CASE age.range_text
        WHEN '16-19' THEN 17.5
        WHEN '20-24' THEN 22.0
        -- ... etc
    END
) as value
FROM licenses l
JOIN age_group_enum age ON l.age_group_id = age.id
GROUP BY year
```

C. Update `DataModels.swift:1425-1434` to allow new metrics:
```swift
private var availableMetricTypes: [ChartMetricType] {
    switch currentFilters.dataEntityType {
    case .license:
        return [.count, .average, .percentage, .coverage]  // ← Update this
    case .vehicle:
        return ChartMetricType.allCases
    }
}
```

**Step 2.4: Extend DatabaseManager.queryLicenseData (1 hour)**
- Add same metrics to legacy query path
- Ensure consistency between optimized and non-optimized

---

### **Phase 3: Curated Years Support** (LOW - 2-3 hours)

**Step 3.1: Update OptimizedQueryManager (1 hour)**
Location: `OptimizedQueryManager.swift:100-116`

```swift
// Current: Only applies to vehicles
if isVehicle && filters.limitToCuratedYears { ... }

// New: Apply to all entity types
if filters.limitToCuratedYears {
    let regManager = databaseManager?.regularizationManager
    let yearConfig = regManager?.getYearConfiguration()
    let curatedYears = yearConfig?.curatedYears ?? []
    yearsToQuery = filters.years.intersection(curatedYears)
}
```

**Step 3.2: Update FilterCacheManager (1-2 hours)**
Add curated filtering methods:
```swift
func getAvailableAgeGroups(limitToCuratedYears: Bool = false) async throws -> [FilterItem]
func getAvailableLicenseTypes(limitToCuratedYears: Bool = false) async throws -> [FilterItem]
func getAvailableGenders(limitToCuratedYears: Bool = false) async throws -> [FilterItem]
```

Pattern: Filter enum items by curated years set (like vehicle Make/Model)

---

### **Phase 4: Regularization Placeholder** (VERY LOW - 30 min)

**Step 4.1: Add Schema Only**
Location: `DatabaseManager.swift:createTablesIfNeeded()`

```sql
CREATE TABLE IF NOT EXISTS license_regularization (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uncurated_age_group_id INTEGER,
    uncurated_license_type_id INTEGER,
    canonical_age_group_id INTEGER,
    canonical_license_type_id INTEGER,
    record_count INTEGER,
    year_range_start INTEGER,
    year_range_end INTEGER,
    created_date TEXT,

    FOREIGN KEY (uncurated_age_group_id) REFERENCES age_group_enum(id),
    FOREIGN KEY (canonical_age_group_id) REFERENCES age_group_enum(id)
);
```

**No implementation needed** - Just schema for future when 2023-2024 data arrives.

---

### **Phase 5: Documentation** (1 hour)

**Update CLAUDE.md:**
- Document license metric limitations
- Note midpoint approximation approach
- Add license example to "Adding New Metric Types"
- Update database schema section

**Inline Documentation:**
- Add comments explaining midpoint calculations
- Document why averages are approximations
- Note that regularization is placeholder-only

---

## 7. Important Context

### Root Cause Analysis

**Why License Import Broke:**
1. September 2024: Integer enumeration migration applied to schema
2. Schema changed: `age_group TEXT` → `age_group_id INTEGER`
3. Old license data was cleared (migration side effect)
4. CSVImporter was **not updated** to match new schema
5. Import attempts write to non-existent string columns → silent failure

**Why It Wasn't Caught:**
- Development focused exclusively on vehicle data
- No test license imports performed after migration
- FilterPanel UI works (shows correct structure) but has no data to display
- No error logging for column mismatch (SQLite silently ignores bad columns)

### Schema Comparison

**Vehicles (Working):**
```sql
-- Old: make TEXT, model TEXT
-- New: make_id INTEGER, model_id INTEGER
-- Import: ✅ Updated to populate enums and write IDs
```

**Licenses (Broken):**
```sql
-- Old: age_group TEXT, gender TEXT, license_type TEXT
-- New: age_group_id INTEGER, gender_id INTEGER, license_type_id INTEGER
-- Import: ❌ Still tries to write to old TEXT columns
```

### Critical File Locations

**Import Logic:**
- Vehicle import (working): `DatabaseManager.swift:3300-3500` approx
- License import (broken): `CSVImporter.swift:758-856`

**Query Logic:**
- Vehicle queries (all metrics): `OptimizedQueryManager.swift:325-745`
- License queries (COUNT only): `OptimizedQueryManager.swift:760-894`

**Database Schema:**
- Table creation: `DatabaseManager.swift:773+`
- Enum table schema: Lines 1005-1009

**UI Filter Loading:**
- FilterPanel license section: `FilterPanel.swift:462-103` (loadDataTypeSpecificOptions)
- License filter display: `FilterPanel.swift:1757-1873` (LicenseFilterSection)

### Key Patterns to Follow

**1. Enum Population Pattern (from vehicle import):**
```swift
// Check if enum exists, insert if not
let checkSQL = "SELECT id FROM age_group_enum WHERE range_text = ?"
let insertSQL = "INSERT OR IGNORE INTO age_group_enum (range_text) VALUES (?)"
let getId = "SELECT id FROM age_group_enum WHERE range_text = ?"

// Returns integer ID for use in foreign key
```

**2. Midpoint Pattern (new for licenses):**
```swift
// In Swift (for UI/helpers):
extension AgeGroupEnum {
    var midpointValue: Double { /* switch on range */ }
}

// In SQL (for AVG queries):
CASE age_group.range_text
    WHEN '16-19' THEN 17.5
    WHEN '20-24' THEN 22.0
    -- ...
END
```

**3. Metric Switch Pattern:**
```swift
switch filters.metricType {
case .count:
    selectClause = "COUNT(*) as value"
case .average:
    // Add CASE statement for midpoints
    selectClause = "AVG(CASE ...) as value"
case .percentage:
    // Dual-query pattern
case .coverage:
    // NULL analysis pattern
}
```

### Dependencies & Requirements

**No New Dependencies:**
- All functionality uses existing SQLite3
- Uses existing SwiftUI/Charts frameworks
- No external packages needed

**Database State Requirements:**
- Must re-import license CSV files after fixing importer
- Enum tables will auto-populate during import
- Old license data is gone (migration cleared it)

### Performance Considerations

**License Data Characteristics:**
- Smaller dataset than vehicles (~1-2M records vs 70M+)
- Fewer unique enum values (8 age groups vs 10K models)
- No regularization needed yet (no uncurated data)
- Should query very fast (< 100ms expected)

**Optimization Not Needed:**
- Integer queries already optimized
- Indexes already in place
- No cache needed (enum tables are tiny)

---

## 8. Testing Strategy

### Phase 1 Testing (After Import Fix)
```bash
# 1. Verify enum tables populated
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT COUNT(*) FROM age_group_enum;
   SELECT COUNT(*) FROM gender_enum;
   SELECT COUNT(*) FROM license_type_enum;"

# Expected: 8, 2, 3 (or similar non-zero values)

# 2. Verify license data imported
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT COUNT(*) FROM licenses;"

# Expected: > 0

# 3. Verify integer IDs used
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT age_group_id, gender_id, license_type_id FROM licenses LIMIT 5;"

# Expected: Integer values, not NULL
```

### Phase 2 Testing (After Metrics)
- Switch to license mode in UI
- Select filters
- Try each metric type:
  - Count: Should show number of license holders
  - Average: Should show ~40-50 for age groups
  - Percentage: Should show percentage breakdown
  - Coverage: Should show 90%+ for required fields

### Phase 3 Testing (After Curated Years)
- Toggle "Limit to Curated Years Only"
- Verify filter dropdowns update
- Verify queries respect curated years filter

---

## 9. Quick Start Commands for Next Session

```bash
# Navigate to project
cd /Users/rhoge/Desktop/SAAQAnalyzer

# Check database state
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT COUNT(*) FROM licenses;
   SELECT COUNT(*) FROM age_group_enum;"

# Open in Xcode
open SAAQAnalyzer.xcodeproj

# Key files to modify (in order):
# 1. CSVImporter.swift:758-856 (fix import)
# 2. DatabaseManager.swift (add enum helpers)
# 3. OptimizedQueryManager.swift:760-894 (add metrics)
# 4. DataModels.swift (add midpoint helpers)
```

---

## 10. Decision Log

### Decisions Made This Session

1. **Focus on Import First** ✅
   - Rationale: Cannot test anything without data
   - Priority: CRITICAL (blocks all other work)

2. **Use Midpoint Approximation for Averages** ✅
   - Rationale: Only way to get numeric values from range data
   - Trade-off: Approximation vs no average support
   - Mitigation: Document clearly, reasonable estimates

3. **Defer Regularization to Future** ✅
   - Rationale: Don't have 2023-2024 license data yet
   - Decision: Empty table schema only
   - Timing: Implement when uncurated data arrives

4. **No Hierarchical Filtering** ✅
   - Rationale: License attributes are flat (no Make→Model equivalent)
   - Decision: Skip this feature entirely for licenses

5. **Phase-Based Implementation** ✅
   - Phase 1: Fix import (critical)
   - Phase 2: Add metrics (high value)
   - Phase 3: Curated years (nice-to-have)
   - Phase 4: Regularization placeholder (future)

### Open Questions for Next Session

1. **Experience Level Enum**: Should we create a separate enum table for experience levels, or keep as strings?
   - Recommendation: Keep as strings (only 4-5 values, infrequent filtering)

2. **License Class Boolean Columns**: Current approach uses 9 boolean columns. Is this optimal?
   - Current: Works well, efficient storage, easy to query
   - Alternative: Normalized junction table (more complex, no benefit)
   - Recommendation: Keep current approach

3. **Import UI**: Should we add specific UI feedback for license imports?
   - Current: Generic import dialog
   - Enhancement: Could show "License Import" with field preview
   - Priority: Low (works fine as-is)

---

## 11. Estimated Effort

**Total Implementation Time: 10-14 hours**

| Phase | Priority | Hours | Complexity |
|-------|----------|-------|-----------|
| Phase 1: Fix Import | CRITICAL | 4-6 | Medium |
| Phase 2: Add Metrics | HIGH | 4-6 | Medium |
| Phase 3: Curated Years | MEDIUM | 2-3 | Low |
| Phase 4: Regularization | LOW | 0.5 | Trivial |
| Phase 5: Documentation | LOW | 1 | Low |

**Recommended Approach:**
- Session 1: Complete Phase 1 (import fix) and test thoroughly
- Session 2: Complete Phase 2 (metrics) and Phase 3 (curated years)
- Session 3: Polish, documentation, comprehensive testing

---

## 12. Success Criteria

### Must Have (Phase 1)
- ✅ License CSV import works without errors
- ✅ Enum tables populate automatically during import
- ✅ FilterPanel shows populated filter options in license mode
- ✅ Basic COUNT query returns correct data

### Should Have (Phase 2)
- ✅ Percentage metric calculates correctly
- ✅ Coverage metric shows data completeness
- ✅ Average metric uses midpoint approximation
- ✅ All metrics work in both optimized and legacy query paths

### Nice to Have (Phase 3)
- ✅ Curated years toggle affects license queries
- ✅ Filter dropdowns respect curated years setting
- ✅ UI consistent with vehicle mode behavior

### Future (Phase 4)
- ✅ Regularization table schema in place
- ⏳ Implementation deferred until uncurated data arrives

---

## 13. Known Issues & Limitations

### Current Limitations

1. **No Numeric Fields**
   - License data has no true numeric values
   - Only ranges and categories
   - Averages are approximations via midpoints

2. **Boolean License Classes**
   - 9 separate boolean columns for license types
   - Not normalized (but efficient and practical)
   - Filtering works via multi-column OR logic

3. **Experience Levels**
   - Stored as text strings, not enumerated
   - 4 separate experience columns (1234, 5, 6ABCE, global)
   - Filtering requires checking all 4 columns

4. **No Municipality Data**
   - License records have Region/MRC but not Municipality
   - Vehicle data has all 3 levels
   - FilterPanel should handle this gracefully

### Future Enhancements

1. **Smart Midpoint Selection**
   - Could use actual data distribution to refine midpoints
   - Example: If 75+ has median 78, use that instead of 80

2. **Experience Level Enumeration**
   - Could create enum table for experience levels
   - Would enable faster filtering
   - Low priority (only 4-5 values)

3. **License Class UI Improvement**
   - Could show checkboxes for each class type
   - Currently uses text-based filter
   - Enhancement, not bug

---

## Status Summary

**✅ COMPLETE:**
- Analysis of vehicle architecture evolution
- Identification of broken license import
- Understanding of schema migration impact
- Comprehensive implementation plan created

**🚧 IN PROGRESS:**
- Nothing (analysis session complete)

**⏳ NOT STARTED:**
- Import fix
- Metric implementation
- Curated years integration
- Regularization placeholder

**🎯 NEXT SESSION:**
Start with Phase 1 (Fix Import) - file `CSVImporter.swift:758-856`

---

**Session Complete - Ready for Implementation**
**Handoff Document Version:** 1.0
**Last Updated:** 2025-10-15 16:45 PST
