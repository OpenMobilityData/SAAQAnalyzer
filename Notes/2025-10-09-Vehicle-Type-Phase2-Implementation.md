# Vehicle Type (TYP_VEH_CATEG_USA) - Phase 2 Implementation
**Date:** October 9, 2025
**Status:** 🔄 In Progress - UI Complete, Query Support Remaining
**Related:** Follows Phase 1 (Vehicle Class terminology refactoring, commit 35bdda0)

---

## 1. Current Task & Objective

### Overall Goal
Add complete support for the TYP_VEH_CATEG_USA field as "Vehicle Type" filter in the SAAQAnalyzer application. This is Phase 2 of a two-phase refactoring:

- **Phase 1 (✅ COMPLETE):** Renamed CLAS field from "classification/Vehicle Type" → "Vehicle Class"
- **Phase 2 (🔄 IN PROGRESS):** Add TYP_VEH_CATEG_USA field as "Vehicle Type"

### Naming Convention Established
- **Vehicle Class** = CLAS field (usage-based: PAU, CAU, PMC, etc.)
- **Vehicle Type** = TYP_VEH_CATEG_USA field (physical: AU, CA, MC, HM, etc.)

### Key Schema Pattern
Following the concise naming pattern established in Phase 1:
- Table: `vehicle_type_enum` (not `vehicle_type_category_enum`)
- Column: `vehicle_type_id` (not `vehicle_type_category_id`)
- Matches pattern: `vehicle_class_enum` / `vehicle_class_id`

---

## 2. Progress Completed

### ✅ Database Schema (DatabaseManager.swift)
**Location:** `/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/DatabaseManager.swift`

1. **Created `vehicle_type_enum` table** (line ~914)
   - 16 enumeration tables total (was 15)
   - Structure: `id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, description TEXT`

2. **Added `vehicle_type_id` column to vehicles table** (line ~744)
   - Position: After `vehicle_class_id`, before `cylinder_count_id`
   - Type: `INTEGER` (TINYINT 1-byte foreign key)

3. **Created indexes for `vehicle_type_id`**
   - Single-column: `idx_vehicles_type_id` (line ~848)
   - Composite: `idx_vehicles_year_type_id` (line ~862)
   - Enum table: `idx_type_enum_code` (line ~889)

4. **Added Unknown value insert** (line ~962)
   - Code: 'AT', Description: 'Unknown'
   - Matches pattern with fuel_type_enum ('U') and vehicle_class_enum ('UNK')

### ✅ CSV Import (DatabaseManager.swift)
**Location:** Lines 4294-4321 (helper function), 4382-4479 (binding)

1. **Added `getOrCreateVehicleTypeEnumId()` helper function**
   - Pattern matches `getOrCreateClassEnumId()` and `getOrCreateFuelTypeEnumId()`
   - Inserts to `vehicle_type_enum` table with code and description
   - Returns integer ID for binding

2. **Extract TYP_VEH_CATEG_USA from CSV** (line ~4382)
   ```swift
   let vehicle_type = record["TYP_VEH_CATEG_USA"]
   ```

3. **Added vehicle_type cache** (line ~4120)
   - `var vehicleTypeEnumCache: [String: Int] = [:]`
   - Loaded from `vehicle_type_enum` table (line ~4162)

4. **Bind vehicle_type_id to INSERT statement** (lines 4454-4479)
   - Position 10 (after vehicle_class_id at position 9)
   - All subsequent positions incremented by 1 (make_id now at 11, etc.)
   - Includes hardcoded description mapping for 12 vehicle type codes

5. **Updated INSERT statement** (line ~4093)
   - Added `vehicle_type_id` column to INSERT
   - Added one more placeholder: `VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`

6. **Updated cache count logging** (line ~4376)
   - Now shows: "classes, types, makes, fuel types, municipalities"

### ✅ Enum Population (CategoricalEnumManager.swift)
**Location:** `/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/CategoricalEnumManager.swift`

1. **Added `populateVehicleTypeEnum()` function** (lines 295-326)
   - Called from `populateEnumerationsFromExistingData()` (line ~210)
   - Hardcoded 12 vehicle type codes with descriptions:
     - AB: Bus
     - AT: Unknown
     - AU: Automobile or Light Truck
     - CA: Truck or Road Tractor
     - CY: Moped
     - HM: Motorhome
     - MC: Motorcycle
     - MN: Snowmobile
     - NV: Other Off-Road Vehicle
     - SN: Snow Blower
     - VO: Tool Vehicle
     - VT: All-Terrain Vehicle
   - Also populates any additional types found in CSV data

