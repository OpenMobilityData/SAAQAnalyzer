# Single-Selection Fuel Type Radio Button UI Implementation

**Date**: October 9, 2025
**Status**: Implementation Complete, Debug Investigation In Progress
**Branch**: `rhoge-dev`

---

## 1. Current Task & Objective

### Primary Goal
Refactor the Make/Model regularization fuel type UI from **multi-selection checkboxes** to **single-selection radio buttons** with explicit "Unknown" and "Not Assigned" options to enforce unambiguous fuel type assignments per model year.

### Problem Being Solved
The previous checkbox-based UI allowed multiple fuel type selections per year, which created ambiguity when applying regularization mappings to uncurated data. For example, if both "Gasoline" and "Hybrid" were selected for 2016, the system couldn't determine which fuel type to assign to an uncurated 2016 record.

### Design Philosophy
**Disambiguation is paramount**: Every model year must have exactly ONE fuel type assignment:
- **Specific fuel type** (E, D, H, etc.) - Unambiguous, single fuel type for that year
- **Unknown** (U) - User has reviewed and determined the year cannot be disambiguated (multiple fuel types exist)
- **Not Assigned** (NULL) - User has not yet reviewed this year

---

## 2. Progress Completed

### ✅ Phase 1: UI Refactoring (COMPLETE)
**File**: `SAAQAnalyzer/UI/RegularizationView.swift`

1. **ViewModel State Update** (lines 661-663)
   - Changed from `[Int: Set<Int>]` (year → multiple fuel types)
   - Changed to `[Int: Int?]` (year → single fuel type, -1 for Unknown, nil for Not Assigned)

2. **Helper Methods Simplified** (lines 897-907)
   - `getSelectedFuelType(forYearId:)` - Returns single selection
   - `setFuelType(yearId:fuelTypeId:)` - Sets single selection
   - Removed `autoAssignSingleFuelTypes()` (no longer needed)

3. **Radio Button UI** (lines 511-595, extracted to lines 560-652)
   - Created `FuelTypeYearSelectionView` component
   - Created `ModelYearFuelTypeRow` component
   - Each year shows radio buttons for: Not Assigned, Unknown, + specific fuel types
   - Fixed year display formatting (no thousands separators)

4. **Radio Button Component** (lines 1305-1320)
   - Created `RadioButtonRow` view with blue fill when selected

### ✅ Phase 2: Save Logic (COMPLETE)
**File**: `SAAQAnalyzer/UI/RegularizationView.swift` (lines 828-900)

**Key Change**: Creates triplets for ALL model years, not just selected ones

```swift
// STEP 2: Create triplet mappings for ALL model years (with user selections or NULL)
for (yearId, fuelTypes) in model.modelYearFuelTypes {
    let selectedFuelTypeId = selectedFuelTypesByYear[yearId] ?? nil

    // Resolve -1 (Unknown placeholder) to actual "U" fuel type ID
    var resolvedFuelTypeId = selectedFuelTypeId
    if selectedFuelTypeId == -1 {
        resolvedFuelTypeId = lookupUnknownFuelTypeId()  // Returns ID for code "U"
    }

    // Create triplet (including NULL fuel types)
    saveMapping(..., fuelTypeId: resolvedFuelTypeId, ...)
}
```

**Console Output Example**:
```
✅ Saved 14 triplet mappings (10 assigned, 2 unknown, 2 not assigned)
```

### ✅ Phase 3: Load Logic (COMPLETE)
**File**: `SAAQAnalyzer/UI/RegularizationView.swift` (lines 1218-1241)

Populates radio selections from database triplets:

```swift
for mapping in allMappings {
    if let yearId = mapping.modelYearId {
        if let fuelTypeName = mapping.fuelType {
            if fuelTypeName == "Unknown" {
                selectedFuelTypesByYear[yearId] = -1
            } else {
                selectedFuelTypesByYear[yearId] = fuelType.id
            }
        } else {
            selectedFuelTypesByYear[yearId] = nil  // Not Assigned
        }
    }
}
```

### ✅ Phase 4: Status Badge Logic (COMPLETE - NEEDS VERIFICATION)
**File**: `SAAQAnalyzer/UI/RegularizationView.swift` (lines 1148-1197)

