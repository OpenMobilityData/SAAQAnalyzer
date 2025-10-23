# Road Wear Index Implementation - In Progress

**Date**: October 11, 2025
**Session Status**: ⏳ **80% COMPLETE** - Core implementation done, normalization pending
**Branch**: `rhoge-dev`
**Build Status**: ✅ **Compiles successfully** (all exhaustive switch errors fixed)

---

## 1. Current Task & Objective

### Overall Goal
Implement a new "Road Wear Index" (RWI) metric in the SAAQAnalyzer application based on the 4th power law of road wear. This metric quantifies the damage vehicles inflict on road surfaces using the engineering principle that road wear is proportional to the fourth power of axle loading.

### User Requirements
1. **Road Wear Index Metric**: Based on 4th power law (damage ∝ axle_load^4)
2. **Simplifying Assumptions**:
   - All vehicles have 2 axles
   - Weight is equally distributed across both axles
   - Formula: RWI = (mass/2)^4 per axle, total = 2 × (mass/2)^4 = mass^4 / 8
3. **User Options**:
   - **Average Mode**: Calculate average road wear index across all vehicles
   - **Sum Mode**: Calculate total road wear index across all vehicles
4. **Normalization**: Results must be normalized so the first year = 1.0 ⚠️ **NOT YET IMPLEMENTED**

### Technical Approach
- Add new `roadWearIndex` metric type to existing metrics system
- Use SQLite `POWER(net_mass, 4)` function for calculation
- Implement mode selection (average vs sum) via UI controls
- Post-process results to normalize to first year (pending)
- Only applicable to vehicle data (not license data)

---

## 2. Progress Completed

### A. Data Model Changes ✅ COMPLETE

**File**: `SAAQAnalyzer/Models/DataModels.swift`

**Changes Made**:

1. **Added `roadWearIndex` case to `ChartMetricType` enum** (lines 1305, 1316, 1329):
```swift
enum ChartMetricType: String, CaseIterable, Sendable {
    case count = "Count"
    case sum = "Sum"
    case average = "Average"
    case minimum = "Minimum"
    case maximum = "Maximum"
    case percentage = "Percentage"
    case coverage = "Coverage"
    case roadWearIndex = "Road Wear Index"  // ✅ NEW

    var description: String {
        case .roadWearIndex: return "Road Wear Index (4th Power Law)"
    }

    var shortLabel: String {
        case .roadWearIndex: return "RWI"
    }
}
```

2. **Added `RoadWearIndexMode` enum to `FilterConfiguration`** (lines 1128-1139):
```swift
struct FilterConfiguration: Equatable, Sendable {
    var roadWearIndexMode: RoadWearIndexMode = .average

    enum RoadWearIndexMode: String, CaseIterable, Sendable {
        case average = "Average"
        case sum = "Sum"

        var description: String {
            switch self {
            case .average: return "Average Road Wear Index"
            case .sum: return "Total Road Wear Index"
            }
        }
    }
}
```

3. **Added `roadWearIndexMode` property to `IntegerFilterConfiguration`** (line 1225)

4. **Updated `FilteredDataSeries.yAxisLabel`** (lines 1492-1493):
```swift
case .roadWearIndex:
    return filters.roadWearIndexMode == .average ? "Average Road Wear Index" : "Total Road Wear Index"
```

5. **Updated `FilteredDataSeries.formatValue()`** (lines 1533-1539):
```swift
case .roadWearIndex:
    // Format Road Wear Index in scientific notation for very large values
    if value > 1e15 {
        return String(format: "%.2e RWI", value)
    } else {
        return String(format: "%.0f RWI", value)
    }
```

### B. Database Query Implementation ✅ COMPLETE

**File**: `SAAQAnalyzer/DataLayer/DatabaseManager.swift`

**Changes Made**:

1. **First vehicle query switch** (lines 1203-1211):
```swift
case .roadWearIndex:
    // Road Wear Index: 4th power law based on vehicle mass
    // Assumes 2 axles with equal weight distribution
    // RWI = (mass/2)^4 per axle, so total = 2 * (mass/2)^4 = mass^4 / 8
    if filters.roadWearIndexMode == .average {
        query = "SELECT year, AVG(POWER(net_mass, 4)) as value FROM vehicles WHERE net_mass IS NOT NULL AND 1=1"
    } else {
        query = "SELECT year, SUM(POWER(net_mass, 4)) as value FROM vehicles WHERE net_mass IS NOT NULL AND 1=1"
    }
```

2. **License query switch** (lines 1505-1507):
```swift
case .roadWearIndex:
    // Road Wear Index not applicable to license data - fallback to count
    query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"
```

3. **Second vehicle query switch** (lines 1882-1890): Same as first occurrence

**SQL Logic**:
- Uses SQLite's built-in `POWER(net_mass, 4)` function
- Filters out NULL mass values with `WHERE net_mass IS NOT NULL`
- Groups by year: `GROUP BY year ORDER BY year` (added automatically)
- Mode selection determines aggregate function: `AVG()` or `SUM()`

### C. Optimized Query Implementation ✅ COMPLETE

**File**: `SAAQAnalyzer/DataLayer/OptimizedQueryManager.swift`

**Changes Made** (lines 606-616):
```swift
case .roadWearIndex:
    // Road Wear Index: 4th power law based on vehicle mass
    // Assumes 2 axles with equal weight distribution
    // RWI = (mass/2)^4 per axle, so total = 2 * (mass/2)^4 = mass^4 / 8
    if filters.roadWearIndexMode == .average {
        selectClause = "AVG(POWER(v.net_mass_int, 4)) as value"
    } else {
        selectClause = "SUM(POWER(v.net_mass_int, 4)) as value"
    }
    additionalWhereConditions = " AND v.net_mass_int IS NOT NULL"
```

Uses `net_mass_int` column (integer-based optimized schema) with same POWER() logic.

### D. UI Implementation ✅ COMPLETE

**File**: `SAAQAnalyzer/UI/FilterPanel.swift`

**Changes Made**:

1. **Fixed exhaustive switch in `descriptionText`** (lines 1853-1856):
```swift
case .roadWearIndex:
    return currentFilters.roadWearIndexMode == .average
        ? "Average road wear index (4th power law)"
        : "Total road wear index (4th power law)"
```

2. **Added UI controls for mode selection** (lines 1731-1746):
```swift
// Road Wear Index configuration
if metricType == .roadWearIndex {
    VStack(alignment: .leading, spacing: 4) {
        Text("Road Wear Index Mode")
            .font(.caption)
            .foregroundStyle(.secondary)

        Picker("Mode", selection: $roadWearIndexMode) {
            ForEach(FilterConfiguration.RoadWearIndexMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
```

3. **Added `roadWearIndexMode` binding parameter** (line 1556):
```swift
struct MetricConfigurationSection: View {
    @Binding var metricType: ChartMetricType
    @Binding var metricField: ChartMetricField
    @Binding var percentageBaseFilters: PercentageBaseFilters?
    @Binding var coverageField: CoverageField?
    @Binding var coverageAsPercentage: Bool
    @Binding var roadWearIndexMode: FilterConfiguration.RoadWearIndexMode  // ✅ NEW
    let currentFilters: FilterConfiguration
```

4. **Updated MetricConfigurationSection call** (line 200):
```swift
MetricConfigurationSection(
    metricType: $configuration.metricType,
    metricField: $configuration.metricField,
    percentageBaseFilters: $configuration.percentageBaseFilters,
    coverageField: $configuration.coverageField,
    coverageAsPercentage: $configuration.coverageAsPercentage,
    roadWearIndexMode: $configuration.roadWearIndexMode,  // ✅ NEW
    currentFilters: configuration
)
```

