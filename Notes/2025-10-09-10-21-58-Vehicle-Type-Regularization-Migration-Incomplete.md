# Vehicle Type Regularization Migration Session
**Date:** October 9, 2025
**Status:** ⚠️ INCOMPLETE - Query Regularization Not Working
**Branch:** rhoge-dev

---

## 1. Current Task & Objective

### Overall Goal
Migrate the Make/Model regularization system from using **vehicle_class_id** (CLAS field - usage-based classification like PAU, CAU, TAX) to **vehicle_type_id** (TYP_VEH_CATEG_USA field - physical vehicle type like AU, CA, MC).

### Background: Why This Change?
The regularization system previously used **vehicle class** (CLAS field) which is **usage-based**:
- A Honda Civic could be PAU (personal use), CAU (commercial use), or TAX (taxi)
- This created ambiguity: one Make/Model pair → multiple possible classes
- Made automatic regularization impossible for most pairs

By switching to **vehicle type** (TYP_VEH_CATEG_USA field) which is **physical**:
- A Honda Civic is ALWAYS "AU - Automobile or Light Truck"
- Eliminates ambiguity: one Make/Model pair → one vehicle type
- Enables far better automatic regularization

### Phase Context
This work follows **Phase 2** (commit a463baa) which added vehicle_type_id column to the vehicles table and full UI/filter support. Now we're adapting the regularization system to use this new field.

---

## 2. Progress Completed

### ✅ Database Schema (RegularizationManager.swift)
- **Changed** `make_model_regularization` table schema:
  - `vehicle_class_id INTEGER` → `vehicle_type_id INTEGER`
  - Foreign key now references `vehicle_type_enum` instead of `vehicle_class_enum`
- **Location:** RegularizationManager.swift lines 26-45

### ✅ Data Models (DataModels.swift)
1. **MakeModelHierarchy** struct updated (lines 1691-1723):
   - Renamed `vehicleClasses: [VehicleClassInfo]` → `vehicleTypes: [VehicleTypeInfo]`
   - Renamed struct `VehicleClassInfo` → `VehicleTypeInfo`
   - Updated comment: "VehicleClass" → "VehicleType"

2. **RegularizationMapping** model updated (line 1660):
   - Property renamed: `vehicleClass: String?` → `vehicleType: String?`

### ✅ RegularizationManager.swift - Canonical Hierarchy Query
Updated query to use `vehicle_type_enum` instead of `vehicle_class_enum`:

**Lines 106-129:** Query now joins `vehicle_type_enum`:
```swift
LEFT JOIN vehicle_type_enum vt ON v.vehicle_type_id = vt.id
```

**Lines 141-206:** Hierarchy building logic updated:
- Changed tuple structure to use `vehicleTypes: [MakeModelHierarchy.VehicleTypeInfo]`
- Variable names: `vehicleClassId` → `vehicleTypeId`, etc.
- Model creation uses `vehicleTypes` property

### ✅ RegularizationManager.swift - Save and Load Mappings
1. **saveMapping() function** (lines 378-460):
   - Parameter: `vehicleClassId: Int?` → `vehicleTypeId: Int?`
   - Comment updated: "VehicleClass" → "VehicleType"
   - SQL column: `vehicle_class_id` → `vehicle_type_id`
   - Log message: "VehicleClass" → "VehicleType"

2. **getAllMappings() query** (lines 493-589):
   - JOIN changed: `vehicle_class_enum cl` → `vehicle_type_enum vt`
   - Column alias: `vehicle_class` → `vehicle_type`
   - RegularizationMapping construction uses `vehicleType` property

### ✅ RegularizationView.swift - UI Updates
All UI elements changed from "Vehicle Class" to "Vehicle Type":

1. **Step 3 section** (lines 460-509):
   - Label: "Select Vehicle Class" → "Select Vehicle Type"
   - Picker label: "Vehicle Class" → "Vehicle Type"
   - Type changed: `MakeModelHierarchy.VehicleClassInfo` → `MakeModelHierarchy.VehicleTypeInfo`
   - Unknown code: `"UNK"` → `"AT"` (matches vehicle_type_enum)
   - Property access: `model.vehicleClasses` → `model.vehicleTypes`

2. **ViewModel properties** (line 615):
   - `selectedVehicleClass` → `selectedVehicleType`

3. **saveMapping() method** (lines 749-795):
   - Variable: `vehicleClassId` → `vehicleTypeId`
   - Enum table lookup: `vehicle_class_enum` → `vehicle_type_enum`
   - Log messages updated