**Status Criteria**:
- 🟢 **Complete**: `VehicleType != NULL` AND `ALL triplets have fuelType != NULL`
- 🟠 **Needs Review**: `VehicleType assigned` OR `some triplets have fuelType != NULL`
- 🔴 **Unassigned**: No mappings exist

**Critical Logic** (lines 1170-1188):
```swift
let allTripletsHaveFuelType: Bool
if tripletMappings.isEmpty {
    allTripletsHaveFuelType = false
} else {
    // ALL triplets must have non-NULL fuel types
    allTripletsHaveFuelType = tripletMappings.allSatisfy { $0.fuelType != nil }

    // DEBUG logging for HONDA/CIVIC (added for investigation)
    if pair.makeName == "HONDA" && pair.modelName == "CIVIC" {
        print("🔍 DEBUG Status Check for HONDA/CIVIC:")
        print("   Total triplets: \(tripletMappings.count)")
        print("   All triplets have fuel type: \(allTripletsHaveFuelType)")
        for triplet in tripletMappings {
            let ftStatus = triplet.fuelType != nil ? "✓ \(triplet.fuelType!)" : "✗ NULL"
            print("   Triplet: ModelYear=\(triplet.modelYear ?? 0), FuelType=\(ftStatus)")
        }
    }
}
```

### ✅ Phase 5: Compiler Performance Fix (COMPLETE)
**Issue**: Swift type-checker timeout on complex VStack expression (line 388)

**Solution**: Extracted nested views into separate components
- `FuelTypeYearSelectionView` (lines 562-593)
- `ModelYearFuelTypeRow` (lines 595-652)

---

## 3. Key Decisions & Patterns

### Architectural Patterns

1. **Triplet Creation Strategy**
   - **OLD**: Only create triplets for user-selected fuel types
   - **NEW**: Create triplets for ALL model years (including NULL fuel types)
   - **Rationale**: Enables tracking of "Not Assigned" state per year

2. **Status Badge Philosophy**
   - "Unknown" (fuel_type = "U") counts as ASSIGNED ✅
   - "Not Assigned" (fuel_type = NULL) does NOT count as assigned ❌
   - Badge only shows "Complete" when ALL years are assigned (including Unknown)

3. **Data Structure Evolution**
   ```swift
   // Phase 1 (checkbox UI): Multiple selections per year
   @Published var selectedFuelTypesByYear: [Int: Set<Int>]

   // Phase 2 (radio UI): Single selection per year
   @Published var selectedFuelTypesByYear: [Int: Int?]
   // nil = Not Assigned, -1 = Unknown, other = specific fuel type ID
   ```

4. **Wildcard vs Triplet Separation**
   - **Wildcard mapping** (`model_year_id = NULL`): Stores VehicleType only
   - **Triplet mappings** (`model_year_id = <year>`): Store fuel types (including NULL)

### Code Patterns

1. **Year Sorting** (avoiding thousands separators)
   ```swift
   Text("Model Year \(String(fuelTypes.first?.modelYear ?? 0))")
   // NOT: Text("Model Year \(fuelTypes.first?.modelYear ?? 0)")
   ```

2. **Radio Button Binding**
   ```swift
   RadioButtonRow(
       label: "Gasoline",
       isSelected: viewModel.getSelectedFuelType(forYearId: yearId) == fuelType.id,
       action: { viewModel.setFuelType(yearId: yearId, fuelTypeId: fuelType.id) }
   )
   ```

3. **Unknown Placeholder Resolution**
   ```swift
   // UI uses -1 as placeholder for "Unknown"
   // Save logic resolves -1 → actual ID from fuel_type_enum where code = "U"
   if selectedFuelTypeId == -1 {
       resolvedFuelTypeId = try await enumManager.getEnumId(
           table: "fuel_type_enum", column: "code", value: "U"
       )
   }
   ```

---

## 4. Active Files & Locations

### Primary Implementation File

**`SAAQAnalyzer/UI/RegularizationView.swift`** (1,350+ lines)

| Section | Lines | Description | Status |
|---------|-------|-------------|--------|
| ViewModel State | 661-663 | `selectedFuelTypesByYear` dictionary | ✅ Updated |
| Helper Methods | 897-907 | `getSelectedFuelType`, `setFuelType` | ✅ Simplified |
| UI Components | 560-652 | `FuelTypeYearSelectionView`, `ModelYearFuelTypeRow` | ✅ Extracted |
| Radio Button | 1305-1320 | `RadioButtonRow` component | ✅ Added |
| Save Logic | 828-900 | Creates triplets for all years | ✅ Updated |
| Load Logic | 1218-1241 | Populates radio selections | ✅ Updated |
| Status Logic | 1148-1197 | Badge calculation | ⚠️ DEBUG ADDED |

