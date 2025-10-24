# ModelYear Triplet Regularization - Phase 2 Implementation Session

**Date**: October 9, 2025
**Status**: Phase 2A Complete, Phase 2B Implemented but Not Working
**Branch**: `rhoge-dev`

---

## 1. Current Task & Objective

### Primary Goal
Implement **Model Year-aware triplet regularization** to enable year-specific fuel type disambiguation for Make/Model pairs in the SAAQ vehicle data regularization system.

### Problem Being Solved
**Original Issue**: The pair-based regularization system (Make/Model only) cannot distinguish fuel types that vary by model year.

**Example**: HONDA CIVIC in canonical data has:
- 2011-2014: Gasoline only
- 2016-2019: Gasoline + Hybrid
- 2020-2022: Gasoline + Hybrid + Electric

With pair-based system → FuelType = NULL (ambiguous)
With triplet system → 2011-2014 can auto-assign FuelType = Gasoline

**Expected Impact**: 3-4x improvement in FuelType auto-assignment rates (from ~10-20% to ~40-60%)

---

## 2. Progress Completed

### ✅ Phase 1 Complete (Previous Session)
- Database schema updated to support triplets
- `make_model_regularization` table now has `model_year_id` column (nullable)
- `UNIQUE(uncurated_make_id, uncurated_model_id, model_year_id)` constraint
- Core functions updated: `saveMapping()`, `getAllMappings()`, `calculateRecordCount()`
- Data model `RegularizationMapping` updated with `modelYearId` and `modelYear` fields

### ✅ Phase 2A Complete (This Session)
**Canonical Hierarchy Generation with ModelYear Grouping**

**File**: `RegularizationManager.swift` (lines 87-255)

1. **Updated SQL Query** (lines 111-135):
   - Added `model_year_id` and `model_year` to SELECT
   - Added `LEFT JOIN model_year_enum my ON v.model_year_id = my.id`
   - Changed GROUP BY to: `mk.id, md.id, my.id, ft.id, vt.id`

2. **Updated Row Extraction** (lines 151-168):
   - Now extracts `modelYearId` and `modelYear` from result set
   - Column indices shifted (modelYear columns at positions 4-5)

3. **New Temporary Storage Structure** (line 149):
   ```swift
   var makesDict: [Int: (
       name: String,
       models: [Int: (
           name: String,
           modelYearFuelTypes: [Int?: [FuelTypeInfo]],
           vehicleTypes: [VehicleTypeInfo]
       )]
   )]
   ```

4. **FuelType Grouping by ModelYear** (lines 180-200):
   - FuelTypes now stored in dictionary keyed by `modelYearId`
   - Each model year can have different fuel types
   - VehicleTypes remain ungrouped (apply to all years)

5. **Updated Data Models** (`DataModels.swift` lines 1712-1742):
   - `MakeModelHierarchy.Model` now has `modelYearFuelTypes: [Int?: [FuelTypeInfo]]`
   - Added backward-compatible computed property `fuelTypes` (deduplicates across years)
   - `FuelTypeInfo` now includes `modelYearId: Int?` and `modelYear: Int?`

6. **Compilation Fixes** (`RegularizationView.swift`):
   - Fixed missing parameters in `FuelTypeInfo` initializers (lines 532-539, 1052-1059)
   - Removed incorrect `await` from synchronous `setYearConfiguration()` call (line 656)

### ✅ Phase 2B Implemented (This Session)
**Auto-Regularization Logic with Triplet Creation**

**File**: `RegularizationView.swift` (lines 878-989)

**New Two-Step Strategy**:

1. **STEP 1: Create Triplet Mappings** (lines 928-945)
   - Analyzes `canonicalModel.modelYearFuelTypes` dictionary
   - For each model year with exactly ONE valid fuel type → creates triplet
   - Sets `modelYearId` = specific year ID
   - Sets `vehicleTypeId` = nil (will inherit from wildcard)

