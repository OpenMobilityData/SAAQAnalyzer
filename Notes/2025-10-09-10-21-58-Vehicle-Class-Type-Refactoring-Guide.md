# Vehicle Classification → Vehicle Class & Type Category Refactoring Guide

## Overview
This guide documents the systematic refactoring needed to:
1. Rename CLAS terminology from "classification" to "vehicle class"
2. Add TYP_VEH_CATEG_USA as "vehicle type category"

## Strategy
Use Xcode's Find & Replace (⌘⇧F) with **"Find > Text > Contains"** option.
Work through these replacements **in order** to avoid conflicts.

---

## Phase 1: Database Schema Changes

### Step 1.1: Table Names
**Search:** `classification_enum`
**Replace:** `vehicle_class_enum`
**Files:** All .swift files
**Notes:** This is a table name, safe to replace globally

### Step 1.2: Column Names in Schema Definition
**Search:** `classification_id INTEGER`
**Replace:** `vehicle_class_id INTEGER`
**Files:** DatabaseManager.swift
**Context:** In CREATE TABLE vehicles statement

### Step 1.3: Index Names (Single Column)
**Search:** `idx_vehicles_classification_id`
**Replace:** `idx_vehicles_vehicle_class_id`
**Files:** DatabaseManager.swift

**Search:** `idx_classification_enum_code`
**Replace:** `idx_vehicle_class_enum_code`
**Files:** DatabaseManager.swift

### Step 1.4: Composite Index Names
**Search:** `idx_vehicles_year_class_id ON vehicles(year_id, classification_id)`
**Replace:** `idx_vehicles_year_class_id ON vehicles(year_id, vehicle_class_id)`
**Files:** DatabaseManager.swift

**Search:** `idx_vehicles_municipality_class_year_id ON vehicles(municipality_id, classification_id, year_id)`
**Replace:** `idx_vehicles_municipality_class_year_id ON vehicles(municipality_id, vehicle_class_id, year_id)`
**Files:** DatabaseManager.swift

**Search:** `idx_vehicles_region_class_year_id ON vehicles(admin_region_id, classification_id, year_id)`
**Replace:** `idx_vehicles_region_class_year_id ON vehicles(admin_region_id, vehicle_class_id, year_id)`
**Files:** DatabaseManager.swift

### Step 1.5: Add Vehicle Type Category Table
**Location:** DatabaseManager.swift, in enumTables array after vehicle_class_enum
**Action:** Manually add after line with vehicle_class_enum:
```swift
// Vehicle Type Category enumeration (TYP_VEH_CATEG_USA field - physical vehicle type)
"CREATE TABLE IF NOT EXISTS vehicle_type_category_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, description TEXT);",
```

### Step 1.6: Add Vehicle Type Category Column
**Location:** DatabaseManager.swift, in CREATE TABLE vehicles
**Action:** Manually add after vehicle_class_id:
```swift
vehicle_type_category_id INTEGER,
```

### Step 1.7: Add Vehicle Type Category Indexes
**Location:** DatabaseManager.swift, after idx_vehicles_vehicle_class_id
**Action:** Manually add:
```swift
"CREATE INDEX IF NOT EXISTS idx_vehicles_vehicle_type_category_id ON vehicles(vehicle_type_category_id);",
```

**Location:** After idx_vehicles_year_class_id
**Action:** Manually add:
```swift
"CREATE INDEX IF NOT EXISTS idx_vehicles_year_type_id ON vehicles(year_id, vehicle_type_category_id);",
```

**Location:** In enumeration indexes section
**Action:** Manually add:
```swift
"CREATE INDEX IF NOT EXISTS idx_vehicle_type_category_enum_code ON vehicle_type_category_enum(code);",
```

### Step 1.8: Update Unknown Value Inserts
**Search:** `INSERT OR IGNORE INTO classification_enum`
**Replace:** `INSERT OR IGNORE INTO vehicle_class_enum`
**Files:** DatabaseManager.swift

**Action:** Manually add third Unknown insert:
```swift
"INSERT OR IGNORE INTO vehicle_type_category_enum (code, description) VALUES ('AT', 'Unknown');"
```

---

## Phase 2: SQL Query Column References

### Step 2.1: WHERE Clauses
**Search:** ` AND classification IN (`
**Replace:** ` AND vehicle_class_id IN (`
**Files:** DatabaseManager.swift
**Count:** Should find 3 occurrences

### Step 2.2: SELECT Statements
**Search:** `SELECT year, classification, admin_region, mrc`
**Replace:** `SELECT year, vehicle_class_id, admin_region_id, mrc_id`
**Files:** DatabaseManager.swift (debug query)

**Search:** `GROUP BY year, classification, admin_region, mrc`
**Replace:** `GROUP BY year, vehicle_class_id, admin_region_id, mrc_id`
**Files:** DatabaseManager.swift

**Search:** `SELECT DISTINCT classification FROM vehicles`
**Replace:** `SELECT DISTINCT vehicle_class_id FROM vehicles`
**Files:** DatabaseManager.swift

