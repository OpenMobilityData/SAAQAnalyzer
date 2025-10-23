# Canonical Hierarchy NULL Fuel Type Bug Fix - Complete

**Date**: October 10, 2025
**Status**: ✅ Complete and Committed
**Branch**: `rhoge-dev`
**Commit**: `363f830` - fix: Include NULL fuel_type model years in canonical hierarchy

---

## 1. Current Task & Objective

### Primary Goal
Fix critical bug in canonical hierarchy generation that excluded model years with NULL fuel_type values, preventing users from completing regularization mappings for Make/Model pairs that only exist in pre-2017 curated data.

### Root Problem
The RegularizationManager only initialized model year entries in the canonical hierarchy when fuel_type data existed. Since the SAAQ schema didn't include the fuel_type field (`TYP_CARBU`) until 2017, all vehicles in registration years 2011-2016 have NULL fuel_type, causing their model years to be completely omitted from the hierarchy.

### User Impact
- Users couldn't see model years in Step 4 of Regularization Editor for pre-2017 pairs
- Pairs remained stuck in "Needs Review" status with no way to complete them
- Example: VOLKS/TOUAR (Volkswagen Touareg) had model years 2010, 2011, 2017 but none appeared in the UI

---

## 2. Progress Completed

### A. Bug Fix Implementation (✅ Complete)

**File**: `SAAQAnalyzer/DataLayer/RegularizationManager.swift`
**Location**: Lines 180-218 in `generateCanonicalHierarchy()` method

**Changes**:
1. **Always initialize model year entries** (lines 182-184):
   ```swift
   // Initialize model year entry (always, even if fuel type is NULL)
   // This ensures pre-2017 model years (with NULL fuel_type) appear in the hierarchy
   if makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId] == nil {
       makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId] = []
   }
   ```

2. **Add fuel type only if present** (lines 187-201):
   - Wraps existing fuel type addition logic in conditional
   - Only executes when fuel_type data exists

3. **Add placeholder for NULL fuel_type** (lines 201-218):
   ```swift
   else if let myId = modelYearId, let myYear = modelYear {
       // Fuel type is NULL (pre-2017 data) - add a placeholder to preserve model year information
       // Use a negative ID to indicate this is a placeholder (won't conflict with real IDs)
       // This ensures UI sorting/display works correctly for empty fuel type arrays
       let placeholderInfo = MakeModelHierarchy.FuelTypeInfo(
           id: -1,  // Placeholder ID
           code: "",
           description: "",
           recordCount: recordCount,
           modelYearId: myId,
           modelYear: myYear
       )

       // Only add placeholder if array is still empty (avoid duplicates from multiple rows)
       if makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId]!.isEmpty {
           makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId]!.append(placeholderInfo)
       }
   }
   ```

**Rationale**: The placeholder preserves the model year value for sorting and display purposes, while the `-1` ID makes it easy to filter out.

### B. UI Updates (✅ Complete)

**File**: `SAAQAnalyzer/UI/RegularizationView.swift`

**Changes**:
1. **Filter placeholders in fuel type display** (line 878):
   ```swift
   private var validFuelTypes: [MakeModelHierarchy.FuelTypeInfo] {
       fuelTypes.filter { fuelType in
           fuelType.id != -1 &&  // Filter out placeholder entries for NULL fuel types
           !fuelType.description.localizedCaseInsensitiveContains("not specified") &&
           !fuelType.description.localizedCaseInsensitiveContains("not assigned") &&
           !fuelType.description.localizedCaseInsensitiveContains("non spécifié")
       }
   }
   ```

2. **Filter placeholders in auto-regularization** (line 1328):
   - Same filter applied to auto-regularization logic
   - Ensures placeholders don't interfere with automatic assignments

**Result**: Users see only valid options:
- "Not Assigned" (default)
- "Unknown" (recommended for NULL fuel_type years)
- Actual fuel types from the data (if any)

### C. Documentation Updates (✅ Complete)

**File 1**: `Documentation/REGULARIZATION_BEHAVIOR.md`