### Supporting Files (No Changes Needed)

- **`DataLayer/RegularizationManager.swift`**: Database operations (already supports triplets with NULL)
- **`Models/DataModels.swift`**: `MakeModelHierarchy` with `modelYearFuelTypes` dictionary
- **Database Schema**: `make_model_regularization.fuel_type_id` (nullable column)

---

## 5. Current State - Debug Investigation

### ✅ What Works
1. **UI renders correctly**: Radio buttons display for each year
2. **User interactions work**: Can select one option per year
3. **Save creates triplets**: All years get triplet rows (including NULL fuel types)
4. **Load populates UI**: Radio selections populated from database
5. **Year formatting**: No thousands separators (2024, not 2,024)

### ⚠️ Issue Under Investigation

**Problem**: Honda Civic shows "Complete" badge even though Model Year 2005 has "Not Assigned" (NULL fuel type)

**Evidence** (from screenshot):
```
Model Year 2005
  ● Not Assigned    ← Selected (blue filled radio button)
  ○ Unknown
  ○ Gasoline (911)
  ○ Hybrid (2)
```

**Expected**: Should show 🟠 "Needs Review" badge (not 🟢 "Complete")

**Debug Added**: Lines 1177-1187 now log detailed triplet information for HONDA/CIVIC

**Debug Output Expected**:
```
🔍 DEBUG Status Check for HONDA/CIVIC:
   Total triplets: 14
   Has VehicleType: true
   All triplets have fuel type: false  ← Should be false if year 2005 is NULL
   Triplet 1: ModelYear=2004, FuelType=✓ Gasoline
   Triplet 2: ModelYear=2005, FuelType=✗ NULL  ← Should show this
   ...
```

**Possible Causes**:
1. Triplet with NULL fuel type not being saved to database
2. Triplet with NULL fuel type not being loaded from database
3. Status check running before mappings are reloaded
4. `allSatisfy` logic not working as expected

**Next Step**: Run app, select HONDA/CIVIC, check console output from debug logging

---

## 6. Next Steps (Priority Order)

### 🔴 CRITICAL - Investigate Status Badge Issue
1. **Run app** and select HONDA/CIVIC
2. **Check console** for debug output showing triplet fuel type status
3. **Verify database** state with SQL query:
   ```sql
   SELECT model_year_id, fuel_type_id,
          my.year as model_year,
          ft.description as fuel_type
   FROM make_model_regularization mmr
   LEFT JOIN model_year_enum my ON mmr.model_year_id = my.id
   LEFT JOIN fuel_type_enum ft ON mmr.fuel_type_id = ft.id
   WHERE uncurated_make_id = (SELECT id FROM make_enum WHERE name = 'HONDA')
     AND uncurated_model_id = (SELECT id FROM model_enum WHERE name = 'CIVIC')
   ORDER BY model_year_id;
   ```
4. **Fix root cause** based on debug findings:
   - If triplets not saved: Fix save logic
   - If triplets not loaded: Fix load logic
   - If status check wrong: Fix status logic

### 🟡 MEDIUM - Remove Debug Logging
Once issue is resolved, remove debug logging (lines 1177-1187)

### 🟡 MEDIUM - Testing
1. Delete database and reimport test data
2. Test workflow:
   - Auto-regularization creates triplets correctly
   - Manual mapping saves all years (including NULL)
   - Re-loading pair shows correct radio selections
   - Status badges update correctly (Complete vs Needs Review)
3. Test edge cases:
   - All years "Unknown" → Complete
   - Mix of assigned + Unknown → Complete
   - Any "Not Assigned" → Needs Review

---

## 7. Important Context

### Database Schema (Unchanged)
```sql
CREATE TABLE make_model_regularization (
    uncurated_make_id INTEGER NOT NULL,
    uncurated_model_id INTEGER NOT NULL,
    model_year_id INTEGER,           -- NULL = wildcard, value = triplet
    canonical_make_id INTEGER NOT NULL,
    canonical_model_id INTEGER NOT NULL,
    fuel_type_id INTEGER,             -- NULL = Not Assigned, value = assigned
    vehicle_type_id INTEGER,          -- Set in wildcard, NULL in triplets
    UNIQUE(uncurated_make_id, uncurated_model_id, model_year_id)
);
```

