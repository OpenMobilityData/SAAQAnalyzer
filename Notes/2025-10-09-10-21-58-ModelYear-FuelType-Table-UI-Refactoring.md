# ModelYear × FuelType Table UI Refactoring Session

**Date**: October 9, 2025
**Status**: In Progress - Core UI Implemented, Loading & Auto-Reg Remaining
**Branch**: `rhoge-dev`

---

## 1. Current Task & Objective

### Primary Goal
Refactor the Make/Model regularization UI from a **single fuel type dropdown** to a **ModelYear × FuelType table** with checkboxes, enabling granular year-specific fuel type assignments while maintaining model-level vehicle type assignments.

### Problem Being Solved
The Phase 2B triplet implementation (completed earlier today) created multiple database rows per Make/Model pair (wildcards + triplets), but the UI still used a single dropdown for fuel types. This caused:

1. **Poor UX**: Users couldn't see or select fuel types by model year
2. **Data Model Mismatch**: Database supported year-specific fuel types, but UI didn't expose this
3. **Confusing Wildcard Logic**: Auto-regularization tried to assign a wildcard fuel type when years had different options, leading to arbitrary assignments (e.g., "Gasoline" for everything)

### Architectural Vision
```
Hierarchical Model:
HONDA
  └─ CIVIC
      ├─ VehicleType: AU (model-level, one dropdown)
      └─ ModelYears (year-specific, table view):
          ├─ 2011: [✓ Gasoline]
          ├─ 2012: [✓ Gasoline]
          ├─ 2016: [✓ Gasoline] [✓ Hybrid]
          ├─ 2020: [✓ Gasoline] [✓ Hybrid] [✓ Electric]
```

**Clean separation of concerns**:
- **VehicleType** = Model-level attribute (unlikely to change - Honda Civic is always a car)
- **FuelType** = Year-specific attribute (varies systematically with model year)

---

## 2. Progress Completed

### ✅ Phase 1: ViewModel State (COMPLETE)
**File**: `RegularizationView.swift` (lines 613-664)

1. **Added new state property**:
   ```swift
   @Published var selectedFuelTypesByYear: [Int: Set<Int>] = [:]
   // Dictionary: modelYearId → Set of fuelTypeIds
   ```

2. **Added auto-clear logic**:
   ```swift
   @Published var selectedCanonicalModel: MakeModelHierarchy.Model? {
       didSet {
           // Clear fuel type selections when model changes
           if selectedCanonicalModel?.id != oldValue?.id {
               selectedFuelTypesByYear = [:]
           }
       }
   }
   ```

3. **Deprecated old property** (marked for future removal):
   ```swift
   @Published var selectedFuelType: MakeModelHierarchy.FuelTypeInfo?  // DEPRECATED
   ```

### ✅ Phase 2: Helper Methods (COMPLETE)
**File**: `RegularizationView.swift` (lines 851-891)

Added three helper methods:

```swift
// Check if specific fuel type is selected for a year
func isFuelTypeSelected(yearId: Int, fuelTypeId: Int) -> Bool

// Toggle selection of a fuel type for a specific year
func toggleFuelType(yearId: Int, fuelTypeId: Int, isSelected: Bool)

// Auto-assign fuel types for years with only ONE option
func autoAssignSingleFuelTypes()
```

### ✅ Phase 3: Table UI Component (COMPLETE)
**File**: `RegularizationView.swift` (lines 511-595)

Replaced the old fuel type dropdown (Step 4 in form) with a new table-based UI:

**Features**:
- **Scrollable table** (max height 300px) with year × fuel type grid
- **Checkbox toggles** for multiple selections per year
- **"Auto-Assign Singles" button** to auto-select years with only one fuel type
- **Filters invalid fuel types** (same logic as auto-regularization)
- **Sorted by year** (ascending, nulls last)
- **Monospaced year labels** (width: 50px) for alignment
- **Record counts** displayed next to each fuel type option

**UI Layout**:
```
┌─────────────┬──────────────────────────────────────┐
│ Model Year  │ Fuel Types (select all that apply)  │
├─────────────┼──────────────────────────────────────┤
│ 2011        │ [✓] Gasoline (15,234)               │
│ 2012        │ [✓] Gasoline (16,891)               │
│ 2016        │ [✓] Gasoline (12,456) [✓] Hybrid (2,145) │
│ 2020        │ [ ] Gasoline [ ] Hybrid [✓] Electric│
└─────────────┴──────────────────────────────────────┘
```