**UI Pattern**: Follows same pattern as coverage field UI (segmented picker, shown only when Road Wear Index metric is selected)

### E. Chart View Updates ✅ COMPLETE

**File**: `SAAQAnalyzer/UI/ChartView.swift`

**Changes Made** (lines 385-387):
```swift
case .roadWearIndex:
    // Road Wear Index formatting - use series' own formatValue() method
    return firstSeries.formatValue(value)
```

Fixed exhaustive switch in `formatYAxisValue()` function to handle Road Wear Index values using the series' built-in formatting (which includes scientific notation for large values).

---

## 3. Key Decisions & Patterns

### Architectural Decisions

#### **Decision 1: Use SQLite POWER() Function**
**Rationale**: SQLite natively supports `POWER(x, y)` for exponentiation, making the 4th power calculation efficient in SQL rather than post-processing in Swift.

**Implementation**:
```sql
AVG(POWER(net_mass, 4))  -- For average mode
SUM(POWER(net_mass, 4))  -- For sum mode
```

**Performance**: `POWER()` is slower than simple arithmetic but acceptable for aggregate queries. No index needed on `net_mass` for typical queries.

#### **Decision 2: Mode Selection via Enum**
**Rationale**: Consistent with existing pattern used for `coverageAsPercentage` boolean. Using an enum provides type safety and clear semantics.

**Pattern**:
```swift
enum RoadWearIndexMode: String, CaseIterable, Sendable {
    case average = "Average"
    case sum = "Sum"
}
```

**Location**: Nested within `FilterConfiguration` for encapsulation, similar to `AgeRange` pattern.

#### **Decision 3: Format Very Large Values with Scientific Notation**
**Rationale**: 4th power of mass (in kg) produces extremely large numbers. A 2000 kg vehicle produces 16 trillion (1.6 × 10^13) as individual RWI.

**Implementation**:
```swift
if value > 1e15 {
    return String(format: "%.2e RWI", value)  // "1.60e+13 RWI"
} else {
    return String(format: "%.0f RWI", value)  // "16000000000000 RWI"
}
```

**Note**: After normalization is implemented, most values will be close to 1.0, so this formatting may need adjustment.

#### **Decision 4: Normalization as Post-Processing Step** ⚠️ PENDING
**Rationale**: SQLite doesn't have window functions in all versions. Simpler to normalize in Swift after query execution.

**Planned Approach** (not yet implemented):
```swift
// After getting points from database:
let firstYearValue = points.first?.value ?? 1.0
let normalizedPoints = points.map { point in
    TimeSeriesPoint(
        year: point.year,
        value: point.value / firstYearValue,
        label: point.label
    )
}
```

### Code Patterns Established

#### **Pattern A: Exhaustive Switch Handling**
All `ChartMetricType` switch statements must include the `.roadWearIndex` case to avoid compiler errors.

**Locations Updated**:
1. ✅ DatabaseManager.swift:1203 (vehicle query 1)
2. ✅ DatabaseManager.swift:1505 (license query)
3. ✅ DatabaseManager.swift:1882 (vehicle query 2)
4. ✅ DataModels.swift:1492 (yAxisLabel)
5. ✅ DataModels.swift:1533 (formatValue)
6. ✅ ChartView.swift:385 (formatYAxisValue)
7. ✅ FilterPanel.swift:1853 (descriptionText)
8. ✅ OptimizedQueryManager.swift:606 (optimized query)

**All locations fixed** - build now compiles successfully!

#### **Pattern B: Vehicle-Only Metric**
Road Wear Index only applies to vehicle data (requires `net_mass` field).

**License Data Handling**:
```swift
case .roadWearIndex:
    // Road Wear Index not applicable to license data - fallback to count
    query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"
```

---

## 4. Active Files & Locations

### Modified Files (Uncommitted Changes)

#### **1. SAAQAnalyzer/Models/DataModels.swift**
**Purpose**: Core data structures for filters, metrics, and chart data