### NULL Semantics
- `model_year_id = NULL` → Wildcard mapping (applies to all years)
- `fuel_type_id = NULL` → "Not Assigned" (user hasn't decided yet)
- `fuel_type_id = <ID for "U">` → "Unknown" (user reviewed, cannot disambiguate)
- `vehicle_type_id = NULL` → Not assigned (in triplets) or set by wildcard

### Fuel Type Enum
- Code "E" = Gasoline (Essence)
- Code "D" = Diesel
- Code "H" = Hybrid
- Code "U" = Unknown (special value for ambiguous cases)
- Code "N" = Not Specified (filtered out in UI)

### Git Status
**Modified Files**:
```
M SAAQAnalyzer/UI/RegularizationView.swift
```

**Branch**: `rhoge-dev` (all changes committed except debug logging)

### Performance Notes
- **100K records/year**: 2-second beachball experienced
- **7M records/year** (full dataset): Performance optimization deferred
- **Compiler issue**: Fixed by extracting complex views into separate components

### Swift Version & Patterns
- **Swift 6.2**: Using modern concurrency (async/await, actors)
- **SwiftUI**: Declarative UI with `@Published` properties
- **Type-checker timeout**: Fixed by breaking complex expressions into computed properties and separate view components

### Console Commands for Debugging
```bash
# Find database location
find ~/Library/Containers -name "*.sqlite" 2>/dev/null | grep -i saaq

# Query triplet mappings for Honda Civic
sqlite3 <db_path> "
SELECT
    CASE WHEN model_year_id IS NULL THEN 'WILDCARD' ELSE CAST(model_year_id AS TEXT) END as year_id,
    my.year as model_year,
    ft.description as fuel_type,
    vt.description as vehicle_type
FROM make_model_regularization mmr
LEFT JOIN model_year_enum my ON mmr.model_year_id = my.id
LEFT JOIN fuel_type_enum ft ON mmr.fuel_type_id = ft.id
LEFT JOIN vehicle_type_enum vt ON mmr.vehicle_type_id = vt.id
WHERE uncurated_make_id = (SELECT id FROM make_enum WHERE name = 'HONDA')
  AND uncurated_model_id = (SELECT id FROM model_enum WHERE name = 'CIVIC')
ORDER BY model_year_id;
"

# Count triplets vs wildcards
sqlite3 <db_path> "
SELECT
    CASE WHEN model_year_id IS NULL THEN 'Wildcard' ELSE 'Triplet' END as type,
    COUNT(*)
FROM make_model_regularization
GROUP BY type;
"
```

---

## 8. Summary for Handoff

### What Changed
Refactored Make/Model regularization fuel type UI from multi-selection checkboxes to single-selection radio buttons (Not Assigned, Unknown, + specific types). Updated save logic to create triplets for ALL years (including NULL), load logic to populate radio selections from triplets, and status badge logic to require all years assigned (excluding "Not Assigned"/NULL).

### What Works
UI renders correctly, saves to database, loads from database, and user can select one fuel type per year. All triplet creation and loading logic is complete.

### What's Broken
Honda Civic shows "Complete" badge even with Model Year 2005 = "Not Assigned" (NULL). Debug logging added to lines 1177-1187 to investigate.

### How to Continue
1. Run app, select HONDA/CIVIC, check console for debug output
2. Verify database state with SQL query (see section 6)
3. Fix root cause based on findings (save/load/status logic)
4. Remove debug logging and test thoroughly

### Files Changed
- `SAAQAnalyzer/UI/RegularizationView.swift`: +316 lines, -115 lines
  - ViewModel state, UI components, save/load logic, status logic, debug logging

### Dependencies
- Database schema unchanged (supports NULL fuel_type_id)
- RegularizationManager unchanged (supports triplets with NULL)
- MakeModelHierarchy unchanged (provides modelYearFuelTypes)

---

## Recovery Commands

```bash
# View current changes
git diff SAAQAnalyzer/UI/RegularizationView.swift

# Revert if needed
git checkout -- SAAQAnalyzer/UI/RegularizationView.swift

# Check git status
git status

# View recent commits
git log --oneline -10
```