### ✅ Data Models (DataModels.swift)
**Location:** `/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/Models/DataModels.swift`

1. **Added `vehicleTypes` property to FilterConfiguration** (line ~1105)
   ```swift
   var vehicleTypes: Set<String> = []
   ```
   - Positioned after `vehicleClasses`, before `vehicleMakes`
   - Follows same pattern as all other vehicle filters

### ✅ Filter UI (FilterPanel.swift)
**Location:** `/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/UI/FilterPanel.swift`

1. **Created `VehicleTypeFilterList` struct** (lines 1221-1387)
   - Mirrors `VehicleClassFilterList` structure exactly
   - Search field, All/Clear buttons, Show All/Less toggle
   - Special handling for NUL (empty string) → "NUL - Not Specified"
   - Special handling for AT → "AT - Unknown"
   - Display format: "AU - Automobile or Light Truck"
   - Tooltips with full descriptions

2. **Added state variable** (line ~16)
   ```swift
   @State private var availableVehicleTypes: [String] = []
   ```

3. **Updated `VehicleFilterSection`** (lines 660-708)
   - Added `selectedVehicleTypes` binding parameter
   - Added `availableVehicleTypes` parameter
   - Added Vehicle Type section after Vehicle Class (lines 695-707)
   - Section includes divider and "Vehicle Type" label

4. **Wired up VehicleFilterSection call** (lines 123-138)
   - Added `selectedVehicleTypes: $configuration.vehicleTypes`
   - Added `availableVehicleTypes: availableVehicleTypes`

5. **Data loading integration** (lines 365-378)
   - Added `async let vehicleTypes = databaseManager.getAvailableVehicleTypes()`
   - Loads in parallel with other vehicle characteristics
   - Updates `availableVehicleTypes` on main thread

6. **Mode switching cleanup** (lines 483-489, 413-418)
   - Clears `configuration.vehicleTypes` when switching to license mode
   - Clears `availableVehicleTypes` when switching to license mode

---

## 3. Key Decisions & Patterns

### Architectural Decisions

1. **Concise Naming Over Verbose**
   - **Decision:** Use `vehicle_type_enum` not `vehicle_type_category_enum`
   - **Rationale:** Matches existing pattern (`vehicle_class_enum`), avoids redundancy
   - **User feedback:** "Seems unnecessarily verbose and redundant"

2. **Separate Helper Function for CSV Import**
   - **Decision:** Created `getOrCreateVehicleTypeEnumId()` instead of reusing `getOrCreateClassEnumId()`
   - **Critical:** Initial bug mixed vehicle types into vehicle_class_enum table
   - **Fix:** Each enum type needs its own helper function with correct table name

3. **Hardcoded Descriptions in Two Places**
   - CSV Import binding (DatabaseManager.swift ~4458-4472): For INSERT operations
   - CategoricalEnumManager (~297-309): For enum table population
   - UI Display (FilterPanel.swift ~1352-1365): For user-facing labels
   - **Rationale:** No enum definition needed in DataModels.swift (unlike VehicleClass)

4. **Position in Binding Order**
   - Vehicle_type_id at position 10 (after vehicle_class_id at 9)
   - **Critical:** All subsequent bindings incremented (make_id: 10→11, model_id: 11→12, etc.)
   - Must match INSERT statement column order exactly

5. **Data Coverage**
   - TYP_VEH_CATEG_USA has 100% coverage in 2011-2022 (curated years)
   - 0% coverage in 2023-2024 (uncurated years)
   - Empty values will appear as "NUL - Not Specified" checkbox

### Coding Patterns

**Pattern 1: Enum Helper Function**
```swift
func getOrCreateVehicleTypeEnumId(code: String, description: String, cache: inout [String: Int]) -> Int? {
    if let id = cache[code] { return id }

    // INSERT OR IGNORE
    let insertSql = "INSERT OR IGNORE INTO vehicle_type_enum (code, description) VALUES (?, ?);"
    // ... execute insert ...

    // SELECT to get ID
    let selectSql = "SELECT id FROM vehicle_type_enum WHERE code = ?;"
    // ... execute select and return id ...
}
```