4. **Auto-regularization logic** (lines 881-923):
   - Variable: `validVehicleClasses` → `validVehicleTypes`
   - Property access: `canonicalModel.vehicleClasses` → `canonicalModel.vehicleTypes`

5. **Status checking** (lines 936-954):
   - Variable: `hasVehicleClass` → `hasVehicleType`
   - Property: `mapping.vehicleClass` → `mapping.vehicleType`

6. **Mapping loader** (lines 1013-1045):
   - Reset: `selectedVehicleClass` → `selectedVehicleType`
   - Variable: `vehicleClassName` → `vehicleTypeName`
   - Type: `VehicleClassInfo` → `VehicleTypeInfo`
   - Code: `"UNK"` → `"AT"`

### ✅ RegularizationManager.swift - Vehicle Type Expansion Method (NEW)
**Added** `getUncuratedMakeModelIDsForVehicleType()` function (lines 941-987):
- Purpose: Finds uncurated Make/Model pairs mapped to a specific vehicle type
- Query: `SELECT uncurated_make_id, uncurated_model_id FROM make_model_regularization WHERE vehicle_type_id = ?`
- Returns: `(makeIds: [Int], modelIds: [Int])`
- Enables regularization queries to include uncurated records with NULL vehicle_type_id

### ✅ OptimizedQueryManager.swift - Vehicle Type Regularization
**Enhanced** regularization expansion logic (lines 185-220):
```swift
// Vehicle Type regularization: Find uncurated Make/Model pairs for selected vehicle types
if !vehicleTypeIds.isEmpty {
    var regularizedMakeIds: Set<Int> = Set(makeIds)
    var regularizedModelIds: Set<Int> = Set(modelIds)

    for vehicleTypeId in vehicleTypeIds {
        let (typeMakeIds, typeModelIds) = try await regManager.getUncuratedMakeModelIDsForVehicleType(vehicleTypeId: vehicleTypeId)
        regularizedMakeIds.formUnion(typeMakeIds)
        regularizedModelIds.formUnion(typeModelIds)
    }

    makeIds = Array(regularizedMakeIds).sorted()
    modelIds = Array(regularizedModelIds).sorted()
}
```

This logic adds uncurated Make/Model IDs to the query when filtering by vehicle type with regularization enabled.

---

## 3. Key Decisions & Patterns

### Architectural Decisions

1. **Complete Terminology Change**
   - **Decision:** Rename all "Vehicle Class" references to "Vehicle Type" in regularization
   - **Rationale:** Avoids confusion with CLAS field (now called "Vehicle Class" in main app)
   - **Scope:** Database schema, data models, UI labels, variable names, comments

2. **Unknown Value Code Change**
   - **CLAS field Unknown:** Code = "UNK"
   - **TYP_VEH_CATEG_USA Unknown:** Code = "AT"
   - **Rationale:** Matches the vehicle_type_enum table populated in Phase 2

3. **Query Regularization Strategy**
   - **Problem:** Uncurated records have NULL vehicle_type_id (2023-2024 data is partial)
   - **Solution:** When vehicle type filter active + regularization enabled:
     1. Query regularization table for Make/Model pairs mapped to selected vehicle types
     2. Add those Make/Model IDs to the query filters
     3. Records match if EITHER `vehicle_type_id` matches OR `(make_id, model_id)` matches
   - **Implementation:** New method `getUncuratedMakeModelIDsForVehicleType()` + integration in OptimizedQueryManager

### Coding Patterns

**Pattern 1: Regularization Table Query**
```swift
func getUncuratedMakeModelIDsForVehicleType(vehicleTypeId: Int) async throws -> (makeIds: [Int], modelIds: [Int]) {
    let sql = """
    SELECT DISTINCT uncurated_make_id, uncurated_model_id
    FROM make_model_regularization
    WHERE vehicle_type_id = ?;
    """
    // Returns Set<Int> converted to sorted [Int]
}
```

**Pattern 2: Query Expansion Integration**
```swift
// BEFORE Make/Model regularization, inject vehicle type regularization
if !vehicleTypeIds.isEmpty && regularizationEnabled {
    for vehicleTypeId in vehicleTypeIds {
        let (typeMakeIds, typeModelIds) = try await regManager.getUncuratedMakeModelIDsForVehicleType(vehicleTypeId: vehicleTypeId)
        makeIds.formUnion(typeMakeIds)  // Adds to existing filters
        modelIds.formUnion(typeModelIds)
    }
}
```