### ✅ Phase 4: New Save Logic (COMPLETE)
**File**: `RegularizationView.swift` (lines 800-882)

**Complete rewrite of `saveMapping()` function**:

**Old Logic** (pair-based):
```swift
// Single mapping with both FuelType and VehicleType
saveMapping(makeId, modelId, fuelTypeId, vehicleTypeId)
```

**New Logic** (triplet-based):
```swift
// STEP 1: Create ONE wildcard with VehicleType only
saveMapping(
    makeId, modelId,
    modelYearId: nil,       // Wildcard
    fuelTypeId: nil,        // NULL
    vehicleTypeId: vtId     // Assigned
)

// STEP 2: Create N triplets from table selections
for (yearId, fuelTypeIds) in selectedFuelTypesByYear {
    for fuelTypeId in fuelTypeIds {
        saveMapping(
            makeId, modelId,
            modelYearId: yearId,    // Specific year
            fuelTypeId: ftId,       // Assigned
            vehicleTypeId: nil      // NULL
        )
    }
}
```

**Console Output Example**:
```
✅ Saved wildcard mapping: HONDA/CIVIC → HONDA/CIVIC, VehicleType=Automobile
   ✓ Triplet: ModelYear 2011 → FuelType=E
   ✓ Triplet: ModelYear 2012 → FuelType=E
   ✓ Triplet: ModelYear 2016 → FuelType=E
   ✓ Triplet: ModelYear 2016 → FuelType=H
✅ Saved 4 triplet mappings for fuel types
```

---

## 3. Key Decisions & Patterns

### Architectural Patterns

1. **Wildcard vs Triplet Strategy**:
   - **VehicleType**: Stored in wildcard mapping (`model_year_id = NULL`)
   - **FuelType**: Stored in triplet mappings (`model_year_id = specific year`)
   - **Rationale**: VehicleType is consistent across years; FuelType varies by year

2. **Database Schema** (unchanged from Phase 2A):
   ```sql
   CREATE TABLE make_model_regularization (
       uncurated_make_id INTEGER NOT NULL,
       uncurated_model_id INTEGER NOT NULL,
       model_year_id INTEGER,           -- NULL = wildcard, value = triplet
       fuel_type_id INTEGER,             -- NULL in wildcard, value in triplets
       vehicle_type_id INTEGER,          -- Value in wildcard, NULL in triplets
       UNIQUE(uncurated_make_id, uncurated_model_id, model_year_id)
   );
   ```

3. **UI State Management**:
   - **Old**: `selectedFuelType: FuelTypeInfo?` (single value)
   - **New**: `selectedFuelTypesByYear: [Int: Set<Int>]` (dictionary of sets)
   - **Benefits**: Supports multiple fuel types per year, clear data structure

4. **NULL Semantics** (unchanged):
   - `model_year_id = NULL` → Wildcard (applies to all years)
   - `fuel_type_id = NULL` → User left it unassigned
   - `vehicle_type_id = NULL` → User left it unassigned (or set by triplet)

### Code Patterns

1. **Filtering Invalid Fuel Types** (consistent across UI and auto-reg):
   ```swift
   let validFuelTypes = fuelTypes.filter { fuelType in
       !fuelType.description.localizedCaseInsensitiveContains("not specified") &&
       !fuelType.description.localizedCaseInsensitiveContains("not assigned") &&
       !fuelType.description.localizedCaseInsensitiveContains("non spécifié")
   }
   ```

2. **Year Sorting** (nil last):
   ```swift
   let sortedYears = model.modelYearFuelTypes.keys.sorted { year1, year2 in
       guard let y1 = year1 else { return false }
       guard let y2 = year2 else { return true }
       return y1 < y2
   }
   ```

3. **Checkbox Binding Pattern**:
   ```swift
   Toggle(isOn: Binding(
       get: { viewModel.isFuelTypeSelected(yearId: yearId, fuelTypeId: fuelType.id) },
       set: { viewModel.toggleFuelType(yearId: yearId, fuelTypeId: fuelType.id, isSelected: $0) }
   ))
   ```

---

## 4. Active Files & Locations

### Primary Implementation File

**`SAAQAnalyzer/UI/RegularizationView.swift`** (1,200+ lines)