2. **STEP 2: Create Wildcard Pair Mapping** (lines 947-961)
   - Creates ONE mapping with `modelYearId = NULL`
   - Assigns VehicleType using cardinal type matching
   - Optionally assigns FuelType if ALL years have same single fuel type

**Example Output**:
```
✓ Triplet: ModelYear 2011 → FuelType=E
✓ Triplet: ModelYear 2012 → FuelType=E
✓ Triplet: ModelYear 2013 → FuelType=E
✓ Wildcard: (all years) → VehicleType=AU
✅ Auto-regularized: HONDA/CIVIC [M/M, FuelType(3 triplets), VehicleType]
```

---

## 3. Key Decisions & Patterns

### Architectural Patterns

1. **Wildcard vs Triplet Strategy**:
   - **VehicleType**: Use wildcards (`model_year_id = NULL`) - consistent across years
   - **FuelType**: Use triplets (`model_year_id = <specific year>`) - varies by model year

2. **Hierarchical Fallback** (Not Yet Implemented):
   - Query should try exact triplet match first
   - Fall back to pair match if no triplet exists
   - Pattern: `WHERE (make_id = X AND model_id = Y AND model_year_id = Z) OR (make_id = X AND model_id = Y AND model_year_id IS NULL)`

3. **Backward Compatibility**:
   - Legacy `fuelTypes` computed property on `Model` struct
   - Allows existing code to work without changes
   - Deduplicates fuel types across all years

4. **NULL Semantics**:
   - `model_year_id = NULL` → Wildcard (applies to all years)
   - `fuel_type_id = NULL` → User couldn't disambiguate (needs review)
   - `vehicle_type_id = NULL` → User couldn't disambiguate (needs review)

### Database Design

**Table**: `make_model_regularization`
```sql
UNIQUE(uncurated_make_id, uncurated_model_id, model_year_id)
-- Allows multiple mappings per Make/Model:
-- - 1 wildcard (model_year_id = NULL) for VehicleType
-- - N triplets (model_year_id = specific year) for FuelType
```

---

## 4. Active Files & Locations

### Core Implementation Files

1. **`RegularizationManager.swift`** (`DataLayer/`)
   - Lines 87-255: `generateCanonicalHierarchy()` - ModelYear grouping
   - Lines 297-386: `saveMapping()` - Supports triplets
   - Lines 416-526: `getAllMappings()` - Returns triplet data
   - Lines 929-989: `calculateRecordCount()` - Counts records per triplet

2. **`DataModels.swift`** (`Models/`)
   - Lines 1703-1742: `MakeModelHierarchy` structs with ModelYear support
   - Lines 1650-1683: `RegularizationMapping` with triplet fields

3. **`RegularizationView.swift`** (`UI/`)
   - Lines 827-990: `autoRegularizeExactMatches()` - Triplet auto-assignment
   - Lines 532-539, 1052-1059: FuelTypeInfo initialization fixes

### Schema Files

- **Database Schema**: Created by `RegularizationManager.createRegularizationTable()` (lines 21-65)

---

## 5. Current State - ⚠️ BROKEN

### Issue #1: Triplet Regularization Not Showing in UI

**Symptom**: After importing data and running auto-regularization:
- No indication of triplet regularization in UI
- Console doesn't show triplet creation messages

**Possible Causes**:
1. Auto-regularization not running (check console for "🔄 Generating canonical hierarchy")
2. Hierarchy generation not grouping by ModelYear correctly
3. Logic not detecting single-fuel-type years
4. Mappings created but not visible in UI

### Issue #2: VehicleType Auto-Assignment Broken

**Symptom**: Vehicle types that were assigned under pair matching are no longer matched (e.g., AU for Honda Civic)

**Root Cause Analysis**:
The new logic creates **two separate mappings**:
- Triplets with `fuel_type_id` set, `vehicle_type_id = NULL`
- Wildcard with `vehicle_type_id` set, `fuel_type_id = NULL`