---

## 4. Active Files & Locations

### Core Data Layer
1. **RegularizationManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/RegularizationManager.swift`)
   - Schema creation (lines 26-45): `vehicle_type_id` column
   - Canonical hierarchy query (lines 106-231): Uses `vehicle_type_enum`
   - saveMapping (lines 378-460): Saves `vehicle_type_id`
   - getAllMappings (lines 493-589): Loads `vehicle_type`
   - **NEW:** getUncuratedMakeModelIDsForVehicleType (lines 941-987)

2. **OptimizedQueryManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/OptimizedQueryManager.swift`)
   - Vehicle type regularization expansion (lines 185-220)
   - convertFiltersToIds (lines 154-161): Converts vehicle type codes to IDs
   - Query building (lines 164-171): `vehicle_type_id IN (...)` WHERE clause

### Models
3. **DataModels.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/Models/DataModels.swift`)
   - MakeModelHierarchy (lines 1691-1742): `vehicleTypes` property, `VehicleTypeInfo` struct
   - RegularizationMapping (lines 1651-1672): `vehicleType: String?` property

### UI Layer
4. **RegularizationView.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/UI/RegularizationView.swift`)
   - Step 3 Vehicle Type section (lines 460-509): Picker UI
   - ViewModel (lines 589-1061): `selectedVehicleType` property and all logic

---

## 5. Current State: ⚠️ PROBLEM

### What's Working ✅
1. **App builds and runs** - No compilation errors
2. **Regularization UI works** - Can map uncurated Make/Model pairs to vehicle types
3. **Vehicle type filter works for curated years** (2011-2022)

### What's NOT Working ❌
**Query Regularization for Vehicle Type Filters**

**Symptom:**
- Filter by Vehicle Type "AU - Automobile or Light Truck"
- With regularization **OFF**: Returns data for 2011-2022 (curated years) ✅
- With regularization **ON**: Still returns ZERO records for 2023-2024 ❌

**Expected Behavior:**
- Many Make/Model pairs in 2023-2024 are mapped to vehicle type AU
- When regularization is ON, those uncurated records should be included
- Should see data for 2023-2024 matching the mapped Make/Model pairs

**Investigation Needed:**
1. **Verify regularization mappings exist:**
   ```sql
   SELECT COUNT(*) FROM make_model_regularization WHERE vehicle_type_id IS NOT NULL;
   ```

2. **Verify getUncuratedMakeModelIDsForVehicleType() returns IDs:**
   - Add debug logging to see if Make/Model IDs are being found
   - Check that the IDs are being added to the query

3. **Verify query logic:**
   - The vehicle type filter creates: `WHERE vehicle_type_id IN (...)`
   - The regularization should add: `OR (make_id IN (...) AND model_id IN (...))`
   - **POTENTIAL BUG:** Current implementation adds Make/Model IDs to filters, but the WHERE clause might still be `vehicle_type_id IN (...)` which excludes NULL values!

**Likely Root Cause:**
The query WHERE clause is probably:
```sql
WHERE vehicle_type_id IN (1)  -- AU
  AND make_id IN (5, 8, 12)   -- Regularized makes
  AND model_id IN (15, 23, 45) -- Regularized models
```

This will **fail** because:
- Uncurated records have `vehicle_type_id = NULL`
- NULL doesn't match `IN (1)`
- Even though make_id/model_id match, the NULL vehicle_type_id excludes them

**Fix Needed:**
Change the WHERE clause logic when regularization is enabled:
```sql
WHERE (vehicle_type_id IN (1) OR (vehicle_type_id IS NULL AND make_id IN (...) AND model_id IN (...)))
```

OR better:
```sql
WHERE (vehicle_type_id IN (1) OR (make_id, model_id) IN ((5,15), (8,23), (12,45)))
```

---

## 6. Next Steps (In Priority Order)

### IMMEDIATE: Fix Query Logic
1. **Investigate WHERE clause building** in OptimizedQueryManager
   - **File:** OptimizedQueryManager.swift
   - **Lines:** 164-171 (vehicle_type_id filter)
   - **Problem:** Need to modify logic when regularization is enabled