**Key Changes**:
- Lines 1305-1332: Added `roadWearIndex` to `ChartMetricType` enum (description, shortLabel)
- Lines 1126-1139: Added `RoadWearIndexMode` enum and `roadWearIndexMode` property
- Line 1225: Added `roadWearIndexMode` to `IntegerFilterConfiguration`
- Lines 1492-1493: Updated `yAxisLabel` for Road Wear Index
- Lines 1533-1539: Updated `formatValue()` for Road Wear Index (scientific notation)

**Key Functions**:
- `FilterConfiguration` (line 1093): String-based filter configuration
- `IntegerFilterConfiguration` (line 1195): Integer-based filter configuration
- `FilteredDataSeries` (line 1427): Observable class for chart data with formatting

#### **2. SAAQAnalyzer/DataLayer/DatabaseManager.swift**
**Purpose**: SQLite database operations and query execution

**Key Changes**:
- Lines 1203-1211: Added Road Wear Index query to vehicle data query (first occurrence)
- Lines 1505-1507: Added fallback for Road Wear Index in license data query
- Lines 1882-1890: Added Road Wear Index query to vehicle data query (second occurrence)

**SQL Pattern**:
```sql
-- Average mode
SELECT year, AVG(POWER(net_mass, 4)) as value
FROM vehicles
WHERE net_mass IS NOT NULL AND [filters]
GROUP BY year
ORDER BY year

-- Sum mode
SELECT year, SUM(POWER(net_mass, 4)) as value
FROM vehicles
WHERE net_mass IS NOT NULL AND [filters]
GROUP BY year
ORDER BY year
```

**Key Functions**:
- `queryVehicleData(filters:)` (line 1110): Main vehicle query function
- `queryLicenseData(filters:)` (line 1421): Main license query function
- `calculatePercentagePoints(filters:)` (line 1809): Percentage baseline calculation

**⚠️ Normalization Location**: Need to add post-processing logic in `queryVehicleData()` before returning `FilteredDataSeries`

#### **3. SAAQAnalyzer/DataLayer/OptimizedQueryManager.swift**
**Purpose**: Integer-based optimized queries for performance

**Key Changes**:
- Lines 606-616: Added Road Wear Index query with `net_mass_int` column

**Pattern**: Uses `POWER(v.net_mass_int, 4)` instead of `POWER(net_mass, 4)` for integer-optimized schema

**Key Function**:
- `queryVehicleDataWithIntegers(filters:filterIds:)` (line 313): Optimized vehicle query

#### **4. SAAQAnalyzer/UI/FilterPanel.swift**
**Purpose**: Left panel filter UI with metric selection

**Key Changes**:
- Lines 1731-1746: Added Road Wear Index mode selector (segmented picker)
- Line 1556: Added `@Binding var roadWearIndexMode` parameter
- Line 200: Pass `roadWearIndexMode` binding to MetricConfigurationSection
- Lines 1853-1856: Updated `descriptionText` switch for Road Wear Index

**UI Pattern**:
- Segmented picker shown only when `metricType == .roadWearIndex`
- Follows same pattern as coverage field UI (lines 1691-1727)
- Two-way binding to `configuration.roadWearIndexMode`

#### **5. SAAQAnalyzer/UI/ChartView.swift**
**Purpose**: Chart rendering and export

**Key Changes**:
- Lines 385-387: Added `.roadWearIndex` case to `formatYAxisValue()` switch

**Pattern**: Delegates formatting to series' own `formatValue()` method, which handles scientific notation

---

## 5. Current State

### What's Working ✅
1. ✅ Road Wear Index added to data models (ChartMetricType enum)
2. ✅ Mode selection enum (average/sum) implemented
3. ✅ Configuration properties added to filter structures
4. ✅ Y-axis label formatting implemented
5. ✅ Value formatting with scientific notation for large numbers
6. ✅ SQL queries implemented for vehicle data (3 locations in DatabaseManager)
7. ✅ License data fallback implemented (returns count)
8. ✅ Optimized integer-based queries implemented (OptimizedQueryManager)
9. ✅ UI controls added (segmented picker for Average/Sum mode)
10. ✅ All exhaustive switch errors fixed
11. ✅ **Build compiles successfully**