### Step 2.3: INSERT Statements
**Search:** `year_id, classification_id, make_id`
**Replace:** `year_id, vehicle_class_id, make_id`
**Files:** DatabaseManager.swift (CSV importer)

---

## Phase 3: Variable and Function Names

### Step 3.1: Cache Variables
**Search:** `classificationEnumCache`
**Replace:** `vehicleClassEnumCache`
**Files:** DatabaseManager.swift
**Count:** ~3 occurrences

### Step 3.2: Function Names
**Search:** `getAvailableClassificationItems`
**Replace:** `getAvailableVehicleClassItems`
**Files:** DatabaseManager.swift

**Search:** `getAvailableClassifications()`
**Replace:** `getAvailableVehicleClasses()`
**Files:** DatabaseManager.swift, FilterCacheManager.swift

**Search:** `getClassificationsFromDatabase`
**Replace:** `getVehicleClassesFromDatabase`
**Files:** DatabaseManager.swift

**Search:** `getOrCreateClassificationEnumId`
**Replace:** `getOrCreateVehicleClassEnumId`
**Files:** DatabaseManager.swift

### Step 3.3: Local Variables in Queries
**Search:** `for classification in filters.vehicleClassifications`
**Replace:** `for vehicleClass in filters.vehicleClassifications`
**Files:** DatabaseManager.swift
**Count:** 3 occurrences

**Then update the variable usage:**
**Search:** `bindValues.append((bindIndex, classification))`
**Replace:** `bindValues.append((bindIndex, vehicleClass))`

### Step 3.4: CSV Import Variables
**Search:** `let classification = record["CLAS"]`
**Replace:** `let vehicleClass = record["CLAS"]`
**Files:** DatabaseManager.swift

**Then update usages of this variable**

---

## Phase 4: UI String Changes

### Step 4.1: Filter Labels (CAREFUL - many "Type" strings!)
**Strategy:** Search for exact phrases to avoid false positives