**Problem**: The UI/query logic may not be combining these properly. The `getRegularizationStatus()` function (lines 967-984) checks for BOTH `fuelType` and `vehicleType` in a **single mapping row**, but now they're split across multiple rows.

### Critical Bug Found

**Location**: `RegularizationView.swift:967-984`

```swift
func getRegularizationStatus(for pair: UnverifiedMakeModelPair) -> RegularizationStatus {
    let key = "\(pair.makeId)_\(pair.modelId)"

    guard let mapping = existingMappings[key] else {
        return .none
    }

    // ⚠️ BUG: This checks a SINGLE mapping row
    // But triplets split FuelType and VehicleType across multiple rows!
    let hasFuelType = mapping.fuelType != nil
    let hasVehicleType = mapping.vehicleType != nil

    if hasFuelType && hasVehicleType {
        return .fullyRegularized
    } else {
        return .needsReview
    }
}
```

**Fix Needed**: Check for fuel types in **any** mapping (triplet or wildcard) and vehicle types in **any** mapping.

---

## 6. Next Steps (Priority Order)

### 🔴 CRITICAL - Fix Status Detection Logic

**File**: `RegularizationView.swift` (lines 967-984)

**Problem**: `getRegularizationStatus()` only checks ONE mapping row, but triplets create multiple rows.

**Solution**: Update to check ALL mappings for a Make/Model pair:

```swift
func getRegularizationStatus(for pair: UnverifiedMakeModelPair) -> RegularizationStatus {
    // Get ALL mappings for this pair (not just one)
    let pairMappings = existingMappings.values.filter {
        $0.uncuratedMakeId == pair.makeId &&
        $0.uncuratedModelId == pair.modelId
    }

    guard !pairMappings.isEmpty else {
        return .none
    }

    // Check if ANY mapping has fuel type (wildcard or triplet)
    let hasFuelType = pairMappings.contains { $0.fuelType != nil }

    // Check if ANY mapping has vehicle type (should be wildcard)
    let hasVehicleType = pairMappings.contains { $0.vehicleType != nil }

    if hasFuelType && hasVehicleType {
        return .fullyRegularized
    } else {
        return .needsReview
    }
}
```

### 🟡 HIGH - Fix Mapping Storage/Retrieval

**File**: `RegularizationView.swift` (lines 669-688)

**Current Code** (line 678):
```swift
mappingsDict[mapping.uncuratedKey] = mapping  // ⚠️ Overwrites! Only stores last mapping
```

**Problem**: Dictionary key `"\(makeId)_\(modelId)"` doesn't include ModelYear, so multiple triplets overwrite each other.

**Solution**: Change `existingMappings` to store **array of mappings per pair**:

```swift
@Published var existingMappings: [String: [RegularizationMapping]] = [:]  // Array, not single mapping

// In loadExistingMappings():
for mapping in mappings {
    let key = "\(mapping.uncuratedMakeId)_\(mapping.uncuratedModelId)"
    if existingMappings[key] == nil {
        existingMappings[key] = []
    }
    existingMappings[key]?.append(mapping)
}
```

### 🟡 HIGH - Debug Hierarchy Generation

**Verify** that `generateCanonicalHierarchy()` is actually grouping by ModelYear:

1. Add debug logging after hierarchy generation (line 242):
   ```swift
   print("✅ Generated base canonical hierarchy: \(makes.count) makes")

   // DEBUG: Print first model's fuel type structure
   if let firstMake = makes.first, let firstModel = firstMake.models.first {
       print("🔍 DEBUG - First model fuel type structure:")
       for (yearId, fuelTypes) in firstModel.modelYearFuelTypes {
           let yearStr = yearId != nil ? String(yearId!) : "NULL"
           print("   ModelYearId \(yearStr): \(fuelTypes.count) fuel types")
           for ft in fuelTypes {
               print("      - \(ft.code) (\(ft.modelYear ?? 0))")
           }
       }
   }
   ```

2. Check if `modelYearFuelTypes` dictionary has multiple keys (not just one)

### 🟢 MEDIUM - Add UI Visibility for Triplets

