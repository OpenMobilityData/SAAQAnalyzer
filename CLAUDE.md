# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: Read Architecture Guide First

**Before starting any development work**, review the architectural guides:

📚 **Quick Start**: [Documentation/QUICK_REFERENCE.md](Documentation/QUICK_REFERENCE.md) (5 min read)
📖 **Full Details**: [Documentation/ARCHITECTURAL_GUIDE.md](Documentation/ARCHITECTURAL_GUIDE.md) (comprehensive)

---

## ⚠️ CRITICAL RULES - Prevent Regressions

**These rules MUST be followed. Violations cause crashes, performance issues, or data corruption.**

### 1. Integer Enumeration ONLY

**ALL categorical data uses integer foreign keys. NEVER use string columns or string queries.**

```swift
// ✅ CORRECT
CREATE TABLE vehicles (
    make_id INTEGER REFERENCES make_enum(id),
    model_id INTEGER REFERENCES model_enum(id)
);

// ❌ WRONG - DO NOT DO THIS
CREATE TABLE vehicles (
    make TEXT,  // NEVER use string columns!
    model TEXT
);
```

**Why**: 10x performance improvement, enables covering indexes.
**Lesson**: September 2024 - Complete schema redesign based on this principle.

### 2. Always Ask Before NS-Prefixed APIs

**NEVER use AppKit/Foundation NS-prefixed APIs without asking the human developer first.**

Examples that require approval: `NSOpenPanel`, `NSSavePanel`, `NSAlert`, `NSColor`, etc.

Prefer SwiftUI equivalents: `.fileImporter()`, `.alert()`, `Color`, etc.

### 3. Manual Triggers for Filter State Updates

**NEVER use `.onChange` handlers for filter state updates. Always use manual button triggers.**

```swift
// ✅ CORRECT
Button("Filter Models") {
    Task { await filterModels() }
}

// ❌ WRONG - CAUSES CRASHES
.onChange(of: selectedMakes) { _ in
    Task { await filterModels() }  // AttributeGraph CRASH!
}
```

**Why**: SwiftUI AttributeGraph has hard limits on circular dependencies.
**Lesson**: October 14, 2025 - Hierarchical filtering crashed until pattern corrected.

### 4. Background Processing for Expensive Operations

**Any operation taking >100ms MUST run in background via `Task.detached`.**

```swift
// ✅ CORRECT
Task.detached(priority: .background) {
    let result = await heavyComputation()
    await MainActor.run {
        self.data = result
    }
}

// ❌ WRONG - Blocks UI
let result = heavyComputation()  // Causes beachball cursor
self.data = result
```

**Why**: Prevents UI freezing and beachball cursor.
**Lesson**: October 11, 2025 - Regularization UI blocked for minutes until fixed.

### 5. Cache Invalidation Pattern

**ALWAYS call `invalidateCache()` before `initializeCache()` after data changes.**

```swift
// ✅ CORRECT
await filterCacheManager.invalidateCache()
await filterCacheManager.initializeCache()

// ❌ WRONG - Stale data persists
await filterCacheManager.initializeCache()  // Has guard, won't reload!
```

**Why**: Cache has `isInitialized` guard preventing re-initialization.

### 6. Enum Table Indexes

**ALL enumeration tables MUST have indexes on their `id` columns.**

```sql
CREATE INDEX idx_make_enum_id ON make_enum(id);
CREATE INDEX idx_model_enum_id ON model_enum(id);
-- etc for ALL enum tables
```

**Why**: Without indexes, 6-way JOINs take 165s instead of <10s.
**Lesson**: October 11, 2025 - Adding 9 indexes improved performance 16x.

### 7. Data-Type-Aware Operations

**Pass `dataType` parameter through import/cache chains. License imports should NOT load vehicle caches.**

```swift
// ✅ CORRECT
await endBulkImport(dataType: .vehicle)
await refreshAllCaches(dataType: .vehicle)

// ❌ WRONG - Loads unnecessary data
await refreshAllCaches()  // Loads 10K+ vehicle items for license import!
```

**Why**: License imports hung 30+ seconds loading vehicle caches.
**Lesson**: October 15, 2025 - Selective cache loading implemented.