**Search:** `"Vehicle Type"` (with quotes)
**Review each occurrence:**
- If related to CLAS → Replace with `"Vehicle Class"`
- If related to TYP_VEH_CATEG_USA → Leave as "Vehicle Type"
- If in RegularizationView → Change to "Vehicle Class" (it's about CLAS)

**Files to check:**
- FilterPanel.swift
- DataInspector.swift
- RegularizationView.swift

### Step 4.2: Enum Case Names
**Search:** `case vehicleClassification`
**Replace:** `case vehicleClass`
**Files:** DataModels.swift

**Search:** `case vehicleClassifications`
**Replace:** `case vehicleClasses`
**Files:** FilterPanel.swift

### Step 4.3: Comments
**Search:** `// classification_id`
**Replace:** `// vehicle_class_id`
**Files:** DatabaseManager.swift

**Search:** `Vehicle Type Classification`
**Context:** If it's about CLAS → `Vehicle Class Classification`
**Files:** Scripts (probably can leave these alone for now)

---

## Phase 5: Model and Configuration Changes

### Step 5.1: FilterConfiguration Properties
**Location:** DataModels.swift

**Search:** `var vehicleClassifications: Set<String>`
**Replace:** `var vehicleClasses: Set<String>`
**Notes:** This will require updating all references throughout codebase

### Step 5.2: Add Vehicle Type Category Property
**Location:** DataModels.swift, in FilterConfiguration
**Action:** Manually add after vehicleClasses:
```swift
var vehicleTypeCategories: Set<String> = []
```

### Step 5.3: Update FilterCategory Enum
**Location:** DataModels.swift
**Action:** Update enum:
```swift
case vehicleClass = "Vehicle Class"     // Changed from vehicleClassification
case vehicleType = "Vehicle Type"       // NEW - for TYP_VEH_CATEG_USA
```

---

## Phase 6: RegularizationManager Updates

### Step 6.1: SQL Queries
**Search:** `ft.description as fuel_type, cl.code as vehicle_type`
**Replace:** `ft.description as fuel_type, cl.description as vehicle_class`
**Files:** RegularizationManager.swift

**Search:** `vehicle_type_id`
**Replace:** `vehicle_class_id`
**Files:** RegularizationManager.swift
**Notes:** Only in make_model_regularization table references

### Step 6.2: Column References
**Search:** `classification_enum`
**Replace:** `vehicle_class_enum`
**Files:** RegularizationManager.swift

---

## Phase 7: CategoricalEnumManager Updates

### Step 7.1: Function Names
**Search:** `populateClassificationEnum`
**Replace:** `populateVehicleClassEnum`
**Files:** CategoricalEnumManager.swift

### Step 7.2: Table References
**Search:** `classification_enum`
**Replace:** `vehicle_class_enum`
**Files:** CategoricalEnumManager.swift

### Step 7.3: Add Vehicle Type Category Population
**Location:** CategoricalEnumManager.swift
**Action:** Add new function after populateVehicleClassEnum:
```swift
func populateVehicleTypeCategoryEnum() async throws {
    // Implementation similar to populateVehicleClassEnum
    // Enumerate TYP_VEH_CATEG_USA from vehicles table
}
```

### Step 7.4: Add Hardcoded Values Arrays
**Action:** Add hardcoded arrays similar to vehicleClassCodes:
```swift
private let vehicleTypeCategoryCodes = [
    ("AB", "Bus"),
    ("AT", "Unknown"),  // Special Unknown value
    ("AU", "Automobile or Light Truck"),
    ("CA", "Truck or Road Tractor"),
    ("CY", "Moped"),
    ("HM", "Motorhome"),
    ("MC", "Motorcycle"),
    ("MN", "Snowmobile"),
    ("NV", "Other Off-Road Vehicle"),
    ("SN", "Snow Blower"),
    ("VO", "Tool Vehicle"),
    ("VT", "All-Terrain Vehicle")
]
```

---

## Phase 8: FilterCacheManager Updates

### Step 8.1: Function Names
**Search:** `getAvailableClassifications`
**Replace:** `getAvailableVehicleClasses`
**Files:** FilterCacheManager.swift

### Step 8.2: Cache Keys
**Search:** `"classifications"`
**Replace:** `"vehicle_classes"`
**Files:** FilterCacheManager.swift

### Step 8.3: Add Vehicle Type Category Support
**Action:** Add new function:
```swift
func getAvailableVehicleTypeCategories() async throws -> [FilterItem] {
    // Similar to getAvailableVehicleClasses
}
```

---

## Phase 9: OptimizedQueryManager Updates

### Step 9.1: Column References
**Search:** `classification_id`
**Replace:** `vehicle_class_id`
**Files:** OptimizedQueryManager.swift

### Step 9.2: Enum Table References
**Search:** `classification_enum`
**Replace:** `vehicle_class_enum`
**Files:** OptimizedQueryManager.swift

### Step 9.3: Add Vehicle Type Category Query Support
**Action:** Add support for filtering by vehicle_type_category_id

---

## Phase 10: CSV Importer Updates

### Step 10.1: Add TYP_VEH_CATEG_USA Column
**Location:** CSVImporter.swift (or DatabaseManager CSV import section)
**Action:** Add after CLAS field handling:
```swift
let vehicleTypeCategory = record["TYP_VEH_CATEG_USA"] ?? ""
```

### Step 10.2: Add Enum Lookup
**Action:** Similar to vehicleClass lookup:
```swift
if let typeCategoryId = getOrCreateVehicleTypeCategoryEnumId(
    code: vehicleTypeCategory,
    description: vehicleTypeCategory,  // Or lookup from hardcoded array
    cache: &vehicleTypeCategoryEnumCache
) {
    // Use in INSERT
}
```

---

## Testing Checklist

After completing refactoring:
1. ✅ Build succeeds without errors
2. ✅ Delete database container: `rm -rf ~/Library/Containers/com.endoquant.SAAQAnalyzer`
3. ✅ Import abbreviated CSV files (1000 records per year)
4. ✅ Verify enum tables exist:
   - vehicle_class_enum
   - vehicle_type_category_enum
5. ✅ Verify vehicles table has columns:
   - vehicle_class_id
   - vehicle_type_category_id
6. ✅ Verify "Unknown" values inserted:
   - vehicle_class_enum: code='UNK'
   - vehicle_type_category_enum: code='AT'
7. ✅ Test filter UI shows "Vehicle Class" (not "Vehicle Type")
8. ✅ Test filtering by vehicle class works
9. ✅ Test adding vehicle type category filter to UI

---

## SQL Verification Queries

After import, run these to verify schema:

```sql
-- Check table exists
SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%vehicle%enum%';

-- Check vehicle_class_enum
SELECT * FROM vehicle_class_enum LIMIT 10;

-- Check vehicle_type_category_enum
SELECT * FROM vehicle_type_category_enum LIMIT 10;

-- Check vehicles table structure
PRAGMA table_info(vehicles);

-- Check sample data
SELECT
  v.year,
  vc.code as vehicle_class_code,
  vc.description as vehicle_class_desc,
  vt.code as vehicle_type_code,
  vt.description as vehicle_type_desc,
  COUNT(*) as count
FROM vehicles v
LEFT JOIN vehicle_class_enum vc ON v.vehicle_class_id = vc.id
LEFT JOIN vehicle_type_category_enum vt ON v.vehicle_type_category_id = vt.id
GROUP BY v.year, vc.code, vt.code
LIMIT 20;
```

---

## Notes

- **Performance**: Indexes already updated to use vehicle_class_id and vehicle_type_category_id
- **Backwards Compatibility**: None - requires database rebuild
- **Data Integrity**: TYP_VEH_CATEG_USA has 100% coverage in 2011-2022, 0% in 2023-2024
- **Unknown Values**: AT code for vehicle_type_category chosen to match existing pattern

---

## Order of Operations Summary

1. Schema changes (tables, columns, indexes)
2. SQL query updates (WHERE, SELECT, INSERT)
3. Function renames
4. Variable renames
5. UI string updates
6. Add vehicle type category support
7. Test and verify