### What's NOT Done ⚠️

#### **CRITICAL: Normalization Missing**
Results are NOT normalized to first year = 1.0 as required. This is the most important missing piece.

**Current behavior**: Returns raw POWER() values (extremely large numbers)
**Required behavior**: Divide all values by first year's value so first year = 1.0

**Implementation needed**: Post-processing in `DatabaseManager.queryVehicleData()` before returning series

### What's NOT Started ⭐
1. ⭐ **Normalization**: Post-processing to make first year = 1.0 (CRITICAL)
2. ⭐ **Testing**: No runtime testing with actual data yet
3. ⭐ **Performance testing**: Query execution time with POWER() function

### Build Status
**Status**: ✅ **Build succeeds** - All exhaustive switch errors fixed

**Compilation**: Project should build without errors in Xcode

---

## 6. Next Steps (Priority Order)

### IMMEDIATE PRIORITY: Implement Normalization ⚠️ BLOCKING

**Why Critical**: User requirement states "results must be normalized so the first year = 1.0". Without this, Road Wear Index values will be meaningless (enormous raw numbers instead of relative ratios).

**Implementation Approach**:

1. **Add normalization helper function** to `DatabaseManager.swift`:

```swift
/// Normalize time series points so first year = 1.0
private func normalizeToFirstYear(points: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
    guard let firstValue = points.first?.value, firstValue > 0 else {
        // Handle edge cases: empty array or zero/negative first value
        AppLogger.query.warning("Cannot normalize: first year value is \(points.first?.value ?? 0)")
        return points
    }

    return points.map { point in
        TimeSeriesPoint(
            year: point.year,
            value: point.value / firstValue,
            label: point.label
        )
    }
}
```

2. **Apply normalization in 3 locations** (after query execution, before returning series):

   **A. `queryVehicleData(filters:)` - line ~1300** (before returning series):
   ```swift
   // After getting points from query execution:
   let points = /* ... query execution ... */

   // Apply normalization for Road Wear Index
   let normalizedPoints = if filters.metricType == .roadWearIndex {
       normalizeToFirstYear(points: points)
   } else {
       points
   }

   return FilteredDataSeries(
       name: seriesName,
       filters: filters,
       points: normalizedPoints
   )
   ```

   **B. `queryLicenseData(filters:)` - line ~1550** (for consistency):
   ```swift
   // Same pattern (though Road Wear Index falls back to count for licenses)
   ```

   **C. `calculatePercentagePoints(filters:)` - line ~1900** (if RWI used in percentage):
   ```swift
   // Apply normalization if Road Wear Index is being used for percentage calculation
   ```

3. **Update value formatting** in `DataModels.swift` (line 1533) to handle normalized values:

   ```swift
   case .roadWearIndex:
       // After normalization, values will be close to 1.0
       if value >= 0.01 && value <= 100.0 {
           return String(format: "%.2f RWI", value)  // Normalized format: "1.05 RWI"
       } else if value > 1e15 {
           return String(format: "%.2e RWI", value)  // Scientific notation (pre-normalization)
       } else {
           return String(format: "%.0f RWI", value)  // Standard format
       }
   ```