**Pattern 2: CSV Field Extraction and Binding**
```swift
// Extract
let vehicle_type = record["TYP_VEH_CATEG_USA"]

// Map to description
let typeDescription: String
switch vehicleTypeStr {
    case "AU": typeDescription = "Automobile or Light Truck"
    // ... other cases ...
    default: typeDescription = vehicleTypeStr
}

// Get or create enum ID and bind
if let typeId = getOrCreateVehicleTypeEnumId(code: vehicleTypeStr, description: typeDescription, cache: &vehicleTypeEnumCache) {
    sqlite3_bind_int(stmt, 10, Int32(typeId))
} else {
    sqlite3_bind_null(stmt, 10)
}
```

**Pattern 3: Special Value Display**
```swift
private func getDisplayName(for vehicleType: String) -> String {
    // NULL case
    if vehicleType.isEmpty || vehicleType.trimmingCharacters(in: .whitespaces).isEmpty {
        return "NUL - Not Specified"
    }

    // Unknown case
    if vehicleType.uppercased() == "AT" {
        return "AT - Unknown"
    }

    // Normal case: "AU - Automobile or Light Truck"
    return "\(vehicleType.uppercased()) - \(typeDescription)"
}
```

**Pattern 4: Parallel Data Loading**
```swift
async let vehicleClasses = databaseManager.getAvailableVehicleClasses()
async let vehicleTypes = databaseManager.getAvailableVehicleTypes()
async let vehicleMakes = databaseManager.getAvailableVehicleMakes()
// ... other async lets ...

let vehicleData = await (vehicleClasses, vehicleTypes, vehicleMakes, ...)
(availableClassifications, availableVehicleTypes, availableVehicleMakes, ...) = vehicleData
```

---

## 4. Active Files & Locations

### Core Data Layer
- **DatabaseManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/DatabaseManager.swift`)
  - ✅ Schema creation (tables, columns, indexes)
  - ✅ Unknown value inserts
  - ✅ CSV import helper function (`getOrCreateVehicleTypeEnumId`)
  - ✅ CSV extraction and binding
  - ⏳ **NEEDED:** `getAvailableVehicleTypes()` function (currently referenced but doesn't exist)

- **CategoricalEnumManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/CategoricalEnumManager.swift`)
  - ✅ Complete - `populateVehicleTypeEnum()` added and working

- **FilterCacheManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/FilterCacheManager.swift`)
  - ⏳ **IN PROGRESS:** Need to add `getAvailableVehicleTypes()` function
  - Should mirror `getAvailableVehicleClasses()` pattern

- **OptimizedQueryManager.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/DataLayer/OptimizedQueryManager.swift`)
  - ⏳ **PENDING:** Add vehicle_type_id filtering support to query building

