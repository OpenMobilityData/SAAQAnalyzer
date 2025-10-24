# Regularization Manager: Performance, Model Year, and Status Fixes - Session Handoff

**Date**: October 21, 2025
**Status**: ⚠️ In Progress - Two Bugs Remaining
**Branch**: `rhoge-dev`
**Context Token Usage**: 176k/200k (88%)

---

## 1. Current Task & Objective

### Primary Goal
Fix critical regressions in the regularization manager that made it unusable:
1. **Performance Bug**: 614,297+ function calls causing complete UI blocking (beachballs, picker corruption)
2. **Model Year Regression**: Showing 20 years from canonical hierarchy instead of actual uncurated years
3. **Status Computation Bug**: Status showing "Complete" when years with "Not Assigned" fuel types exist

### User Impact
- **Before**: Regularization UI completely frozen when filtering by vehicle type
- **Before**: Showing wrong number of model years (20 canonical vs 22 actual)
- **Before**: Misleading "Complete" status when work remains

### Session Scope
This session focused on three interconnected bugs discovered during testing:
- Massive performance regression from vehicle type filter
- UI showing incorrect model year counts
- Status badges not reflecting actual completion state

---

## 2. Progress Completed

### ✅ Critical Performance Fix (614k+ call elimination)

**Problem**: Vehicle type filter in `RegularizationView.swift:141` called `getWildcardMapping(for:)` for every pair on every SwiftUI re-render.

**Root Cause**:
```swift
// BEFORE (line 141) - BROKEN
let wildcardMapping = viewModel.getWildcardMapping(for: pair)  // Called 614k+ times!
```

**Solution**: Implemented **integer enumeration caching** (core architecture pattern):

1. **Added `vehicleTypeId: Int?` to `UnverifiedMakeModelPair`** (`DataModels.swift:1858`)
   - Cached vehicle type ID from wildcard mapping
   - Populated during pair creation (one-time cost)

2. **Updated cache table schema** (`DatabaseManager.swift:908-920`)
   ```sql
   CREATE TABLE uncurated_pairs_cache (
       ...
       vehicle_type_id INTEGER,
       FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_type_enum(id)
   )
   ```

3. **Changed filter from string codes to integer IDs** (`RegularizationView.swift:140-150`)
   ```swift
   // AFTER - FAST
   if selectedId == -1 {
       return pair.vehicleTypeId == nil  // Instant integer comparison
   }
   return pair.vehicleTypeId == selectedId
   ```

4. **Updated picker to use integer IDs** (`RegularizationView.swift:83, 283-304`)
   - Changed `selectedVehicleTypeFilter: Int?` (was `String?`)
   - Uses `-1` as sentinel for "Not Assigned"

**Result**: Filter now executes instant integer comparisons instead of 614k+ method calls.

**Cache Invalidation Required**:
```bash
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "DELETE FROM uncurated_pairs_cache; DELETE FROM regularization_cache_metadata WHERE cache_name='uncurated_pairs';"
```

### ✅ Form Reversion Bug Fix

**Problem**: After saving vehicle type, picker reverted to "Not Assigned" because code searched in `model.vehicleTypes` (only types in curated data for that specific model).

**Location**: `RegularizationView.swift:1723`

**Solution**: Changed lookup to use `allVehicleTypes` (all 13 types from schema), allowing assignment of types that don't appear in curated years.

### ✅ Architecture Consistency (Integer Enumeration)

**Problem**: Initial fix used `vehicle_type_code TEXT`, violating core architecture pattern.

**Solution**: Updated to use integer enumeration throughout:
- `RegularizationMapping`: Added `fuelTypeId: Int?` and `vehicleTypeId: Int?`
- `getAllMappings()`: SELECT both IDs and descriptions
- Form picker: Uses integer IDs for tags/comparison
- Filter: Uses integer comparison

### ✅ Model Year Display Fix (Hybrid Approach - Option 3)

**Problem**: UI showed 20 model years from canonical hierarchy (2011-2022 curated data) instead of the 22 years that actually exist in uncurated data (2023-2024) for SKIDO/EXPED.

**Root Cause**:
- UI displayed `model.modelYearFuelTypes.keys` (from canonical hierarchy)
- Didn't query which model years actually exist in uncurated dataset