**Edge Cases to Handle**:
- First year has zero RWI (divide by zero)
- First year has negative RWI (shouldn't happen, but check)
- Empty result set (no points to normalize)
- Only one year in result set (trivial normalization: 1.0)

**Testing After Implementation**:
1. Query Montreal 2020-2024 in Average mode → First year (2020) should be 1.00
2. Query same in Sum mode → First year should still be 1.00
3. Compare multiple years → Values should show relative change (e.g., 1.05 = 5% increase)

### STEP 2: Test with Sample Data

**After normalization is implemented**:

1. **Build Application**:
   ```bash
   # In Xcode: Product → Build (⌘B)
   ```

2. **Launch Application**:
   ```bash
   # In Xcode: Product → Run (⌘R)
   ```

3. **Test Road Wear Index - Average Mode**:
   - Set data entity: Vehicle
   - Apply filters: Montreal, Years 2020-2024
   - Set metric: Road Wear Index
   - Set mode: Average
   - Click "Add to Chart"
   - **Verify**:
     - First year (2020) has value close to 1.0 ✅
     - Values are displayed with 2 decimal places (e.g., "1.05 RWI")
     - Y-axis label shows "Average Road Wear Index"
     - Chart renders without errors

4. **Test Road Wear Index - Sum Mode**:
   - Keep same filters
   - Change mode: Sum
   - Update chart or add new series
   - **Verify**:
     - First year (2020) has value close to 1.0 ✅
     - Sum mode shows similar trend (may differ in magnitude)
     - Y-axis label shows "Total Road Wear Index"
     - Values formatted correctly

5. **Test Edge Cases**:
   - Empty filter result (no vehicles) → Should handle gracefully
   - Single year selected → Should show 1.0 (trivial normalization)
   - Very large filter set (all vehicles, all years) → Performance check
   - Export chart as PNG → Verify legend shows mode

6. **Performance Check**:
   - Query execution time should be reasonable (< 10 seconds for typical query)
   - `POWER()` function is efficient in SQLite but may be slower than simple aggregates
   - Check console for any performance warnings

### STEP 3: Documentation

**After testing is complete**:

1. Update CLAUDE.md with Road Wear Index feature documentation
2. Add usage examples to user-facing documentation (if any)
3. Document the normalization approach and formula

---

## 7. Important Context

### Errors Solved

#### **Error 1: "Switch must be exhaustive"**

**Problem**: Added new enum case `.roadWearIndex` to `ChartMetricType`, but didn't update all switch statements that handle this enum.

**Locations Fixed**:
1. ✅ DatabaseManager.swift:1203 - Vehicle query 1
2. ✅ DatabaseManager.swift:1505 - License query
3. ✅ DatabaseManager.swift:1882 - Vehicle query 2
4. ✅ DataModels.swift:1492 - yAxisLabel
5. ✅ DataModels.swift:1533 - formatValue
6. ✅ ChartView.swift:385 - formatYAxisValue
7. ✅ FilterPanel.swift:1853 - descriptionText
8. ✅ OptimizedQueryManager.swift:606 - optimized query

**Solution Pattern**:
```swift
case .roadWearIndex:
    // Implement Road Wear Index logic here
    // For vehicle queries: use POWER(net_mass, 4)
    // For license queries: fallback to COUNT(*)
    // For UI: display mode selector
```

**Status**: ✅ All fixed - build compiles successfully

### Database Considerations

#### **SQLite POWER() Function**

**Availability**: Built-in to SQLite 3.0+

**Syntax**:
```sql
POWER(base, exponent)
-- Example: POWER(2000, 4) = 16000000000000
```

**Performance**:
- `POWER()` is slower than simple arithmetic but acceptable for aggregate queries
- Filtering by `net_mass IS NOT NULL` prevents processing unnecessary rows
- Index on `net_mass` would help but likely not needed for typical queries

**Alternatives Considered**:
- Could calculate `mass * mass * mass * mass` instead of `POWER(mass, 4)`
- Slightly faster but less readable
- For now, using `POWER()` for clarity

#### **NULL Handling**

**Issue**: Some vehicles may have NULL `net_mass` values

**Solution**: `WHERE net_mass IS NOT NULL` filter in SQL query

**Impact**: Vehicles without mass data are excluded from Road Wear Index calculations

### Swift Concurrency Patterns

**All database operations use async/await**:
```swift
func queryVehicleData(filters: FilterConfiguration) async throws -> FilteredDataSeries
```

**Pattern**: Return `FilteredDataSeries` with populated `points` array

**Normalization Location**: Apply after query execution, before returning series

### UI/UX Considerations

#### **Scientific Notation Threshold**

**Current Decision**: Display values > 1e15 in scientific notation

**Rationale**:
- Individual vehicle RWI for 2000 kg vehicle: 1.6 × 10^13
- Average RWI across thousands of vehicles: ~1-5 × 10^13
- Sum RWI for entire dataset: > 1 × 10^17 (hundreds of quintillions)
- Standard decimal notation becomes unreadable

**Format Examples** (pre-normalization):
```
Value: 1,600,000,000,000 → "1.60e+12 RWI" (average mode)
Value: 160,000,000,000,000,000 → "1.60e+17 RWI" (sum mode)
```

#### **Normalization Display**

**After normalization**, all values become relative to first year = 1.0:
```
Year 2020: 1.00 RWI  (normalized baseline)
Year 2021: 1.05 RWI  (5% increase)
Year 2022: 0.98 RWI  (2% decrease)
```

**Implication**: Need to adjust `formatValue()` to detect normalized values and use simpler formatting:
```swift
case .roadWearIndex:
    // Check if value is normalized (close to 1.0)
    if value >= 0.01 && value <= 100.0 {
        return String(format: "%.2f RWI", value)  // Normalized format
    } else if value > 1e15 {
        return String(format: "%.2e RWI", value)  // Scientific notation
    } else {
        return String(format: "%.0f RWI", value)  // Standard format
    }
```

### Git & Version Control

**Current Branch**: `rhoge-dev`

**Uncommitted Changes**:
- `SAAQAnalyzer/Models/DataModels.swift` (M)
- `SAAQAnalyzer/DataLayer/DatabaseManager.swift` (M)
- `SAAQAnalyzer/DataLayer/OptimizedQueryManager.swift` (M)
- `SAAQAnalyzer/UI/FilterPanel.swift` (M)
- `SAAQAnalyzer/UI/ChartView.swift` (M)

**Git Status**:
```
On branch rhoge-dev
Changes not staged for commit:
  M SAAQAnalyzer/DataLayer/DatabaseManager.swift
  M SAAQAnalyzer/Models/DataModels.swift

Untracked files:
  Notes/2025-10-11-Road-Wear-Index-Implementation-In-Progress.md
```

**Recommended Commit Message** (after normalization is implemented):
```
feat: Add Road Wear Index metric with 4th power law calculation

Implement Road Wear Index (RWI) metric based on engineering principle
that road wear is proportional to the 4th power of axle loading.

Features:
- Average and Sum modes for RWI calculation
- SQLite POWER() function for efficient computation
- Normalized results (first year = 1.0)
- Scientific notation formatting for very large values
- Segmented picker UI for mode selection
- Vehicle data only (license data falls back to count)

Technical details:
- Assumes 2 axles with equal weight distribution
- Formula: RWI = (mass/2)^4 per axle
- Filters out NULL mass values
- Post-processes results to normalize to first year

Related: User request for road infrastructure impact analysis
```

---

## Summary

**Current Progress**: **80% Complete**

**✅ Completed**:
- Data model changes (enum, properties, formatting)
- Database queries (regular and optimized)
- UI controls (segmented picker)
- All exhaustive switch errors fixed
- Build compiles successfully

**⚠️ Critical Missing**:
- **Normalization to first year = 1.0** (user requirement)

**Next Session**:
1. Implement normalization helper function
2. Apply normalization in 3 query locations
3. Update value formatting for normalized values
4. Test with sample data (Average and Sum modes)
5. Verify first year = 1.0 in all cases
6. Check edge cases and performance
7. Commit changes

**Estimated Time to Complete**: 30-60 minutes for normalization + testing

---

**Session completed**: October 11, 2025
**Next session**: Pick up with normalization implementation in `DatabaseManager.swift`