### Models
- **DataModels.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/Models/DataModels.swift`)
  - ✅ Complete - `vehicleTypes: Set<String>` added to FilterConfiguration

### UI Layer
- **FilterPanel.swift** (`/Users/rhoge/Desktop/SAAQAnalyzer/SAAQAnalyzer/UI/FilterPanel.swift`)
  - ✅ Complete - `VehicleTypeFilterList` struct created
  - ✅ Complete - State variable and data loading wired up
  - ✅ Complete - Mode switching cleanup added

### Documentation
- **CLAUDE.md** (`/Users/rhoge/Desktop/SAAQAnalyzer/CLAUDE.md`)
  - ⏳ **PENDING:** Update to mention vehicle_type_enum table and vehicle_type_id column

- **README.md** (`/Users/rhoge/Desktop/SAAQAnalyzer/README.md`)
  - ⏳ **PENDING:** Update to mention Vehicle Type filter

### Reference Documents
- **Vehicle-Registration-Schema.md** (`/Users/rhoge/Desktop/SAAQAnalyzer/Documentation/Vehicle-Registration-Schema.md`)
  - Reference for TYP_VEH_CATEG_USA values and descriptions (lines 62-81)

---

## 5. Current State

### ✅ What's Working
1. **App builds successfully** - No compilation errors
2. **Database creates correctly** - 16 enum tables including vehicle_type_enum
3. **CSV import populates vehicle_type_id** - Field extracted from TYP_VEH_CATEG_USA
4. **Unknown values inserted** - AT code for vehicle_type_enum
5. **UI displays Vehicle Type section** - Appears after Vehicle Class in FilterPanel
6. **Special values render correctly** - NUL and AT/Unknown display properly

### ⚠️ What's Incomplete
1. **FilterCacheManager/DatabaseManager missing `getAvailableVehicleTypes()`**
   - Function is called from FilterPanel (line 366)
   - Function doesn't exist yet
   - **Symptom:** UI will show empty Vehicle Type section until this is added

2. **Query building doesn't filter by vehicle_type_id**
   - OptimizedQueryManager needs updates
   - Users can see Vehicle Type checkboxes but selecting them won't filter data

3. **Documentation not updated**
   - CLAUDE.md and README.md need vehicle_type references

### 🐛 Bugs Fixed During Implementation

**Bug 1: Vehicle Types Mixed Into Vehicle Classes**
- **Symptom:** UI showed "AB", "AU", "CA" codes in Vehicle Class filter section
- **Cause:** CSV import used `getOrCreateClassEnumId()` for vehicle types
- **Fix:** Created separate `getOrCreateVehicleTypeEnumId()` function
- **Location:** DatabaseManager.swift lines 4294-4321
- **Resolution:** Database rebuild required to clear mixed data

**Bug 2: Binding Position Mismatch**
- **Symptom:** Would have caused INSERT failures (caught during code review)
- **Cause:** Adding vehicle_type_id without incrementing subsequent binding positions
- **Fix:** Updated all bindings from position 11 onwards (make_id: 10→11, etc.)
- **Critical:** Positions must match INSERT column order exactly

---

## 6. Next Steps (In Order of Priority)

### Step 1: Add `getAvailableVehicleTypes()` Function
**File:** FilterCacheManager.swift or DatabaseManager.swift
**Pattern to follow:** Look at `getAvailableVehicleClasses()` implementation

Expected signature:
```swift
func getAvailableVehicleTypes() async -> [String] {
    // Query: SELECT DISTINCT code FROM vehicle_type_enum ORDER BY code
    // Return array of codes like ["AB", "AT", "AU", "CA", ...]
}
```

This will make the UI populate with actual vehicle types from the database.

### Step 2: Update OptimizedQueryManager for vehicle_type_id Filtering
**File:** OptimizedQueryManager.swift
**Pattern to follow:** Look at how vehicle_class_id filtering is implemented

Need to add:
1. WHERE clause building for `vehicle_type_id IN (...)`
2. Bind parameter handling for vehicle type filter
3. Follow same pattern as `vehicleClasses` filter

### Step 3: Test with Abbreviated CSV Files
**Action:** Delete database, reimport, verify:
1. Database creates 16 enum tables (including vehicle_type_enum)
2. Vehicle Type filter section appears with populated checkboxes
3. Selecting vehicle types filters the chart data correctly
4. NULL values (from 2023-2024) appear as "NUL - Not Specified"
5. AT unknown value appears as "AT - Unknown"

**Test database location:**
```bash
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

To delete and rebuild:
```bash
rm -rf ~/Library/Containers/com.endoquant.SAAQAnalyzer/
```

### Step 4: Update Documentation
**Files to update:**
- CLAUDE.md: Add vehicle_type_enum and vehicle_type_id to schema documentation
- README.md: Mention Vehicle Type filter in features list

### Step 5: Commit Phase 2
**Commit message pattern:**
```
Add TYP_VEH_CATEG_USA support as 'Vehicle Type' filter

- Create vehicle_type_enum table and vehicle_type_id column
- Add CSV import support for TYP_VEH_CATEG_USA field
- Implement Vehicle Type filter UI with NUL and Unknown support
- Update query building to filter by vehicle type
- Add documentation for new filtering capability

BREAKING CHANGE: Requires database rebuild
Users must delete ~/Library/Containers/com.endoquant.SAAQAnalyzer
and reimport CSV data.
```

---

## 7. Important Context

### Database Schema Details

**Enumeration Tables (16 total after Phase 2):**
1. year_enum
2. vehicle_class_enum ← Phase 1 rename (was classification_enum)
3. **vehicle_type_enum** ← **Phase 2 NEW**
4. cylinder_count_enum
5. axle_count_enum
6. color_enum
7. fuel_type_enum
8. admin_region_enum
9. age_group_enum
10. gender_enum
11. license_type_enum
12. make_enum
13. model_enum
14. model_year_enum
15. mrc_enum
16. municipality_enum

**Vehicles Table Structure (relevant columns):**
```sql
CREATE TABLE vehicles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    year INTEGER NOT NULL,
    vehicle_sequence TEXT NOT NULL,

    -- Numeric data columns
    model_year INTEGER,
    net_mass REAL,
    cylinder_count INTEGER,
    displacement REAL,
    max_axles INTEGER,

    -- Integer foreign key columns (TINYINT 1-byte)
    year_id INTEGER,
    vehicle_class_id INTEGER,       -- Phase 1 (was classification_id)
    vehicle_type_id INTEGER,        -- Phase 2 NEW
    cylinder_count_id INTEGER,
    axle_count_id INTEGER,
    original_color_id INTEGER,
    fuel_type_id INTEGER,
    admin_region_id INTEGER,

    -- Integer foreign key columns (SMALLINT 2-byte)
    make_id INTEGER,
    model_id INTEGER,
    model_year_id INTEGER,
    mrc_id INTEGER,
    municipality_id INTEGER,

    -- Optimized numeric columns
    net_mass_int INTEGER,
    displacement_int INTEGER,

    UNIQUE(year, vehicle_sequence)
);
```