| Section | Lines | Description |
|---------|-------|-------------|
| ViewModel State | 613-664 | Published properties for form state |
| Helper Methods | 851-891 | Year-based fuel type selection logic |
| Table UI | 511-595 | ModelYear × FuelType checkbox grid |
| Save Logic | 800-882 | Creates wildcard + triplets |
| Load Logic | 1035-1156 | **NEEDS UPDATE** - populate table from DB |
| Auto-Reg Logic | 893-1010 | **NEEDS UPDATE** - remove wildcard fuel assignment |

### Supporting Files (No Changes Needed)

- **`DataLayer/RegularizationManager.swift`**: Database operations (already supports triplets)
- **`Models/DataModels.swift`**: `MakeModelHierarchy` with `modelYearFuelTypes` dictionary
- **Database Schema**: Already supports `model_year_id` column (Phase 2A)

---

## 5. Current State - In Progress

### ✅ What Works
1. **UI renders correctly**: Table displays years and fuel types with checkboxes
2. **User interactions work**: Checkboxes toggle state correctly
3. **Auto-assign button works**: Selects years with single fuel type
4. **Save creates correct mappings**: Wildcard + triplets saved to database
5. **Status badges work**: Shows green/orange/red based on combined mappings

### ⚠️ What's Broken/Incomplete

#### Issue #1: Table Not Pre-Populated from Database
**Location**: `loadMappingForSelectedPair()` (lines 1035-1156)

**Problem**: When user selects an existing pair with triplet mappings, the table checkboxes remain empty (not pre-filled).

**Current Logic**:
```swift
// Only loads fuel type from OLD dropdown (deprecated)
if let mapping = mapping, let fuelTypeName = mapping.fuelType {
    selectedFuelType = model.fuelTypes.first { $0.description == fuelTypeName }
}
```

**Needed Logic**:
```swift
// Get ALL mappings for this pair (triplets + wildcard)
let allMappings = getMappingsForPair(pair.makeId, pair.modelId)

// Populate selectedFuelTypesByYear from triplet mappings
selectedFuelTypesByYear = [:]
for mapping in allMappings {
    if let yearId = mapping.modelYearId, let fuelTypeName = mapping.fuelType {
        // Find fuel type ID from name
        if let fuelType = model.fuelTypes.first(where: { $0.description == fuelTypeName }) {
            if selectedFuelTypesByYear[yearId] == nil {
                selectedFuelTypesByYear[yearId] = []
            }
            selectedFuelTypesByYear[yearId]?.insert(fuelType.id)
        }
    }
}
```

#### Issue #2: Auto-Regularization Still Assigns Wildcard Fuel Type
**Location**: `autoRegularizeExactMatches()` (lines 960-976)

**Problem**: Lines 265-267 in the auto-reg logic still try to assign a wildcard fuel type:
```swift
let uniqueFuelTypeIds = Set(allSingleFuelTypes.compactMap { $0.first?.id })
let wildcardFuelTypeId: Int? = uniqueFuelTypeIds.count == 1 ? uniqueFuelTypeIds.first : nil
```

**Issue**: This assigns `wildcardFuelTypeId` if ALL years have the same fuel type (rare). Should ALWAYS be `nil` now.

**Fix**: Remove lines 348-351 (the wildcard fuel type calculation):
```swift
// DELETE THESE LINES:
let allSingleFuelTypes = fuelTypesByYear.values.filter { $0.count == 1 }
let uniqueFuelTypeIds = Set(allSingleFuelTypes.compactMap { $0.first?.id })
let wildcardFuelTypeId: Int? = uniqueFuelTypeIds.count == 1 ? uniqueFuelTypeIds.first : nil

// REPLACE WITH:
let wildcardFuelTypeId: Int? = nil  // FuelType ALWAYS set by triplets, not wildcard
```

---

## 6. Next Steps (Priority Order)

### 🔴 CRITICAL - Fix Load Logic (Estimated: 15 minutes)
**File**: `RegularizationView.swift` (lines 1035-1156)

**Task**: Update `loadMappingForSelectedPair()` to populate the year-based fuel type table from existing triplet mappings.

**Implementation**:
```swift
// After line 1105 (after setting selectedCanonicalModel)

// NEW CODE: Populate year-based fuel type table from triplets
selectedFuelTypesByYear = [:]
let allMappings = getMappingsForPair(pair.makeId, pair.modelId)

for mapping in allMappings {
    // Only process triplet mappings (those with model_year_id set)
    if let yearId = mapping.modelYearId,
       let fuelTypeName = mapping.fuelType {

        // Find the fuel type ID by matching description
        // Need to search within the specific year's fuel types
        if let yearFuelTypes = model.modelYearFuelTypes[yearId],
           let fuelType = yearFuelTypes.first(where: { $0.description == fuelTypeName }) {

            if selectedFuelTypesByYear[yearId] == nil {
                selectedFuelTypesByYear[yearId] = []
            }
            selectedFuelTypesByYear[yearId]?.insert(fuelType.id)
        }
    }
}
```