### 8. Use os.Logger in Production Code

**ALL production code uses `os.Logger` (AppLogger). NEVER use `print()`.**

```swift
// ✅ CORRECT - Production code
AppLogger.database.info("Importing \(fileName, privacy: .public)")

// ❌ WRONG - Production code
print("Importing \(fileName)")

// ✅ EXCEPTION - CLI scripts in Scripts/ can use print()
```

**Why**: Console.app integration, performance, structured logging.
**Lesson**: October 10, 2025 - Migration to os.Logger initiated.

### 9. Thread-Safe Database Access

**Pass database PATHS (strings) to concurrent tasks, NEVER share connections.**

```swift
// ✅ CORRECT
await withTaskGroup { group in
    group.addTask {
        let db = try openDatabase(path: dbPath)  // Fresh connection
        return query(db, item)
    }
}

// ❌ WRONG
let db = try openDatabase(path: dbPath)
await withTaskGroup { group in
    group.addTask {
        return query(db, item)  // SEGFAULT!
    }
}
```

**Why**: SQLite not thread-safe across concurrent tasks.
**Lesson**: October 5, 2025 - Segfaults until pattern corrected.

### 10. Table-Specific ANALYZE

**ALWAYS specify table name in ANALYZE commands.**

```swift
// ✅ CORRECT
sqlite3_exec(db, "ANALYZE vehicles")

// ❌ WRONG
sqlite3_exec(db, "ANALYZE")  // Analyzes entire 35GB+ database!
```

**Why**: Without table name, analyzes entire database (can take minutes).
**Lesson**: October 15, 2025 - License imports hung until fixed.

---

## Pre-Development Checklist

Before writing ANY code, verify:

- [ ] Am I using **integer foreign keys** for categorical data?
- [ ] Will this query need **indexes on enum table IDs**?
- [ ] Should this expensive operation run in **background**?
- [ ] Does this state update need **MainActor.run**?
- [ ] Am I about to use an **NS-prefixed API**? (ASK FIRST!)
- [ ] Will this import **invalidate caches**?
- [ ] Is this operation **data-type aware**?
- [ ] Am I using **os.Logger** for production code?
- [ ] Will this **onChange** trigger during rendering?
- [ ] Am I passing a **database PATH** to concurrent tasks?

---

## Project Overview