### TYP_VEH_CATEG_USA Value Reference

From Vehicle-Registration-Schema.md (authoritative source):

| Code | Description |
|------|-------------|
| AB | Bus |
| AT | No specific type (for movable plates with prefix X only) |
| AU | Automobile or light truck |
| CA | Truck or road tractor |
| CY | Moped |
| HM | Motorhome |
| MC | Motorcycle |
| MN | Snowmobile |
| NV | Other off-road vehicles |
| SN | Snow blower |
| VO | Tool vehicle |
| VT | All-terrain vehicle |

**Data Coverage:**
- **2011-2022 (curated):** 100% coverage (every vehicle has TYP_VEH_CATEG_USA value)
- **2023-2024 (uncurated):** 0% coverage (partial dataset, field is NULL)

### Swift Concurrency Notes
- **Swift version:** 6.2
- **Pattern:** Use `async let` for parallel loading
- **Pattern:** Use `await MainActor.run {}` for UI updates
- **Avoid:** DispatchQueue, completion handlers, Operation

### Database Location
**Primary database:**
```
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

**Test data:**
```
~/Desktop/SAAQ_Data/Vehicle_Registration/*.csv
```

### Git Status
**Branch:** rhoge-dev
**Last Phase 1 commit:** 35bdda00502a34190598bd13262b06143d09c4f0

**Phase 2 changes (uncommitted):**
- DatabaseManager.swift: +80 lines (schema, import, helper function)
- CategoricalEnumManager.swift: +33 lines (populate function)
- DataModels.swift: +1 line (vehicleTypes property)
- FilterPanel.swift: +190 lines (VehicleTypeFilterList, wiring)
- Total: ~300 lines added across 4 files

### Configuration & Environment
- **Development:** Xcode IDE required
- **Framework:** SwiftUI (macOS 13.0+)
- **Database:** SQLite3 with WAL mode
- **Testing:** Abbreviated CSV files (1000 records per year)

### Known Limitations
1. **No enum in DataModels.swift:** Unlike VehicleClass enum, no VehicleType enum needed
2. **Hardcoded descriptions:** Type descriptions duplicated in 3 locations (CSV import, enum population, UI display)
3. **NULL handling:** 2023-2024 data will show NUL checkbox that returns 0 records
4. **AT usage:** AT/"Unknown" is for regularization system, not expected in CSV data

### Helper Queries for Verification

**Check enum tables exist:**
```sql
SELECT name FROM sqlite_master
WHERE type='table' AND name LIKE '%enum%'
ORDER BY name;
```

**Check vehicle_type_enum contents:**
```sql
SELECT * FROM vehicle_type_enum ORDER BY code;
```

**Check vehicles table structure:**
```sql
PRAGMA table_info(vehicles);
```

**Check data distribution:**
```sql
SELECT
    v.year,
    vt.code AS vehicle_type_code,
    vt.description AS vehicle_type_desc,
    COUNT(*) AS count
FROM vehicles v
LEFT JOIN vehicle_type_enum vt ON v.vehicle_type_id = vt.id
GROUP BY v.year, vt.code
ORDER BY v.year, count DESC;
```

**Check for NULL vehicle types:**
```sql
SELECT year, COUNT(*) AS null_count
FROM vehicles
WHERE vehicle_type_id IS NULL
GROUP BY year
ORDER BY year;
```

---

## Handoff Checklist

When resuming this work:

- [ ] Verify app builds successfully
- [ ] Check git status - should be on rhoge-dev branch
- [ ] Confirm database has been rebuilt after Phase 1 changes
- [ ] Review remaining tasks in order (getAvailableVehicleTypes → OptimizedQueryManager → Testing → Docs)
- [ ] Check FilterCacheManager for existing vehicle classes pattern to copy
- [ ] Remember: vehicle_type_enum uses "code" column (not "name")
- [ ] Remember: Use `vehicle_type_id` (concise) not `vehicle_type_category_id` (verbose)
- [ ] After completion: Delete database, reimport, test filtering, then commit

---

**End of Session Summary**