**Solution Implemented** (Option 3 - Hybrid):

1. **New Database Query** (`RegularizationManager.swift:109-160`)
   ```swift
   func getModelYearsForUncuratedPair(makeId: Int, modelId: Int) async throws -> [Int]
   ```
   - Queries distinct model years for make/model in uncurated registration years
   - Returns only years that actually exist (e.g., [2004, 2005, ..., 2025])

2. **UI State** (`RegularizationView.swift:950-952`)
   ```swift
   @Published var uncuratedModelYears: [Int] = []
   ```
   - Loaded when pair selected
   - Cleared when form cleared

3. **Smart Fuel Type Options** (`RegularizationView.swift:875-883`)
   - **If year exists in canonical** (2004-2023): Shows specific fuel types from curated data
   - **If year NOT in canonical** (2024, 2025): Shows ALL fuel types from schema
   - User can always select "Unknown" or "Not Assigned"

4. **New `getAllFuelTypes()` Function** (`RegularizationManager.swift:1512-1558`)
   ```sql
   SELECT id, code, description FROM fuel_type_enum WHERE code != 'NS'
   ```
   - Loaded at startup into `allFuelTypes`
   - Used for model years that don't exist in canonical hierarchy

**Result**:
- Shows correct count (22 of 22 years for SKIDO/EXPED)
- 2025 model years show all fuel options including "Electric"
- Future-proof for new fuel types

### ✅ Status Computation Fix

**Problem**: Status showed "Complete" when 2024 and 2025 had "Not Assigned" fuel types.

**Root Cause**: Status extracted model years from **existing triplet mappings**, missing years without triplets yet.
```swift
// BEFORE - WRONG
let uncuratedModelYears = Set(triplets.compactMap { $0.modelYear }).sorted()
// Only checks years that already have triplets!
```

**Solution**: Query database for ALL uncurated model years (same as UI does).

**Implementation** (`RegularizationManager.swift:584-657`):
1. Made function `async` to allow database query
2. Extract make/model IDs from key
3. Call `getModelYearsForUncuratedPair()` to get ALL years
4. Check each year (including ones without triplets yet)

**Structural Change**:
- Moved status computation AFTER database query completes (was inside sync continuation)
- Load mappings once, then compute status for all pairs asynchronously

**Result**: SKIDO/EXPED now shows "Partial" (not "Complete") because 2024/2025 missing fuel types.

---

## 3. Key Decisions & Patterns

### A. Option 3 (Hybrid Approach) for Fuel Type Options

**Decision**: Show different fuel type options based on whether model year exists in canonical hierarchy.