### 🟡 HIGH - Fix Auto-Regularization (Estimated: 5 minutes)
**File**: `RegularizationView.swift` (lines 960-976)

**Task**: Remove wildcard fuel type assignment logic.

**Change**: Replace lines 348-351 with:
```swift
// FuelType ALWAYS set by triplets, never by wildcard
let wildcardFuelTypeId: Int? = nil
```

**Also update logging** (lines 366-370):
```swift
// Remove this logging:
if wildcardFuelTypeId != nil {
    autoAssignedFields.append("FuelType(wildcard)")
}
```

### 🟢 MEDIUM - Clean Up Deprecated Code (Estimated: 10 minutes)

**Tasks**:
1. Remove `selectedFuelType` property entirely (line 659)
2. Remove old fuel type loading logic in `loadMappingForSelectedPair()` (lines 1107-1126)
3. Update `clearMappingFormFields()` to remove `selectedFuelType = nil` (line 896)

### 🟢 LOW - Testing (Estimated: 30 minutes)

**Test Plan**:
1. **Delete database**: `find ~/Library/Containers -name "*.sqlite" -delete`
2. **Import 1K CSV files** (2011-2024) via app UI
3. **Open Regularization Manager**
4. **Verify auto-regularization**:
   - Check console for triplet creation messages
   - Verify NO wildcard fuel type assignments
5. **Select Honda Civic**:
   - Table should show years 2011-2024
   - Years with single fuel type should be pre-selected
   - "Auto-Assign Singles" button should work
6. **Save mapping**:
   - Should create 1 wildcard + N triplets
   - Status badge should turn green
7. **Re-select same pair**:
   - Table checkboxes should be pre-filled from database

---

## 7. Important Context

### What We Fixed Today (Earlier Sessions)

**Session 1: Phase 2A - Database Schema & Hierarchy**
- Added `model_year_id` column to `make_model_regularization` table
- Updated `generateCanonicalHierarchy()` to group fuel types by ModelYear
- Changed `Model.fuelTypes` to `Model.modelYearFuelTypes: [Int?: [FuelTypeInfo]]`

**Session 2: Phase 2B - Bug Fixes**
- Fixed mapping storage to use arrays: `existingMappings: [String: [RegularizationMapping]]`
- Fixed `getRegularizationStatus()` to check across multiple mappings
- Added helper methods: `getMappingsForPair()`, `getWildcardMapping()`

**Session 3: UI Refactoring (This Session)**
- Replaced fuel type dropdown with year-based table
- Updated save logic to create wildcard + triplets
- **Still need**: Load logic + auto-reg fix

### Dependencies

- **Swift Version**: 6.2 (async/await, actors)
- **Frameworks**: SwiftUI, SQLite3
- **Database**: WAL mode, foreign keys enabled
- **Data Files**: 1K-record test CSV files available (per year, 2011-2024)

### Gotchas Discovered

1. **Column Index Shift**: When we added ModelYear columns to the hierarchy query, all subsequent column indices shifted by 2 (affects row extraction logic)

2. **Dictionary Key Pattern**: `existingMappings` keyed by `"\(makeId)_\(modelId)"` (no year component) because we store arrays of mappings per pair

3. **Wildcard Identification**: Wildcard mapping has `modelYearId == nil`; triplets have `modelYearId == <specific year>`

4. **Fuel Type Lookup Challenge**: When loading from database, we have fuel type **description** (string) but need to find the **ID** (integer). Must search within the specific year's fuel types: `model.modelYearFuelTypes[yearId]`