**New Section Added** (lines 249-286): "Model Year vs Registration Year: The 2017 Fuel Type Cutoff"

**Content**:
- Explains distinction between AN (registration year) and ANNEE_MOD (model year)
- Documents that TYP_CARBU field was added in 2017
- Explains edge case: Model year 2017 vehicles in 2016 registration data
- Provides VOLKS/TOUAR as concrete example
- Recommends selecting "Unknown" for NULL fuel_type years

**File 2**: `Documentation/Vehicle-Registration-Schema.md`

**Updated Section** (lines 134-144): Fuel Type section

**Content**:
- Clarified field was added to SAAQ schema in 2017
- Documented NULL for all vehicles in registration years 2011-2016
- Explained edge case scenario with examples

---

## 3. Key Decisions & Patterns

### A. Placeholder Pattern

**Decision**: Use `id: -1` for placeholder FuelTypeInfo entries

**Rationale**:
- Negative IDs will never conflict with real database IDs (always positive)
- Easy to filter in UI code with simple `id != -1` check
- Preserves model year data needed for sorting (`modelYear` field)
- Enables consistent data structure (every model year has at least one entry)

**Alternative Considered**: Keep empty arrays and handle nil checks in UI
- **Rejected**: Would break sorting logic that depends on `fuelTypes.first?.modelYear`
- Current approach is cleaner and more robust

### B. Data Availability vs User Decision

**Decision**: Distinguish between "data unavailable" and "user hasn't decided yet"

**Implementation**:
- **NULL in database** = "Not Assigned" in UI = User hasn't reviewed yet
- **"Unknown" enum value** = User reviewed and determined it's unknowable
- **Specific value** = User identified the type

**User Flow**:
1. Pre-2017 model years have no fuel_type data in source
2. User sees "Not Assigned" and "Unknown" as only options
3. User selects "Unknown" to acknowledge fuel type cannot be determined
4. Pair moves from "Needs Review" to "Complete" status

### C. Registration Year vs Model Year

**Critical Understanding**: The 2017 cutoff refers to **registration year** (when the snapshot was taken), not model year.

**Implications**:
- Model year 2017 vehicles can have NULL fuel_type if registered in 2016
- Model year 2010 vehicles can have fuel_type if registered in 2017+
- Always check registration year (curated years 2011-2016) not model year

---

## 4. Active Files & Locations

### Modified Files (All Committed)

1. **`SAAQAnalyzer/DataLayer/RegularizationManager.swift`** (+38 lines, -7 lines)
   - Lines 180-218: Hierarchy generation bug fix
   - Purpose: Generate canonical Make/Model/ModelYear/FuelType hierarchy from curated data

2. **`SAAQAnalyzer/UI/RegularizationView.swift`** (+2 lines)
   - Line 878: Filter placeholder in `validFuelTypes` computed property
   - Line 1328: Filter placeholder in `autoRegularizeExactMatches()` method
   - Purpose: Regularization editor UI and auto-assignment logic

3. **`Documentation/REGULARIZATION_BEHAVIOR.md`** (+37 lines)
   - Lines 249-286: New section on model year vs registration year
   - Purpose: User guide for regularization system behavior

4. **`Documentation/Vehicle-Registration-Schema.md`** (+5 lines)
   - Lines 134-144: Enhanced fuel type section with 2017 cutoff explanation
   - Purpose: Schema documentation for Quebec vehicle registration data

### Related Files (No Changes)

5. **`SAAQAnalyzer/Models/DataModels.swift`**
   - Lines 1735-1742: FuelTypeInfo struct definition (includes modelYearId and modelYear fields)
   - Lines 1675-1715: MakeModelHierarchy struct definition
   - Purpose: Data model reference

### Session Notes (Untracked)

6. **`Notes/2025-10-10-Incomplete-Fields-Filter-and-Hierarchy-Bug.md`**
   - Detailed session notes from filter implementation + bug discovery
   - Current file

7. **`Notes/2025-10-10-Regularization-UX-Improvements-Complete.md`**
   - Session notes from previous incomplete fields filter work