**Rationale**:
- Years in canonical (2020-2023): Show specific types that exist for this model (helps user understand valid options)
- Years NOT in canonical (2024-2025): Show ALL types from schema (handles new fuel types like "Electric" that didn't exist in older data)

**Edge Case Handled**: A 2025 electric model year that never appeared in 2011-2022 canonical data will still show "Electric" as an option.

### B. Integer Enumeration Pattern (Core Architecture)

**Principle**: All categorical data uses integer enumeration, never string comparisons.

**Applied To**:
- Vehicle type IDs (not codes)
- Fuel type IDs (not descriptions)
- Dictionary lookups
- Picker selections

**Benefits**:
- Fast integer comparison
- Foreign key constraints
- Avoid SwiftUI Picker equality issues with structs

### C. Async Status Computation After Query

**Pattern**: Separate database query (sync in continuation) from status computation (async with DB lookups).

```swift
// 1. Query pairs (sync)
var pairs = try await withCheckedThrowingContinuation { ... }

// 2. Compute status (async - can call DB)
for i in 0..<pairs.count {
    let status = await computeRegularizationStatus(...)
    pairs[i].regularizationStatus = status
}
```

**Reason**: Status computation now needs to query database for model years, can't be done inside sync continuation.

### D. Double-Optional Handling

**Pattern**: Dictionary keys are `Int?`, so `.first` returns `Int??`.

```swift
// Wrong:
let yearId = model.modelYearFuelTypes.keys.first { ... }  // Returns Int??

// Correct:
let foundYearId = model.modelYearFuelTypes.keys.first { ... }
return foundYearId.flatMap { $0 }  // Unwrap to Int?
```

**Applied In**:
- `FuelTypeYearSelectionView.filteredYears`
- `ModelYearFuelTypeRow.yearId`

---

## 4. Active Files & Locations

### Modified Code Files

1. **`SAAQAnalyzer/Models/DataModels.swift`**
   - Line 1858: Added `vehicleTypeId: Int?` to `UnverifiedMakeModelPair`
   - Line 1816-1818: Added `fuelTypeId`, `vehicleTypeId` to `RegularizationMapping`

2. **`SAAQAnalyzer/DataLayer/RegularizationManager.swift`**
   - Lines 109-160: New `getModelYearsForUncuratedPair()` function
   - Lines 1512-1558: New `getAllFuelTypes()` function
   - Lines 584-657: Modified `computeRegularizationStatus()` (now async, queries DB)
   - Lines 506-516: Removed vehicleTypeId extraction from sync query (moved to async section)
   - Lines 546-577: Added async status computation loop after query
   - Lines 754-781: Updated `getAllMappings()` SQL to include fuel_type_id, vehicle_type_id
   - Lines 804-833: Updated result processing to extract IDs

3. **`SAAQAnalyzer/DataLayer/DatabaseManager.swift`**
   - Lines 908-920: Updated `uncurated_pairs_cache` schema (added vehicle_type_id)
   - Lines 5936-5964: Updated INSERT statement for cache (10 columns now)
   - Lines 5997-6037: Updated SELECT statement for cache loading

4. **`SAAQAnalyzer/UI/RegularizationView.swift`**
   - Line 83: Changed `selectedVehicleTypeFilter: Int?` (was `String?`)
   - Line 946: Changed `selectedVehicleTypeId: Int?` (was `selectedVehicleType: VehicleTypeInfo?`)
   - Line 952: Added `uncuratedModelYears: [Int]`
   - Line 938: Added `allFuelTypes: [MakeModelHierarchy.FuelTypeInfo]`
   - Lines 140-150: Updated filter logic (integer comparison)
   - Lines 283-304: Updated picker (integer tags)
   - Lines 678-705: Updated form picker (integer IDs)
   - Lines 1656-1677: Load uncurated model years when pair selected
   - Lines 1713-1725: Fixed form loading (use integer ID, not description)
   - Lines 777-859: Rewrote `FuelTypeYearSelectionView` (show uncurated years)
   - Lines 857-932: Rewrote `ModelYearFuelTypeRow` (hybrid fuel type options)
   - Lines 1340-1344: Updated surgical status update (now async)

### Supporting Changes

5. **Cache Invalidation**
   - User must delete cache after schema change
   - OR app handles it automatically (might show error, then work)

---

## 5. Current State

### ✅ Working Features

1. **Performance**: Vehicle type filter works without UI blocking
2. **Model Year Display**: Shows correct count (22 of 22 for SKIDO/EXPED)
3. **Fuel Type Options**: 2024/2025 show all schema types (including future types like "Electric")
4. **Status Badge**: SKIDO/EXPED shows "Partial" (not "Complete")
5. **Picker Persistence**: Vehicle type selection no longer reverts after save

### ⚠️ Remaining Bugs (CRITICAL)

#### Bug 1: Green Checkmark Displays Incorrectly

**Location**: `RegularizationView.swift` - "4. Select Fuel Type by Model Year" section header

**Problem**: Green checkmark shows even though 2024 and 2025 have "Not Assigned" values.

**Likely Cause**: `allFuelTypesAssigned(for: model)` function checks `model.modelYearFuelTypes` (canonical years only), not `uncuratedModelYears`.

**Fix Needed**: Update checkmark logic to check ALL uncurated model years (not just canonical years).

```swift
// Current (wrong):
if viewModel.allFuelTypesAssigned(for: model) {  // Only checks canonical years
    Image(systemName: "checkmark.circle.fill")
}

// Should check:
let allUncuratedYearsAssigned = viewModel.uncuratedModelYears.allSatisfy { modelYear in
    // Find yearId for this model year
    // Check if fuel type is assigned (not nil, not -1 for partial assignments)
}
```

#### Bug 2: Radio Buttons Don't Work for 2024/2025

**Location**: `RegularizationView.swift:896-932` - `ModelYearFuelTypeRow`

**Problem**: Clicking radio buttons for 2024 and 2025 model years doesn't select them.

**Root Cause**: `yearId` is `nil` for years not in canonical hierarchy (2024, 2025 don't exist in 2011-2022 curated data).

```swift
private var yearId: Int? {
    // Searches model.modelYearFuelTypes for modelYear
    // Returns nil for 2024/2025 (not in canonical)
}
```

Radio button actions check `if let yearId = yearId` and do nothing when nil.

**Fix Needed**:
1. Create yearId entries on-the-fly for non-canonical years
2. OR store selections by model year (Int) instead of yearId (Int?)
3. OR add logic to save triplets with model_year looked up from `model_year_enum` table

**Recommended Approach**: Store selections by model year value (not yearId), then lookup/create yearId when saving.

---

## 6. Next Steps (Priority Order)

### Priority 1: Fix Radio Button Selection for Non-Canonical Years

**Task**: Make radio buttons work for 2024/2025 model years.

**Approach**:
1. Change `selectedFuelTypesByYear` dictionary key from `yearId: Int` to `modelYear: Int`
2. Update all getter/setter functions to work with model year values
3. When saving, lookup yearId from `model_year_enum` table (or create if doesn't exist)

**Files to Modify**:
- `RegularizationView.swift`: Change dictionary type, update getters/setters
- May need to add helper function to resolve model year → yearId

### Priority 2: Fix Green Checkmark Logic

**Task**: Update checkmark to check uncurated model years (not canonical years).

**Approach**:
1. Find `allFuelTypesAssigned(for: model)` function
2. Replace with logic that checks `uncuratedModelYears`
3. For each uncurated year, verify fuel type is assigned

**Files to Modify**:
- `RegularizationView.swift`: Update checkmark condition

### Priority 3: Testing & Validation

**Test Cases**:
1. SKIDO/EXPED should show 22 years
2. All radio buttons should work (including 2024, 2025)
3. Assigning fuel types to all years should make checkmark appear
4. Saving should update status to "Complete"
5. Status should change back to "Partial" if any year set to "Not Assigned"

### Priority 4: Performance Validation

**Verify**:
- No beachballs when filtering by vehicle type
- Picker selections work smoothly
- Form loads quickly

---

## 7. Important Context

### A. Errors We Solved

1. **Incorrect argument labels in FuelTypeInfo initializer**
   - Issue: Wrong parameter order (had `modelYear` before `recordCount`)
   - Fix: Use correct order: `id, code, description, recordCount, modelYearId, modelYear`

2. **Swift 6 concurrency - explicit self in async closures**
   - Issue: `self.uncuratedModelYears` in async closure
   - Fix: Add explicit `self.` in all async closures

3. **Double-optional unwrapping**
   - Issue: Dictionary keys are `Int?`, `.first` returns `Int??`
   - Fix: Use `.flatMap { $0 }` to unwrap

4. **Cannot call async function inside sync continuation**
   - Issue: `await computeRegularizationStatus()` inside `withCheckedThrowingContinuation`
   - Fix: Compute status AFTER continuation completes

5. **Immutable let constant**
   - Issue: `let pairs` can't be mutated
   - Fix: Change to `var pairs`

6. **Invalid redeclaration of mappingsDict**
   - Issue: Declared mappingsDict twice (before continuation and after)
   - Fix: Load once before continuation, reuse in status loop

### B. Dependencies Added

1. **New Database Function**: `getModelYearsForUncuratedPair()`
   - Queries distinct model years for make/model in uncurated data
   - Used by both UI and status computation

2. **New Schema Function**: `getAllFuelTypes()`
   - Loads all fuel types from schema (not just those in canonical hierarchy)
   - Used for non-canonical model years (2024, 2025, etc.)

3. **UI State**: `uncuratedModelYears: [Int]`
   - Populated when pair selected
   - Drives fuel type year list

4. **UI State**: `allFuelTypes: [MakeModelHierarchy.FuelTypeInfo]`
   - Loaded at startup
   - Used for years not in canonical hierarchy

### C. Gotchas Discovered

1. **Year ID vs Model Year Confusion**
   - `yearId`: Integer ID from `model_year_enum` table (used in canonical hierarchy)
   - `modelYear`: Actual year value (2024, 2025, etc.)
   - Non-canonical years don't have yearId entries yet

2. **Canonical Hierarchy Only Contains Curated Years**
   - Built from 2011-2022 data only
   - Doesn't include 2024, 2025 even though they exist in uncurated data
   - Must query database separately for uncurated model years

3. **Status Computation Timing**
   - Can't be done inside sync continuation anymore
   - Requires database query (async)
   - Must happen AFTER pairs are loaded

4. **SwiftUI Picker Equality**
   - Comparing structs fails when different instances (even with same IDs)
   - Must use simple types (Int, String) for tags
   - Integer enumeration pattern solves this

5. **Cache Schema Changes Require Invalidation**
   - Adding `vehicle_type_id` column requires cache rebuild
   - App may crash or show errors if cache schema doesn't match
   - User must delete cache or app handles gracefully

### D. Testing Notes from User

**Console Output When Selecting SKIDO/EXPED**:
```
Found 22 distinct model years for makeId=16 modelId=257 in uncurated years: [2004, 2005, ..., 2025]
Loaded 22 uncurated model years: [2004, 2005, ..., 2025]
```

**SQL Query Confirmation**:
```sql
-- Returns 22 rows for SKIDO/EXPED in 2023-2024 registration data
SELECT DISTINCT my.year FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
JOIN model_year_enum my ON v.model_year_id = my.id
WHERE make.name = 'SKIDO' AND model.name = 'EXPED'
AND y.year IN (2023, 2024) AND my.year IS NOT NULL
```

**Observed Behavior**:
- ✅ List shows 22 years correctly
- ✅ Status badge shows "Partial"
- ✅ Vehicle type shows "MN - Snowmobile" (no longer reverts)
- ⚠️ Green checkmark appears even with "Not Assigned" years
- ⚠️ Can't select radio buttons for 2024/2025

### E. Architecture Notes

**Core Pattern: Integer Enumeration**
- All categorical data (vehicle type, fuel type, etc.) uses integer IDs
- Descriptions are for display only
- Database foreign keys enforce referential integrity
- Filters and comparisons use integers (fast)

**Data Flow**:
1. User selects uncurated pair
2. Query database for model years in uncurated data
3. For each year, look up fuel type options:
   - If year in canonical: use specific options from curated data
   - If year not in canonical: use all options from schema
4. User assigns fuel types
5. Save creates triplet mappings (make/model/modelyear/fueltype)
6. Status recomputed by checking ALL uncurated model years

**Canonical Hierarchy Purpose**:
- Provides reference data (what fuel types are valid for each year)
- Built from curated years (2011-2022)
- NOT a complete list of all years that exist in uncurated data
- Must query database separately for uncurated model years

---

## 8. Command Reference

### View Current State
```bash
git status
git log --oneline -5
git diff HEAD
```

### Test Database Queries
```bash
# Get model years for SKIDO/EXPED
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite "
SELECT DISTINCT my.year FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
JOIN model_year_enum my ON v.model_year_id = my.id
JOIN make_enum mk ON v.make_id = mk.id
JOIN model_enum md ON v.model_id = md.id
WHERE mk.name = 'SKIDO' AND md.name = 'EXPED'
AND y.year IN (2023, 2024)
ORDER BY my.year;
"

# Check cache schema
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "PRAGMA table_info(uncurated_pairs_cache);"
```

### Clear Cache (if needed)
```bash
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "DELETE FROM uncurated_pairs_cache;
   DELETE FROM regularization_cache_metadata WHERE cache_name='uncurated_pairs';"
```

---

## 9. Quick Start for Next Session

1. **Read this document** (all necessary context included)
2. **Current state**: Two bugs remaining (checkmark, radio buttons)
3. **Start here**: Fix radio button selection for 2024/2025 model years
4. **Key insight**: yearId is nil for non-canonical years - need to handle this case
5. **Files to modify**: `RegularizationView.swift` (change selectedFuelTypesByYear dictionary key type)

---

**Session End**: October 21, 2025
**Ready for**: Radio button fix implementation
**Blocked on**: Nothing - clear path forward
**Risk**: Low - well-understood problem with clear solution
**Estimated Effort**: 1-2 hours to fix both remaining bugs