5. **Toggle State Pattern**: SwiftUI checkboxes require `Binding(get:set:)` for custom state management (can't bind directly to dictionary)

### Git Status

**Modified Files**:
```
M SAAQAnalyzer/DataLayer/RegularizationManager.swift
M SAAQAnalyzer/Models/DataModels.swift
M SAAQAnalyzer/UI/RegularizationView.swift
```

**Branch**: `rhoge-dev` (up to date with origin)

### Console Commands for Debugging

```bash
# Check database schema
sqlite3 ~/Library/Containers/*/saaq_data.sqlite \
  "SELECT sql FROM sqlite_master WHERE name='make_model_regularization';"

# View all mappings for a pair
sqlite3 ~/Library/Containers/*/saaq_data.sqlite \
  "SELECT model_year_id, fuel_type_id, vehicle_type_id, record_count
   FROM make_model_regularization
   WHERE uncurated_make_id = 123 AND uncurated_model_id = 456
   ORDER BY model_year_id;"

# Count wildcards vs triplets
sqlite3 ~/Library/Containers/*/saaq_data.sqlite \
  "SELECT
     CASE WHEN model_year_id IS NULL THEN 'Wildcard' ELSE 'Triplet' END as type,
     COUNT(*)
   FROM make_model_regularization
   GROUP BY type;"
```

---

## Expected Outcome After Completion

### User Workflow
1. **Select uncurated pair** (e.g., "HONDA / CIVIC")
2. **Form auto-populates**:
   - Make/Model dropdowns: HONDA / CIVIC
   - VehicleType dropdown: Automobile (AU)
   - Year table: Pre-filled with existing triplet selections
3. **User modifies** year-based fuel type selections (check/uncheck boxes)
4. **User clicks "Save Mapping"**
5. **Database updated**:
   - 1 wildcard row with VehicleType
   - N triplet rows with year-specific FuelTypes
6. **Status badge turns green** (fully regularized)

### Console Output Example
```
🔍 DEBUG - Verifying ModelYear-grouped FuelType structure:
   First Model: HONDA / CIVIC
   ModelYear groups: 14
      ModelYearId 157 (year: 2011): 1 fuel types - E
      ModelYearId 158 (year: 2012): 1 fuel types - E
      ModelYearId 165 (year: 2019): 2 fuel types - E, H

✅ Loaded 250 mappings (150 pairs, 100 triplets)

✅ Auto-regularized: HONDA/CIVIC [M/M, FuelType(7 triplets), VehicleType(Cardinal)]

✅ Saved wildcard mapping: HONDA/CIVIC → HONDA/CIVIC, VehicleType=Automobile
   ✓ Triplet: ModelYear 2011 → FuelType=E
   ✓ Triplet: ModelYear 2012 → FuelType=E
   ✓ Triplet: ModelYear 2016 → FuelType=E
✅ Saved 3 triplet mappings for fuel types
```

---

## File Structure Summary

```
SAAQAnalyzer/
├── DataLayer/
│   ├── RegularizationManager.swift    ✅ Phase 2A complete (ModelYear grouping)
│   ├── DatabaseManager.swift          (no changes needed)
│   └── ...
├── Models/
│   └── DataModels.swift                ✅ Phase 2A complete (modelYearFuelTypes)
├── UI/
│   └── RegularizationView.swift        ⚠️ IN PROGRESS
│       ├── Lines 613-664: ViewModel state ✅
│       ├── Lines 511-595: Table UI ✅
│       ├── Lines 800-882: Save logic ✅
│       ├── Lines 851-891: Helper methods ✅
│       ├── Lines 1035-1156: Load logic ❌ NEEDS FIX
│       └── Lines 960-976: Auto-reg ❌ NEEDS FIX
└── Notes/
    └── 2025-10-09-ModelYear-FuelType-Table-UI-Refactoring.md (this file)
```

---

## Recovery Commands

If things break during testing:

```bash
# Delete database and start fresh
find ~/Library/Containers -name "*.sqlite" -delete
find ~/Library/Containers -name "*.sqlite-shm" -delete
find ~/Library/Containers -name "*.sqlite-wal" -delete

# Check git status
git status

# Revert RegularizationView.swift if needed
git checkout -- SAAQAnalyzer/UI/RegularizationView.swift

# View recent commits
git log --oneline -10
```

---

## Summary for Next Session

**What's Done**:
- ✅ Table UI implementation (year × fuel type grid with checkboxes)
- ✅ Save logic (creates wildcard + triplets)
- ✅ Helper methods (toggle, check, auto-assign)
- ✅ ViewModel state (dictionary-based selections)

**What's Needed** (15-20 minutes total):
1. **Fix `loadMappingForSelectedPair()`**: Populate table from database triplets
2. **Fix auto-regularization**: Remove wildcard fuel type assignment
3. **Test**: Delete DB, import CSVs, verify table UI works end-to-end

**Key Insight**: The architecture is sound. We just need to wire up the "load from DB → populate table" direction. The "save from table → DB" direction already works perfectly.