SAAQAnalyzer is a macOS SwiftUI application designed to import, analyze, and visualize vehicle registration data from SAAQ (Société de l'assurance automobile du Québec). The application provides a three-panel interface for filtering data, displaying charts, and inspecting details.

## Development Principles

### Swift Concurrency
- **Swift version**: 6.2
- **Concurrency**: Use only modern Swift 6.2 concurrency constructs (async/await, actors, TaskGroups)
- **Avoid**: Legacy patterns (DispatchQueue, Operation, completion handlers)

### Framework Preferences
- **Avoid AppKit**: Stick to SwiftUI and Swift-native APIs whenever possible
- **NS prefix warning**: Always ask before using any AppKit/Foundation API with NS prefix (NSOpenPanel, NSSavePanel, NSAlert, etc.)
- **Prefer**: SwiftUI equivalents and modern Swift APIs

### Command Line Workflow
- **NEVER auto-run builds or tests**: User ALWAYS prefers to build and run manually
- **Manual execution preferred**: Generate robust command-line invocations for copy/paste into console
- **Don't auto-run**: User prefers to run scripts manually to monitor output and selectively copy results back
- **Output format**: Ensure scripts produce clear, copy-friendly output for integration into Claude Code sessions

#### Example Command Line Patterns
```bash
# Database inspection
sqlite3 ~/Library/Application\ Support/SAAQAnalyzer/saaq.db "SELECT COUNT(*) FROM vehicles;"

# CSV validation before import
head -n 5 ~/Downloads/Vehicule_En_Circulation_2023.csv

# Performance testing
time sqlite3 ~/Library/Application\ Support/SAAQAnalyzer/saaq.db "EXPLAIN QUERY PLAN SELECT..."

## Build and Development Commands

```bash
# Build the project (use Xcode)
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -configuration Debug build

# Run tests
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -destination 'platform=macOS'

# Clean build folder
xcodebuild clean -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer
```

**Primary development environment**: Xcode IDE is required for iOS/macOS Swift development. Open `SAAQAnalyzer.xcodeproj` in Xcode to build and run the application.

## Architecture Overview

### Core Components

1. **Data Layer** (`DataLayer/`)
   - `DatabaseManager.swift`: SQLite database operations with async/await patterns
   - `CSVImporter.swift`: Handles importing SAAQ CSV files with encoding fixes for French characters
   - `GeographicDataImporter.swift`: Imports d001 geographic reference files

2. **Models** (`Models/`)
   - `DataModels.swift`: Core data structures including VehicleRegistration, GeographicEntity, FilterConfiguration, and enums for classifications

3. **UI Layer** (`UI/`)
   - `FilterPanel.swift`: Left panel with two distinct top-level sections (Oct 2025):
     - **Analytics Section**: Configuration for what to measure
       - Y-Axis Metric (count, sum, average, RWI, percentage, coverage)
       - Draggable divider allows height adjustment (200-600pt range)
     - **Filters Section**: Configuration for what subset of data to analyze
       1. Filter Options (includes toggles for:)
          - "Limit to Curated Years Only" - Filters out uncurated Make/Model pairs
          - "Enable Query Regularization" - Merges uncurated variants into canonical values
          - "Couple Make/Model in Queries" - Conditional toggle, includes Make when filtering by Model
       2. Years (when)
       3. Geographic Location (where)
       4. Vehicle/License Characteristics (what/who)
          - **Hierarchical Make/Model Filtering** - Manual button appears when Makes selected (Oct 2025)
            - Button states: "Filter by Selected Makes (N)" / "Filtering by N Make(s)" (disabled) / "Show All Models"
            - Three-state UX: ready to filter / actively filtering (status) / can reset
            - Fast in-memory filtering using FilterCacheManager
            - Avoids SwiftUI AttributeGraph crashes from automatic filtering
   - `ChartView.swift`: Center panel with Charts framework integration (line, bar, area charts)
   - `DataInspector.swift`: Right panel for detailed data inspection

4. **Main App**
   - `SAAQAnalyzerApp.swift`: App entry point with three-panel NavigationSplitView layout

### Database Schema

- **vehicles**: Main table storing vehicle registration data (16 fields for 2017+, 15 for earlier years)
  - Includes `vehicle_class_id` (CLAS field - usage-based classification like PAU, CAU, PMC)
  - Includes `vehicle_type_id` (TYP_VEH_CATEG_USA field - physical type like AU, CA, MC)
- **geographic_entities**: Hierarchical geographic data (regions, MRCs, municipalities)
- **import_log**: Tracks import operations and success/failure status
- **canonical_hierarchy_cache**: Materialized cache for regularization queries (Oct 2025)
  - Pre-aggregated Make/Model/Year/Fuel/VehicleType combinations from curated years
  - Populated on-demand, persists across sessions
- **Enumeration tables** (16 total): year_enum, vehicle_class_enum, vehicle_type_enum, make_enum, model_enum, fuel_type_enum, color_enum, cylinder_count_enum, axle_count_enum, model_year_enum, admin_region_enum, mrc_enum, municipality_enum, age_group_enum, gender_enum, license_type_enum

### Key Design Patterns

- **MVVM Architecture**: ObservableObject pattern with @StateObject and @EnvironmentObject
- **Async/await**: Database operations use structured concurrency
- **Three-panel layout**: NavigationSplitView with filters, charts, and details
- **Batch processing**: CSV imports processed in 1000-record batches for performance
- **Draggable UI dividers**: Resizable sections with visual feedback and cursor affordances (Oct 2025)
- **@AppStorage synchronization**: Global settings synced across multiple UI locations via UserDefaults (Oct 2025)

## Data Import Process

### File Types
- **Vehicle CSV files**: Named pattern `Vehicule_En_Circulation_YYYY.csv`
- **Geographic d001 files**: `d001_min.txt` format for municipality/region mapping

### CSV Preprocessing (Scripts/)

**Production Tool:**
- **NormalizeCSV.swift** ✅ - Fixes structural inconsistencies in SAAQ CSV files
  - Problem: 2017+ files have 16 fields (fuel_type added), earlier files have 15
  - Solution: Adds NULL fuel_type column to pre-2017 files
  - Status: Production-ready, required for database import
  - Compilation: `swiftc NormalizeCSV.swift -o NormalizeCSV -O`

**Experimental Tools (Work in Progress):**
- **Make/Model Regularization Scripts** 🚧 - Various approaches to correcting typos and variants
  - Problem: 2023-2024 data has typos (VOLV0), truncations (CX3 vs CX-3), mixed with genuinely new models
  - Scripts: StandardizeMakeModel, AIStandardizeMake, AIStandardizeMakeModel, AIRegularizeMakeModel, RegularizeMakeModel
  - Status: Experimental - DO NOT apply to production database
  - See: `Scripts/SCRIPTS_DOCUMENTATION.md` for detailed analysis and architectural evolution

**Key Distinction:**
- ✅ **NormalizeCSV** fixes column structure (WORKING - use in production)
- 🚧 **Make/Model scripts** attempt content correction (EXPERIMENTAL - research only)

### Character Encoding
The CSV importer handles French characters by trying multiple encodings (UTF-8, ISO-Latin-1, Windows-1252) and includes fixes for common encoding corruption patterns like "Montréal" → "MontrÃ©al".

### Data Quality Issues

**Known SAAQ Data Limitations**:
- **MRC field missing for 2023-2024**: The MRC column exists in CSV files but contains only empty strings
  - **Impact**: MRC-based filtering excludes 2023-2024 data (records imported with NULL mrc_id)
  - **Workaround**: Use Admin Region or Municipality filters for 2023-2024 geographic filtering
  - **Status**: Confirmed data source issue, not an application bug
  - **Detection date**: October 2025
  - **Potential fixes** (not implemented):
    1. Derive MRC from municipality code using geographic hierarchy
    2. Fall back to Admin Region when MRC is NULL
    3. Contact SAAQ to request corrected data

### Data Validation
- Schema validation based on year (fuel type field available 2017+)
- Duplicate detection using UNIQUE constraint on (year, vehicle_sequence)
- Import logging tracks success/failure rates

## UI Framework and Components

- **SwiftUI**: Modern declarative UI framework
- **Charts framework**: Native charting with line, bar, and area chart types
- **AppKit integration**: Uses NSOpenPanel, NSSavePanel, NSAlert for file operations
- **NavigationSplitView**: Three-column responsive layout

### Available Chart Metrics

The application supports multiple metric types for data analysis:

1. **Count**: Record count (default)
   - Simple count of vehicles or license holders matching filters

2. **Sum/Average/Min/Max**: Aggregate functions on numeric fields
   - Fields: Vehicle Mass (kg), Engine Displacement (cm³), Cylinders, Vehicle Age, Model Year
   - Example legend: `"Avg Vehicle Mass (kg) in [[filters]]"`

3. **Percentage**: Ratio within a baseline superset
   - Compares filtered subset against a broader baseline
   - Example: Percentage of electric vehicles among all vehicles in Montreal

4. **Coverage**: Data completeness analysis
   - Analyzes NULL vs non-NULL values for specific fields
   - Two modes: Percentage coverage or raw NULL count
   - Useful for assessing data quality across years

5. **Road Wear Index (RWI)** ✨ *New in October 2025*
   - Engineering metric based on 4th power law of road wear (damage ∝ axle_load^4)
   - Displayed as "Road Wear Index" with tooltip explaining the 4th power law
   - **Weight Distribution** (axle-based with vehicle-type fallback):
     - **Primary: Actual Axle Count** (when `max_axles` data available from BCA trucks):
       - **2 axles**: 45% front, 55% rear → RWI = 0.1325 × mass^4
       - **3 axles**: 30% front, 35% rear1, 35% rear2 → RWI = 0.0234 × mass^4
       - **4 axles**: 25% each → RWI = 0.0156 × mass^4
       - **5 axles**: 20% each → RWI = 0.0080 × mass^4
       - **6+ axles**: ~16.67% each (6 axles) → RWI = 0.0046 × mass^4
     - **Fallback: Vehicle-Type Assumptions** (when `max_axles` is NULL):
       - **Trucks (CA) & Tool vehicles (VO)**: Assume 3 axles → RWI = 0.0234 × mass^4
       - **Buses (AB)**: Assume 2 axles (35/65 split) → RWI = 0.1935 × mass^4
       - **Cars (AU) & other vehicles**: Assume 2 axles (50/50 split) → RWI = 0.125 × mass^4
   - **Modes**:
     - **Average**: Mean road wear index across vehicles
     - **Sum**: Total cumulative road wear
   - **Normalization** (see "Normalize to First Year" feature below)
     - When enabled, first year = 1.0, subsequent years show relative change
     - Works with RWI and all other metric types
     - Raw RWI values (mass^4) displayed when normalization is off
     - Values displayed in scientific notation (e.g., "1.60e+18 RWI") or magnitude notation (K/M) when not normalized
   - **Display Format**:
     - Normalized values: "1.05 RWI" (2 decimal places)
     - Raw values: Scientific notation or K/M notation for large values
   - **Use Cases**: Infrastructure impact analysis, fleet management, policy evaluation
   - **Key Insight**: 6-axle truck causes 97% less road damage per kg than 2-axle truck
   - **Legend format**: `"Avg RWI in [[filters]]"` or `"Total RWI (All Vehicles)"`
   - **Y-axis label**: Indicates normalization state: "(Normalized)" or "(Raw)"
   - **Implementation**:
     - `OptimizedQueryManager.swift:647-673`: RWI calculation (axle-based with vehicle-type fallback) ⚠️ PRIMARY PATH
     - `DatabaseManager.swift:399-421`: Normalization helper function
     - `DatabaseManager.swift:1227-1245`: RWI calculation (legacy path, not used)
     - `DatabaseManager.swift:1923-1941`: RWI calculation (percentage query path, legacy)
     - `DatabaseManager.swift:1436-1440`: Conditional normalization application (see Normalize to First Year below)
     - `OptimizedQueryManager.swift:693-697`: Conditional normalization (optimized path, see Normalize to First Year)
     - `FilterPanel.swift:1731-1768`: UI mode selector (RWI-specific)
     - `DataModels.swift:1127`: normalizeToFirstYear property (global, see below)
     - `DataModels.swift:1546-1564`: Value formatting with normalization awareness
     - `ChartView.swift:328-336`: Y-axis formatting with automatic precision detection for normalized values
     - `ChartView.swift:688`: Legend display using formatValue()

### Cumulative Sum Transform ✨ *New in October 2025*

**Global toggle** available for all metrics that transforms time series data into cumulative values:

- **Purpose**: Shows accumulated totals over time instead of year-by-year values
- **Use Cases**:
  - **Road Wear Index**: Total cumulative road damage from the fleet since first year
  - **Vehicle Count**: Growing vehicle population over time
  - **Coverage Analysis**: Cumulative data completeness improvement
- **Behavior**: Each year's value becomes the sum of all previous years plus current year
- **Applies After**: Normalization (for RWI), ensuring correct transformation order
- **Legend Display**: When enabled, chart legends show "Cumulative" prefix to distinguish from non-cumulative data
  - Example: "Cumulative Avg RWI in [All Vehicles]" vs "Avg RWI in [All Vehicles]"
  - Applies to all metric types (Count, Sum, Average, RWI, etc.)
- **Implementation**:
  - `DataModels.swift:1128`: showCumulativeSum property
  - `DatabaseManager.swift:423-442`: applyCumulativeSum() helper function
  - `DatabaseManager.swift:1478-1480`: Vehicle query cumulative transform
  - `DatabaseManager.swift:1750-1752`: License query cumulative transform
  - `DatabaseManager.swift:2401-2404`: Legend generation for aggregate metrics (with cumulative prefix)
  - `DatabaseManager.swift:2473-2476`: Legend generation for RWI (with cumulative prefix)
  - `DatabaseManager.swift:2665-2668`: Legend generation for count metric (with cumulative prefix)
  - `OptimizedQueryManager.swift:714-716`: Optimized vehicle query transform
  - `OptimizedQueryManager.swift:856-858`: Optimized license query transform
  - `FilterPanel.swift:1773-1791`: UI toggle control

### Normalize to First Year ✨ *Promoted to Global in October 2025*

**Global toggle** available for all metrics that normalizes time series data so first year = 1.0:

- **Purpose**: Shows relative change over time instead of absolute values
- **Use Cases**:
  - **All Metrics**: Compare growth rates across different measurements (vehicles, mass, RWI, etc.)
  - **Percentages**: Convert to decimal fractions (50% → 1.0, 60% → 1.2 for 20% increase)
  - **Trend Analysis**: First year = 1.0, subsequent years show relative change (1.05 = 5% increase)
- **Behavior**: Divides all years by first year value (2011: 1000 → 1.0, 2012: 1100 → 1.1)
- **Applies Before**: Cumulative sum (if enabled), ensuring correct transformation order
- **Display Precision**: Automatically shows 2 decimal places for normalized values (detects range 0.1-10.0)
- **Edge Cases**: Returns original values if first year is zero or negative (prevents division by zero)
- **Implementation**:
  - `DataModels.swift:1127`: normalizeToFirstYear property
  - `DataModels.swift:1232`: normalizeToFirstYear in IntegerFilterConfiguration
  - `DatabaseManager.swift:399-421`: normalizeToFirstYear() helper function
  - `DatabaseManager.swift:1471-1480`: Vehicle query normalization (applied to all metrics)
  - `DatabaseManager.swift:1749-1758`: License query normalization (applied to all metrics)
  - `OptimizedQueryManager.swift:719-723`: Optimized vehicle query normalization
  - `OptimizedQueryManager.swift:867-876`: Optimized license query normalization
  - `FilterPanel.swift:1817-1835`: UI toggle control (global section, below RWI config)
  - `ChartView.swift:328-336`: Automatic 2-decimal precision detection for normalized values
  - `DataModels.swift:1516-1519`: Legend value formatting with normalization awareness

## Development Notes

### Performance Considerations
- SQLite WAL mode enabled for concurrent reads
- Indexes on year, vehicle_class_id, vehicle_type_id, geographic fields, and fuel_type_id
- 64MB cache size for database operations
- Batch processing for large imports

### Query Performance & Transparency System
- **Deterministic Index Analysis**: Uses `EXPLAIN QUERY PLAN` to analyze query performance before execution
- **Real-time Progress Indicators**: `SeriesQueryProgressView` shows query patterns and index usage status
- **Smart Performance Detection**: Detects table scans, temp B-trees, and other performance issues
- **Educational UI**: Progress views explain why queries are slow (limited indexing vs. optimized)
- **Console Transparency**: Detailed execution plan output for debugging and optimization
- **Query Pattern Generation**: `generateQueryPattern()` creates human-readable query descriptions
- **Performance Classification**: Automatic categorization from "Excellent" (sub-second) to "Slow" (25s+)

### Logging Infrastructure
- **Framework**: Uses Apple's `os.Logger` (unified logging system) for all production logging
- **Location**: `Utilities/AppLogger.swift` - Centralized logging infrastructure
- **Categories**:
  - `AppLogger.database` - Database operations (connections, schema, transactions)
  - `AppLogger.dataImport` - CSV import operations and file processing
  - `AppLogger.query` - Query execution and optimization
  - `AppLogger.cache` - Filter cache operations
  - `AppLogger.regularization` - Regularization system operations
  - `AppLogger.ui` - UI events and user interactions
  - `AppLogger.performance` - Performance benchmarks and timing measurements
  - `AppLogger.geographic` - Geographic data operations

- **Log Levels**:
  - `.debug` - Detailed debugging (filtered in release builds, wrapped in `#if DEBUG`)
  - `.info` - General informational messages
  - `.notice` - Important events worth highlighting (default level)
  - `.error` - Error conditions
  - `.fault` - Critical failures

- **Performance Tracking**:
  - `AppLogger.ImportPerformance` struct for structured import metrics
  - `AppLogger.logQueryPerformance()` for automatic query performance rating
  - Preserves all timing information for cross-machine comparisons

- **Console.app Integration**: Filter logs by subsystem and category
  ```
  subsystem:com.yourcompany.SAAQAnalyzer category:performance
  subsystem:com.yourcompany.SAAQAnalyzer level:error
  ```

- **Migration Guide**: See `Documentation/LOGGING_MIGRATION_GUIDE.md` for patterns and best practices
- **Scripts**: Command-line scripts in `Scripts/` intentionally use `print()` (appropriate for CLI tools)

### Testing Framework
- XCTest framework with basic test structure in place
- Tests located in `SAAQAnalyzerTests/`

### Platform Requirements
- **Target**: macOS (no iOS support)
- **Minimum macOS version**: Requires NavigationSplitView (macOS 13.0+)
- **Dependencies**: SQLite3, Charts framework, UniformTypeIdentifiers, OSLog

### Application Preferences

The application includes user-configurable preferences accessed via Settings (Cmd+,):

1. **Appearance Mode** ✨ *New in October 2025*
   - **Location**: Settings → General tab
   - **Options**: System (follows macOS), Light, Dark
   - **Implementation**: `@AppStorage` with `.preferredColorScheme()` modifier
   - **Persistence**: Automatic via UserDefaults
   - **Files**:
     - `DataModels.swift`: AppearanceMode enum
     - `SAAQAnalyzerApp.swift`: Settings UI and application

2. **Build Version Information** ✨ *New in October 2025*
   - **Console Logging**: Version info logged at app launch
     ```
     🚀 SAAQAnalyzer launched
     📦 Version 1.0 (196) - Built Oct 15, 2025 at 12:30 AM
     Build date: 2025-10-15T00:30:45Z
     ```
   - **Build Timestamp**: Extracted from app bundle/executable filesystem metadata
   - **Automatic Build Numbering**: Git pre-commit hook sets build number to commit count
   - **App Store Ready**: Monotonically increasing build numbers
   - **Files**:
     - `Utilities/AppVersion.swift`: Build info utility
     - `Utilities/AppLogger.swift`: Added `app` logger category
     - `.git/hooks/pre-commit`: Git hook for build numbering
   - **About Panel**: Shows version, build number, and copyright
   - **Implementation Note**: Pre-commit hook approach avoids build interruptions

## Current Implementation Status

### Integer-Based Optimization (September 2024)
- **Pivoted from migration to clean implementation approach** - Building optimized schema from scratch
- **Building integer-based schema directly during CSV import** - No migration complexity
- **Using pre-assigned Quebec geographic codes** - No separate enumeration needed:
  - Municipality codes: Direct integers (e.g., 66023 for Montréal)
  - Admin Region codes: Extract from parentheses "Abitibi-Témiscamingue (08)" → 8
  - MRC codes: Extract from parentheses "Montréal (06)" → 6
- **Testing with abbreviated CSV files** (1000 rows) before scaling to full datasets
- **Database deleted for clean slate** - Starting fresh with optimized schema

### Key Architectural Components
1. **Optimized Query System**
   - `CategoricalEnumManager.swift`: Creates and manages enumeration tables with performance indexes
   - `OptimizedQueryManager.swift`: Integer-based queries (5.6x performance improvement)
   - `FilterCacheManager.swift`: Loads filter data from enumeration tables
     - Supports "Limit to Curated Years Only" filtering (Oct 2025)
     - Efficient in-memory filtering of uncurated Make/Model pairs
     - Dual-layer filtering: UI dropdowns + query restrictions

2. **Geographic Code Handling**
   - Municipality codes are the only numeric codes requiring transformation to human-readable names
   - Admin regions and MRCs have embedded codes in parentheses that need extraction
   - License data only contains Admin Region and MRC (no municipalities)
   - Vehicle data contains all three levels of geographic hierarchy

3. **Special Cases**
   - **Municipalities**: Numeric codes need geographic entity name lookup for UI display
   - **License Classes**: Multiple boolean columns transformed to single multi-selectable filter
   - **Numeric Fields**: Vehicle mass and engine displacement remain as true integers (not enumerated)

### Performance Optimizations
- Integer foreign keys instead of string comparisons
- **Database indexes on enum table ID columns** - Critical for JOIN performance (Oct 2025)
- Covering indexes for common query patterns
- Direct use of Quebec's official numeric coding system
- Canonical geographic code set enables cross-mode filter persistence
- **Background processing** for expensive regularization operations (Oct 2025)
- **Fast-path optimizations** for SwiftUI computed properties (Oct 2025)
- **Canonical hierarchy cache** - Materialized table for regularization queries (Oct 2025)
  - Pre-aggregates Make/Model/Year/Fuel/VehicleType combinations from curated years
  - Reduces canonical hierarchy generation from 13.4s to 0.12s (109x improvement)
  - One-time cache population on first use, persists across app sessions

## File Organization

```
SAAQAnalyzer/
├── DataLayer/          # Database and import logic
│   ├── DatabaseManager.swift
│   ├── CSVImporter.swift
│   ├── GeographicDataImporter.swift
│   ├── CategoricalEnumManager.swift    # Enumeration table management
│   ├── OptimizedQueryManager.swift     # Integer-based queries
│   ├── FilterCacheManager.swift        # Enumeration-based filter cache
│   └── RegularizationManager.swift     # Make/Model/FuelType/VehicleType regularization
├── Models/             # Data structures and enums
├── UI/                 # SwiftUI views and components
├── Utilities/          # Shared utilities and infrastructure
│   └── AppLogger.swift                 # Centralized logging (os.Logger)
├── Assets.xcassets/    # App icons and colors
└── SAAQAnalyzerApp.swift   # Main app entry point
```

## Common Tasks

### Adding New Filter Types
1. Update `FilterConfiguration` struct in `DataModels.swift`
2. Add UI components in `FilterPanel.swift`
3. Update query building in `DatabaseManager.queryVehicleData()`
4. Add enumeration table if categorical data

### Adding New Chart Types
1. Extend `ChartType` enum in `ChartView.swift`
2. Add new case in the chart content switch statement
3. Update toolbar picker to include new option

### Adding New Metric Types
Follow the pattern established for Road Wear Index (October 2025):

1. **Data Model** (`DataModels.swift`):
   - Add new case to `ChartMetricType` enum with description and shortLabel
   - Add configuration properties to `FilterConfiguration` (e.g., mode enums)
   - Update `FilteredDataSeries.yAxisLabel` switch
   - Update `FilteredDataSeries.formatValue()` switch

2. **Database Query** (`DatabaseManager.swift`):
   - Add case to query switch in `queryVehicleData()` (or `queryLicenseData()`)
   - Implement SQL query logic with appropriate aggregate functions
   - Add normalization/post-processing if needed (see `normalizeToFirstYear()`)
   - Update `generateSeriesNameAsync()` to format legend strings

3. **Optimized Query** (`OptimizedQueryManager.swift`):
   - Add case to query switch in `queryVehicleDataWithIntegers()`
   - Use integer column names (e.g., `net_mass_int` instead of `net_mass`)
   - Apply same normalization logic

4. **UI Components** (`FilterPanel.swift`):
   - Add configuration controls in `MetricConfigurationSection`
   - Add binding parameter for new configuration properties
   - Update `descriptionText` switch for filter panel summary

5. **Chart Display** (`ChartView.swift`):
   - Add case to `formatYAxisValue()` switch
   - Delegate to series' `formatValue()` or provide custom formatting

**Example Files Changed for Road Wear Index**:
- `DataModels.swift`: Lines 1305, 1316, 1329, 1128-1139, 1492-1493, 1533-1542
- `DatabaseManager.swift`: Lines 399-421, 1203-1211, 1436-1440, 2409-2459
- `OptimizedQueryManager.swift`: Lines 606-616, 693-697
- `FilterPanel.swift`: Lines 1556, 200, 1731-1746, 1853-1856
- `ChartView.swift`: Lines 385-387

### Database Schema Changes
1. Update table creation SQL in `DatabaseManager.createTablesIfNeeded()`
2. Update `CategoricalEnumManager` for new enumerations
3. Update import binding in `CSVImporter` to populate integer columns directly