2. **Two possible approaches:**

   **Option A: Modify WHERE clause building** (RECOMMENDED)
   ```swift
   // In queryVehicleDataWithIntegers() around line 164
   if !filterIds.vehicleTypeIds.isEmpty {
       if regularizationEnabled && (!filterIds.makeIds.isEmpty || !filterIds.modelIds.isEmpty) {
           // Include both matching vehicle_type_id AND matching make/model with NULL vehicle_type_id
           whereClause += " AND ("
           whereClause += "vehicle_type_id IN (\(placeholders))"
           whereClause += " OR (vehicle_type_id IS NULL AND make_id IN (...) AND model_id IN (...))"
           whereClause += ")"
       } else {
           // Standard filter: just vehicle_type_id
           whereClause += " AND vehicle_type_id IN (\(placeholders))"
       }
   }
   ```

   **Option B: Remove vehicle_type_id filter when regularization enabled**
   - If regularization is ON, don't add `vehicle_type_id IN (...)` clause at all
   - Instead, rely entirely on the Make/Model IDs from regularization
   - **Drawback:** Won't filter curated records by vehicle type

3. **Add debug logging:**
   - Log when vehicle type regularization expansion happens
   - Log the Make/Model IDs being added
   - Log the final WHERE clause to verify it's correct

### TESTING:
After fixing, test with:
1. Filter: Vehicle Type = AU, Years = 2023-2024, Regularization = ON
2. Should see non-zero counts for 2023-2024
3. Verify the records match expected Make/Model pairs (Honda Civic, Toyota Corolla, etc.)

### DOCUMENTATION:
Once working, update:
- **CLAUDE.md:** Document vehicle type regularization in query system
- **Session notes:** Record the fix and final solution

---

## 7. Important Context

### Database State
- **Database location:** `~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite`
- **Regularization table:** `make_model_regularization`
  - Has `vehicle_type_id` column (NOT `vehicle_class_id`)
  - Mappings exist with vehicle types assigned
- **Vehicles table:** Has `vehicle_type_id` column
  - 2011-2022 (curated): vehicle_type_id populated (100% coverage)
  - 2023-2024 (uncurated): vehicle_type_id = NULL (0% coverage)

### Git Status
- **Branch:** rhoge-dev
- **Last commit:** a463baa (Phase 2 - Vehicle Type Filter Implementation)
- **Files changed (uncommitted):**
  - RegularizationManager.swift
  - OptimizedQueryManager.swift
  - DataModels.swift
  - RegularizationView.swift

### Known Issues
1. **Regularization query doesn't work for vehicle type filters** ⚠️ PRIMARY ISSUE
2. No other known bugs

### Dependencies
- Swift 6.2 concurrency (async/await, actors)
- SQLite3
- SwiftUI + Charts framework
- No external package dependencies

### Testing Commands
```bash
# Build the project
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -configuration Debug build

# Check database
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite

# Check regularization mappings
SELECT COUNT(*) FROM make_model_regularization WHERE vehicle_type_id IS NOT NULL;

# Check vehicle type coverage by year
SELECT y.year,
       COUNT(*) as total,
       COUNT(v.vehicle_type_id) as with_type,
       (COUNT(v.vehicle_type_id) * 100.0 / COUNT(*)) as coverage_pct
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
GROUP BY y.year
ORDER BY y.year;
```

### Critical Files NOT to Modify
- **DatabaseManager.swift:** Schema already has vehicle_type_id column (Phase 2)
- **FilterPanel.swift:** Vehicle Type filter UI already complete (Phase 2)
- **CategoricalEnumManager.swift:** vehicle_type_enum already populated (Phase 2)

---

## Handoff Summary

**What's Done:**
- ✅ Complete migration of regularization system from vehicle_class to vehicle_type
- ✅ Database schema updated
- ✅ UI updated and working
- ✅ Data models updated
- ✅ Canonical hierarchy generation using vehicle types
- ✅ Save/load mappings using vehicle types
- ✅ Query expansion logic added (but not working correctly)

**What's Broken:**
- ❌ Vehicle type filters with regularization return zero results for uncurated years
- **Root cause:** WHERE clause logic needs fixing (see Section 5)

**Next Action:**
Modify OptimizedQueryManager.swift (lines 164-171) to handle vehicle_type_id filtering when regularization is enabled. Use Option A from Section 6 to include both `vehicle_type_id IN (...)` matches AND `(vehicle_type_id IS NULL AND make/model matches)`.

**Context Window:**
- Used: ~157k/200k tokens (78%)
- Cleared after writing this summary

---

**End of Session - Ready for Handoff**