**Option A**: Read-only mapping list (quick fix):

Add to `MappingFormView` after step 4:

```swift
// Show existing mappings for this pair
if !viewModel.getMappingsForSelectedPair().isEmpty {
    VStack(alignment: .leading, spacing: 8) {
        Text("Existing Mappings:")
            .font(.headline)

        ForEach(viewModel.getMappingsForSelectedPair()) { mapping in
            HStack {
                if mapping.modelYearId == nil {
                    Image(systemName: "star.fill")
                    Text("All Years")
                } else {
                    Image(systemName: "calendar")
                    Text("\(mapping.modelYear ?? 0)")
                }

                if let ft = mapping.fuelType {
                    Text("FuelType: \(ft)")
                }
                if let vt = mapping.vehicleType {
                    Text("VehicleType: \(vt)")
                }
            }
            .font(.caption)
        }
    }
}
```

### 🟢 LOW - Implement Query Expansion for Triplets

**File**: `RegularizationManager.swift` (`expandMakeModelIDs()`)

**Current**: Only expands Make/Model pairs
**Needed**: Also match triplets when filtering by ModelYear

---

## 7. Important Context

### What Works
✅ Database schema supports triplets
✅ Hierarchy generation compiles and runs
✅ Auto-regularization logic compiles
✅ App builds, launches, imports, queries

### What's Broken
❌ Triplet mappings not visible in UI
❌ VehicleType auto-assignment broken (regression)
❌ Status badges not reflecting triplet state
❌ Mapping dictionary overwrites triplets (only stores last one)

### Data Files Available
- 1K-record test CSV files (per year)
- 10K and 100K record test files
- 14 years of data (2011-2024)

### Testing Pattern
1. Delete database: `find ~/Library/Containers -name "*.sqlite" -delete`
2. Import 1K CSV files via app UI
3. Open Regularization Manager
4. Check console for auto-regularization output
5. Verify status badges and mapping list

### Gotchas Discovered

1. **Column Index Shift**: Adding ModelYear columns shifted all fuel/vehicle type column indices by 2
2. **Dictionary Overwriting**: Using `makeId_modelId` as key causes triplets to overwrite each other
3. **Split Mappings**: FuelType and VehicleType now in separate rows, breaking status check logic
4. **Backward Compatibility**: The `fuelTypes` computed property works, but may not be used everywhere

### Dependencies
- Swift 6.2 (async/await, actors)
- SQLite3 (WAL mode, foreign keys enabled)
- SwiftUI (NavigationSplitView, Charts framework)

### Console Commands for Debugging

```bash
# Check database schema
sqlite3 ~/Library/Containers/.../saaq_data.sqlite \
  "SELECT sql FROM sqlite_master WHERE name='make_model_regularization';"

# View triplet mappings
sqlite3 ~/Library/Containers/.../saaq_data.sqlite \
  "SELECT model_year_id, fuel_type_id, vehicle_type_id, record_count
   FROM make_model_regularization
   ORDER BY uncurated_make_id, uncurated_model_id, model_year_id;"

# Count mappings by type
sqlite3 ~/Library/Containers/.../saaq_data.sqlite \
  "SELECT
     CASE WHEN model_year_id IS NULL THEN 'Wildcard' ELSE 'Triplet' END as type,
     COUNT(*)
   FROM make_model_regularization
   GROUP BY type;"
```

---

## Summary for Next Session

**Immediate Action Required**: Fix the mapping storage and status detection logic. The triplet system is architecturally sound but has critical bugs in how mappings are stored/retrieved from the dictionary and how status is calculated.

**Root Cause**: Triplets split FuelType and VehicleType across multiple database rows, but the UI assumes one row per Make/Model pair.

**Quick Win**: Fix `existingMappings` to be `[String: [RegularizationMapping]]` (array) and update `getRegularizationStatus()` to check across all mappings.

**Expected Outcome**: After fixes, you should see console output showing triplet creation and status badges reflecting the combined state of all mappings for a pair.