---

## 5. Current State

### ✅ Fully Complete

All tasks have been successfully completed and committed:

**Commit Details**:
```
Branch: rhoge-dev
Commit: 363f830
Message: fix: Include NULL fuel_type model years in canonical hierarchy

Status:
- Your branch is ahead of 'origin/rhoge-dev' by 1 commit
- No uncommitted changes
- Working tree clean
```

**Verification**:
- Screenshot shows VOLKS/TOUAR with all three model years (2010, 2011, 2017) appearing in Step 4
- Each year displays "Not Assigned" and "Unknown" options correctly
- No actual fuel type options appear (expected since all have NULL fuel_type)
- Count shows "3 of 3 years" confirming all years are present

**Quality Checks**:
- ✅ Code compiles without errors
- ✅ UI displays correctly for test case
- ✅ Documentation updated with clear explanations
- ✅ Commit message follows project conventions
- ✅ Changes tested and verified working

---

## 6. Next Steps (Priority Order)

### 🟢 OPTIONAL - Push to Remote

```bash
git push origin rhoge-dev
```

**Decision Point**: User may want to test more thoroughly before pushing, or push immediately if confident.

### 🟢 OPTIONAL - Test Additional Pre-2017 Pairs

**Recommended Test Cases**:
1. Find other Make/Model pairs that only exist in curated years 2011-2016
2. Verify model years appear in Step 4
3. Assign "Unknown" to all years
4. Verify status changes to "Complete"
5. Save and verify mappings persist correctly

**Query to Find Test Cases**:
```sql
-- Find Make/Model pairs only in pre-2017 curated data
SELECT DISTINCT
    mk.name as make,
    md.name as model,
    COUNT(DISTINCT my.year) as model_year_count,
    GROUP_CONCAT(DISTINCT my.year ORDER BY my.year) as years
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
JOIN make_enum mk ON v.make_id = mk.id
JOIN model_enum md ON v.model_id = md.id
LEFT JOIN model_year_enum my ON v.model_year_id = my.id
WHERE y.year IN (2012, 2016)  -- Curated years
GROUP BY mk.name, md.name
HAVING model_year_count > 0
LIMIT 20;
```

### 🟢 OPTIONAL - Consider Future Enhancements

**Ideas for Future Sessions**:

1. **Add visual indicator for NULL fuel_type years**:
   - Show icon or badge next to "Model Year XXXX" header
   - Tooltip: "No fuel type data available (pre-2017)"
   - Helps users understand why no fuel type options appear

2. **Bulk "Unknown" assignment**:
   - Button to assign "Unknown" to all "Not Assigned" years at once
   - Useful for pre-2017 pairs where all years will be "Unknown"
   - Could save significant time for bulk regularization

3. **Filter for pre-2017 pairs**:
   - Add filter option in RegularizationView
   - "Show only pre-2017 pairs" (pairs with all NULL fuel_types)
   - Helps users batch-process these special cases

4. **Statistics/reporting**:
   - Count how many pairs have NULL fuel_type years
   - Show percentage of regularization that's pre-2017
   - Could inform priority decisions

---

## 7. Important Context

### A. Errors Solved

#### Issue 1: Sorting Logic Failure
**Problem**: Initial attempt to just initialize empty arrays broke sorting logic in RegularizationView.swift lines 807-811.

**Code That Would Have Failed**:
```swift
private var sortedYears: [Int?] {
    model.modelYearFuelTypes.keys.sorted { yearId1, yearId2 in
        guard let id1 = yearId1, let fuelTypes1 = model.modelYearFuelTypes[id1],
              let year1 = fuelTypes1.first?.modelYear else { return false }
        // When fuelTypes1 is empty, fuelTypes1.first is nil, year1 fails to unwrap
    }
}
```

**Solution**: Add placeholder FuelTypeInfo with model year data so `fuelTypes.first?.modelYear` always succeeds.

#### Issue 2: SQL Query Grouping
**Understanding**: The SQL query at RegularizationManager.swift:133 groups by `ft.id` (fuel_type_id):

```sql
GROUP BY mk.id, md.id, my.id, ft.id, vt.id
```

**Implication**: When `ft.id` is NULL (pre-2017 data), all records with the same Make/Model/ModelYear but NULL fuel_type get grouped into **one row**.

**Result**: We only get one row per model year with NULL fuel_type, so the placeholder check at line 215 (`if array.isEmpty`) prevents duplicates.

### B. Dependencies

**No New Dependencies Added**

All changes use existing Swift/SwiftUI constructs:
- Standard library types (Int, String, Array)
- SwiftUI framework (existing import)
- SQLite3 (existing import)

### C. Gotchas Discovered

#### Gotcha 1: Model Year vs Registration Year Confusion
**Issue**: Easy to confuse model year with registration year when discussing the 2017 cutoff.

**Example**:
- ❌ "Fuel type is available for model year 2017+"
- ✅ "Fuel type is available in registration year 2017+ (regardless of model year)"

**Remember**: A 2017 model year vehicle registered in 2016 will have NULL fuel_type.

#### Gotcha 2: Placeholder ID Must Be Filtered Everywhere
**Issue**: If you add new code that iterates over fuel types, you MUST filter out `id == -1`.

**Locations to Remember**:
- Any UI display code showing fuel type options
- Any auto-assignment logic
- Any statistics/counting code
- Any export/reporting features

**Pattern to Use**:
```swift
let validFuelTypes = fuelTypes.filter { $0.id != -1 }
```

#### Gotcha 3: Empty Array vs Array With Placeholder
**Issue**: `modelYearFuelTypes[yearId]` is never truly empty after this fix.

**Before Fix**: Could be missing key entirely or have empty array `[]`
**After Fix**: Always has key with array containing at least placeholder

**Code That Might Need Review**:
```swift
// This will always be true now (never nil):
if let fuelTypes = model.modelYearFuelTypes[yearId] {
    // But fuelTypes might only contain placeholder (id: -1)
}

// Better check:
if let fuelTypes = model.modelYearFuelTypes[yearId] {
    let validTypes = fuelTypes.filter { $0.id != -1 }
    if validTypes.isEmpty {
        // Truly no fuel type data
    }
}
```

### D. Testing Notes

**Test Dataset**: User is working with abbreviated dataset for faster iteration.

**Database Location**:
```
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

**Verified Test Case**: VOLKS/TOUAR (Volkswagen Touareg)
- **Make**: VOLKS
- **Model**: TOUAR
- **Curated Years**: 2012, 2016 (3 total records)
- **Model Years**: 2010, 2011, 2017
- **Fuel Types**: All NULL (as expected)
- **Vehicle Type**: AU (Automobile or Light Truck) - auto-assigned

**Test Query**:
```sql
-- Verify VOLKS/TOUAR records
SELECT
    mk.name as make,
    md.name as model,
    my.year as model_year,
    ft.description as fuel_type,
    vt.description as vehicle_type,
    COUNT(*) as records
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
JOIN make_enum mk ON v.make_id = mk.id
JOIN model_enum md ON v.model_id = md.id
LEFT JOIN model_year_enum my ON v.model_year_id = my.id
LEFT JOIN fuel_type_enum ft ON v.fuel_type_id = ft.id
LEFT JOIN vehicle_type_enum vt ON v.vehicle_type_id = vt.id
WHERE mk.name = 'VOLKS' AND md.name = 'TOUAR' AND y.year IN (2012, 2016)
GROUP BY mk.name, md.name, my.year, ft.description, vt.description;
```

**Expected Output**:
```
VOLKS|TOUAR|2010|<NULL>|Automobile or Light Truck|1
VOLKS|TOUAR|2011|<NULL>|Automobile or Light Truck|1
VOLKS|TOUAR|2017|<NULL>|Automobile or Light Truck|1
```

Note the empty column between model_year and vehicle_type = NULL fuel_type.

### E. Code Style & Patterns

**Swift Version**: 6.2
**Concurrency**: Modern async/await patterns (no DispatchQueue)
**UI Framework**: SwiftUI (avoid AppKit/NS* APIs when possible)
**Database**: SQLite3 with direct C API usage (no wrapper library)

**Patterns Used in This Fix**:
- Conditional initialization with nil-coalescing
- Guard-let chains for optional unwrapping
- Filter operations on arrays with complex predicates
- Negative sentinel values for special cases (-1 for placeholder)

### F. Related Features

**This fix enables completion of**:
1. **Incomplete Fields Filter** (implemented in previous session):
   - Can now correctly identify pairs with NULL fuel_type triplets
   - Users can filter to find pre-2017 pairs needing "Unknown" assignment

2. **Regularization Status System**:
   - Pairs can now achieve "Complete" (green) status
   - Before: Stuck in "Needs Review" (orange) indefinitely
   - After: Assign "Unknown" to NULL years → status changes to "Complete"

3. **Auto-Regularization**:
   - Still skips model years with multiple fuel types (as designed)
   - Now correctly handles model years with NULL fuel_type (skips them)
   - User must manually assign "Unknown" for these years

---

## 8. Handoff Checklist

For the next Claude Code session to continue seamlessly:

### ✅ Code State
- [x] All changes committed
- [x] Working tree clean
- [x] No compilation errors
- [x] Fix tested and verified working

### ✅ Documentation
- [x] User-facing documentation updated (REGULARIZATION_BEHAVIOR.md)
- [x] Schema documentation updated (Vehicle-Registration-Schema.md)
- [x] Session notes written (this file)
- [x] Code comments added to explain placeholder pattern

### ✅ Context Preserved
- [x] Test case documented (VOLKS/TOUAR)
- [x] SQL queries provided for verification
- [x] Database location noted
- [x] Gotchas and edge cases documented
- [x] Related features cross-referenced

### ✅ Next Actions Clear
- [x] Optional: Push to remote
- [x] Optional: Additional testing recommendations
- [x] Optional: Future enhancement ideas listed

---

## 9. Quick Reference

### Key File Locations
```
Code Changes:
  SAAQAnalyzer/DataLayer/RegularizationManager.swift:180-218
  SAAQAnalyzer/UI/RegularizationView.swift:878,1328

Documentation:
  Documentation/REGULARIZATION_BEHAVIOR.md:249-286
  Documentation/Vehicle-Registration-Schema.md:134-144

Data Models:
  SAAQAnalyzer/Models/DataModels.swift:1735-1742 (FuelTypeInfo)

Session Notes:
  Notes/2025-10-10-Hierarchy-Bug-Fix-Complete.md (this file)
```

### Key Concepts
```
Placeholder ID: -1 (indicates NULL fuel_type from source data)
Registration Year: Year of snapshot (AN field) - determines if fuel_type exists
Model Year: Manufacturer's model year (ANNEE_MOD field) - can be any value
2017 Cutoff: TYP_CARBU field added to SAAQ schema in registration year 2017
Curated Years: 2011-2016 (NULL fuel_type for all)
Uncurated Years: 2023-2024 (fuel_type populated)
```

### Essential Queries
```sql
-- Find pre-2017 test cases
SELECT mk.name, md.name, COUNT(*)
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
JOIN make_enum mk ON v.make_id = mk.id
JOIN model_enum md ON v.model_id = md.id
WHERE y.year IN (2012, 2016)
GROUP BY mk.name, md.name;

-- Check regularization mappings
SELECT
    uc_make.name, uc_model.name,
    r.model_year_id, ft.description as fuel_type
FROM make_model_regularization r
JOIN make_enum uc_make ON r.uncurated_make_id = uc_make.id
JOIN model_enum uc_model ON r.uncurated_model_id = uc_model.id
LEFT JOIN fuel_type_enum ft ON r.fuel_type_id = ft.id;
```

---

**Session End**: October 10, 2025
**Duration**: Approximately 2 hours (filter implementation + bug discovery + bug fix + documentation)
**Outcome**: ✅ Complete Success - Bug fixed, tested, documented, and committed
