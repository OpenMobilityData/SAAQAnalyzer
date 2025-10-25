# SAAQAnalyzer Architectural Guide

**Purpose**: Comprehensive architectural reference to prevent regressions and guide future development
**Audience**: Claude Code sessions and human developers
**Last Updated**: October 25, 2025
**Maintainers**: Review and update at end of each significant development session

---

## Table of Contents

1. [Core Architectural Principles](#core-architectural-principles)
2. [Database Architecture](#database-architecture)
3. [Concurrency & Performance Patterns](#concurrency--performance-patterns)
4. [UI Architecture](#ui-architecture)
5. [Data Import System](#data-import-system)
6. [Caching Strategy](#caching-strategy)
7. [Logging Infrastructure](#logging-infrastructure)
8. [Common Regression Patterns](#common-regression-patterns)
9. [Critical Code Patterns](#critical-code-patterns)
10. [RWI Configuration System](#rwi-configuration-system)
11. [Decision Log](#decision-log)

---

## Core Architectural Principles

### 1. Modern Swift 6.2 First

**Mandatory Patterns:**
- ✅ Use `async/await`, `Actor`, `TaskGroup` for all concurrency
- ✅ Use `@MainActor` for UI updates
- ✅ Use structured concurrency patterns
- ❌ **NEVER** use `DispatchQueue`, `OperationQueue`, completion handlers
- ❌ **AVOID** AppKit/Foundation NS-prefixed APIs (always ask before using)

**Examples:**
```swift
// ✅ CORRECT
@MainActor
func updateUI() async {
    Task.detached(priority: .background) {
        let result = await heavyComputation()
        await MainActor.run {
            self.data = result
        }
    }
}

// ❌ WRONG
DispatchQueue.global().async {
    let result = heavyComputation()
    DispatchQueue.main.async {
        self.data = result
    }
}
```

### 2. Integer-Based Enumeration System

**CRITICAL**: ALL categorical data uses integer foreign keys. **NO** string queries on categorical data.

**Pattern:**
```sql
-- ✅ CORRECT: Integer foreign keys
CREATE TABLE vehicles (
    make_id INTEGER REFERENCES make_enum(id),
    model_id INTEGER REFERENCES model_enum(id),
    fuel_type_id INTEGER REFERENCES fuel_type_enum(id)
);

-- ❌ WRONG: String columns
CREATE TABLE vehicles (
    make TEXT,
    model TEXT,
    fuel_type TEXT
);
```

**Why This Matters:**
- **Performance**: Integer joins are ~10x faster than string joins
- **Consistency**: Single source of truth for categorical values
- **Query optimization**: Database can use covering indexes
- **Memory efficiency**: 4 bytes vs 20+ bytes per value

**Enumeration Tables:**
- `year_enum`, `make_enum`, `model_enum`, `fuel_type_enum`
- `vehicle_class_enum`, `vehicle_type_enum`, `color_enum`
- `admin_region_enum`, `mrc_enum`, `municipality_enum`
- `age_group_enum`, `gender_enum`, `license_type_enum`
- `cylinder_count_enum`, `axle_count_enum`, `model_year_enum`

**ALL queries must JOIN enumeration tables to unwrap human-readable values.**

### 3. Minimize Latency Everywhere

The application is designed for **interactive query exploration** with minimal delay.

**Performance Targets:**
- Filter dropdown population: < 1 second
- Chart query execution: < 5 seconds (millions of records)
- UI interactions: < 100ms response time
- Regularization UI: < 1 second to load list

**Strategies:**
1. **Aggressive caching** (filter cache, canonical hierarchy cache, regularization mappings)
2. **Background processing** for expensive operations (auto-regularization, package export)
3. **Fast-path optimizations** for SwiftUI computed properties
4. **Materialized views** for complex aggregations (canonical_hierarchy_cache)
5. **Covering indexes** on all query paths

### 4. Sandboxed Storage

**Database Location:** `~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/`

**NEVER** hardcode paths. Always use:
```swift
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let dbURL = documentsURL.appendingPathComponent("saaq_data.sqlite")
```

**Extension**: `.sqlite` (NOT `.db`)

### 5. Command-Line Workflow for Scripts

Scripts in `Scripts/` directory are **CLI tools**, NOT part of the app:

**Principles:**
- Generate **robust command-line invocations** for copy/paste into terminal
- User runs scripts manually to monitor output
- Scripts produce **copy-friendly output** for integration into Claude Code sessions
- **ALWAYS compile**: `swiftc Script.swift -o Script -O`
- **NEVER use shebang execution** for Foundation Models API scripts

**Appropriate for Scripts:**
- ✅ Use `print()` for output (not AppLogger)
- ✅ Direct SQLite access
- ✅ Standalone execution

**Example:**
```bash
# Database inspection
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT COUNT(*) FROM vehicles WHERE year_id = (SELECT id FROM year_enum WHERE year = 2023);"
```

---

## Database Architecture

### Schema Design

**Integer Foreign Keys Everywhere:**
```sql
-- Core vehicle table
CREATE TABLE vehicles (
    id INTEGER PRIMARY KEY,
    year_id INTEGER REFERENCES year_enum(id),
    make_id INTEGER REFERENCES make_enum(id),
    model_id INTEGER REFERENCES model_enum(id),
    fuel_type_id INTEGER REFERENCES fuel_type_enum(id),
    vehicle_type_id INTEGER REFERENCES vehicle_type_enum(id),
    -- ... other fields
);

-- Enumeration table pattern
CREATE TABLE make_enum (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL
);

CREATE INDEX idx_make_enum_id ON make_enum(id);  -- CRITICAL for JOINs
```

### Critical Indexes

**Performance Lesson**: The October 11, 2025 regularization optimization reduced query time from **165s → <10s** (16x improvement) by adding indexes to enumeration table `id` columns.

**Required Indexes:**
```sql
-- Enum table ID columns (for JOINs)
CREATE INDEX idx_year_enum_id ON year_enum(id);
CREATE INDEX idx_make_enum_id ON make_enum(id);
CREATE INDEX idx_model_enum_id ON model_enum(id);
-- ... (all enum tables)

-- Main table foreign keys
CREATE INDEX idx_vehicles_year_id ON vehicles(year_id);
CREATE INDEX idx_vehicles_make_id ON vehicles(make_id);
CREATE INDEX idx_vehicles_model_id ON vehicles(model_id);
-- ... (all foreign keys)

-- Composite indexes for common queries
CREATE INDEX idx_vehicles_year_make_model
  ON vehicles(year_id, make_id, model_id);
```

### Configuration

```swift
// DatabaseManager initialization
sqlite3_config(SQLITE_CONFIG_SERIALIZED)  // Thread-safe
sqlite3_exec(db, "PRAGMA journal_mode=WAL")  // Concurrent reads
sqlite3_exec(db, "PRAGMA cache_size=-\(cacheSizeKB)")  // 8GB cache on M3 Ultra
sqlite3_exec(db, "PRAGMA mmap_size=\(mmapSizeBytes)")  // 32GB memory-mapped I/O
sqlite3_exec(db, "PRAGMA temp_store=MEMORY")  // In-memory temp tables
```

### Materialized Caches

**Canonical Hierarchy Cache** (October 11, 2025):

**Problem**: 6-way JOIN on 10M+ records took 13.4 seconds to generate canonical Make/Model hierarchy.

**Solution**: Pre-aggregate into `canonical_hierarchy_cache` table:
```sql
CREATE TABLE canonical_hierarchy_cache (
    make_id INTEGER,
    make_name TEXT,
    model_id INTEGER,
    model_name TEXT,
    model_year_id INTEGER,
    model_year INTEGER,
    fuel_type_id INTEGER,
    fuel_type_code TEXT,
    vehicle_type_id INTEGER,
    vehicle_type_code TEXT,
    record_count INTEGER,
    PRIMARY KEY (make_id, model_id, model_year_id, fuel_type_id, vehicle_type_id)
);
```

**Result**: 13.4s → 0.12s (109x improvement)

**Lesson**: For expensive queries that don't change often (curated years are static 2011-2022), materialize results once and query cache.

---

## Concurrency & Performance Patterns

### 1. Background Task Pattern

**Problem**: SwiftUI's AttributeGraph crashes when state updates occur during view rendering.

**Solution**: Use manual button triggers + background tasks:

```swift
// ✅ CORRECT: Manual button + background task
Button("Filter Models") {
    Task {
        await filterModelsBySelectedMakes()
    }
}

private func filterModelsBySelectedMakes() async {
    // Background work
    let filtered = await filterCache.getAvailableModels(forMakeIds: selectedMakes)

    // UI update on main actor
    await MainActor.run {
        filteredModels = filtered
        isModelListFiltered = true
    }
}

// ❌ WRONG: Automatic update via onChange
.onChange(of: selectedMakes) { newValue in
    Task { await filterModelsBySelectedMakes() }  // CRASH!
}
```

**Lesson from October 14, 2025**: AttributeGraph has hard limits on circular dependencies. ALL filter state updates MUST be user-triggered (button clicks), never automatic (onChange handlers).

### 2. Fast-Path for Computed Properties

**Problem**: SwiftUI recomputes ALL computed properties on EVERY @Published change. With 100K+ items, this causes beachballs.

**Solution**: Add fast-path checks:

```swift
// ✅ CORRECT: Fast-path optimization
var statusCounts: (unassigned: Int, needsReview: Int, complete: Int) {
    let totalPairs = viewModel.uncuratedPairs.count

    // Fast path: if no mappings exist yet, everything is unassigned
    if viewModel.existingMappings.isEmpty {
        return (unassigned: totalPairs, needsReview: 0, complete: 0)
    }

    // Only do expensive computation when necessary
    var unassigned = 0
    var needsReview = 0
    var complete = 0
    for pair in viewModel.uncuratedPairs {
        let status = viewModel.getRegularizationStatus(for: pair)
        // ... categorize
    }
    return (unassigned, needsReview, complete)
}

// ❌ WRONG: Always expensive
var statusCounts: (unassigned: Int, needsReview: Int, complete: Int) {
    // Always loops through 100K+ items!
    for pair in viewModel.uncuratedPairs {
        let status = viewModel.getRegularizationStatus(for: pair)
        // ...
    }
}
```

**Lesson from October 11, 2025**: Regularization UI blocked for minutes until fast-path added.

### 3. Foundation Models API Pattern

**CRITICAL**: Foundation Models API requires specific execution pattern.

```swift
// ✅ CORRECT
@MainActor
func main() async throws {
    // Main logic here
    let session = LanguageModelSession(instructions: "...")
    let response = try await session.respond(to: prompt)
}

try await main()

// ❌ WRONG: Causes hangs
Task { @MainActor in
    // Main logic here
}
RunLoop.main.run()  // HANGS INDEFINITELY
```

**Lesson from October 4-5, 2025**: Make/Model standardization scripts hung until pattern corrected.

### 4. Thread-Safe Database Access

**Problem**: SQLite is NOT thread-safe across concurrent tasks.

**Solution**: Pass database PATHS (strings), not connections:

```swift
// ✅ CORRECT: Each task opens its own connection
await withTaskGroup(of: Result.self) { group in
    for pair in pairs {
        group.addTask {
            let db = try DatabaseHelper(path: dbPath)  // Fresh connection
            return await processPair(pair, db: db)
        }
    }
}

// ❌ WRONG: Shared connection
let db = try DatabaseHelper(path: dbPath)
await withTaskGroup(of: Result.self) { group in
    for pair in pairs {
        group.addTask {
            return await processPair(pair, db: db)  // CRASH!
        }
    }
}
```

**Lesson from October 5, 2025**: Segmentation faults until pattern corrected.

### 5. Selective Table Analysis

**Problem**: `ANALYZE` without table name analyzes entire database (can take minutes on 35GB+ databases).

**Solution**: Always specify table name:

```swift
// ✅ CORRECT: Table-specific
sqlite3_exec(db, "ANALYZE vehicles")

// ❌ WRONG: Analyzes everything
sqlite3_exec(db, "ANALYZE")
```

**Lesson from October 15, 2025**: License imports hung for minutes analyzing entire vehicle database (35GB) when only needed to analyze licenses table (< 1MB).

---

## UI Architecture

### Three-Panel Layout

**NavigationSplitView** with responsive column visibility:

```
┌──────────────────────────────────────────────────────┐
│ ┌─────────────┐ ┌──────────────┐ ┌────────────────┐ │
│ │   Filters   │ │    Charts    │ │  Data Details  │ │
│ │             │ │              │ │                │ │
│ │ • Analytics │ │  Line chart  │ │  Selected      │ │
│ │ • Years     │ │  Bar chart   │ │  data point    │ │
│ │ • Geography │ │  Area chart  │ │  breakdown     │ │
│ │ • Vehicle   │ │              │ │                │ │
│ └─────────────┘ └──────────────┘ └────────────────┘ │
└──────────────────────────────────────────────────────┘
```

### Filter Panel Architecture (October 14, 2025)

**Two Top-Level Sections:**

1. **Analytics Section** (200-600pt, draggable divider):
   - Y-Axis Metric selection
   - Metric-specific configuration (RWI mode, coverage field, etc.)
   - Normalize to First Year toggle
   - Cumulative Sum toggle

2. **Filters Section** (scrollable):
   - Filter Options (Vehicle mode only: Limit to Curated Years, Enable Regularization, etc.)
   - Years (when) - **Data-type-aware**: queries vehicle/license tables separately
   - Geographic Location (where)
   - Vehicle/License Characteristics (what/who)

**Critical UI Patterns**:
- Manual "Filter by Selected Makes" button avoids AttributeGraph crashes from automatic hierarchical filtering
- Filter Options section hidden in license mode (not applicable to license data)
- Year ranges reflect actual data availability per data type (vehicles: 2011-2024, licenses: 2011-2022)
- Progress badges show data-type-aware curation status

### SwiftUI Performance Patterns

```swift
// ✅ CORRECT: Efficient list rendering
LazyVStack {
    ForEach(filteredItems) { item in
        RowView(item: item)
    }
}

// ❌ WRONG: Loads all items at once
VStack {
    ForEach(allItems) { item in  // 100K+ items!
        RowView(item: item)
    }
}
```

---

## Data Import System

### CSV Import Architecture

**Delegation Pattern** (established October 15, 2025):

```
┌──────────────┐
│ CSVImporter  │  Parses CSV files, handles encoding
└──────┬───────┘
       │ delegates to
       ▼
┌──────────────────┐
│ DatabaseManager  │  Populates enum tables, inserts records
└──────────────────┘
```

**Why**: Separation of concerns (file parsing vs database operations).

### Enum Population During Import

**Pattern:**
```swift
func importVehicleBatch(_ records: [VehicleRecord], year: Int) async throws {
    // 1. Load existing enum values into in-memory caches
    var makeEnumCache: [String: Int] = [:]
    loadEnumCache(table: "make_enum", keyColumn: "name", cache: &makeEnumCache)

    // 2. For each record, get or create enum ID
    for record in records {
        let makeId = getOrCreateEnumId(
            table: "make_enum",
            column: "name",
            value: record.make,
            cache: &makeEnumCache
        )

        // 3. Write integer ID to main table
        sqlite3_bind_int(stmt, index, Int32(makeId))
    }
}
```

**Why**: Pre-loading enum cache avoids N database queries per record (1000x improvement for large batches).

### Data-Type-Aware Operations

**CRITICAL**: License imports should NOT load vehicle caches (10,000+ make/model pairs).

```swift
// ✅ CORRECT: Pass dataType through entire chain
func endBulkImport(dataType: DataEntityType = .vehicle) async {
    // ...
    await refreshAllCachesAfterBatchImport(dataType: dataType)
}

func refreshAllCachesAfterBatchImport(dataType: DataEntityType) async {
    await filterCacheManager.initializeCache(for: dataType)
}

func initializeCache(for dataType: DataEntityType?) async {
    if dataType == .vehicle || dataType == nil {
        try await loadVehicleCaches()  // Makes, Models, Colors, etc.
    }
    if dataType == .license || dataType == nil {
        try await loadLicenseCaches()  // AgeGroups, Genders, etc.
    }
}

// ❌ WRONG: Loads everything
func refreshAllCaches() async {
    await loadVehicleCaches()  // Expensive!
    await loadLicenseCaches()  // Even for vehicle imports!
}
```

**Lesson from October 15, 2025**: License imports hung for 30+ seconds loading vehicle caches until selective loading implemented.

### Security-Scoped Resource Access

**macOS Sandbox Requirement**: Files outside container need explicit permission.

```swift
// ✅ CORRECT: Request access before reading
let accessing = fileURL.startAccessingSecurityScopedResource()
defer {
    if accessing {
        fileURL.stopAccessingSecurityScopedResource()
    }
}

// Now can read file
let data = try Data(contentsOf: fileURL)
```

**Required for**: CSV imports from external disks, data package imports.

---

## Caching Strategy

### Filter Cache Architecture

**Three-Layer Separation:**

1. **Shared Caches** (loaded for both vehicle and license):
   - Years (14 items)
   - Admin Regions (17 items)
   - MRCs (104 items)
   - Municipalities (917 items)

2. **Vehicle-Only Caches**:
   - Makes (~200 items)
   - Models (~2000+ items)
   - Colors (~20 items)
   - Fuel Types (~10 items)
   - Vehicle Classes (~21 items)
   - Vehicle Types (~13 items)
   - Regularization mappings (355 pairs + 1627 triplets)

3. **License-Only Caches**:
   - Age Groups (8 items)
   - Genders (2-3 items)
   - License Types (3-5 items)

**Invalidation Triggers:**
- CSV import (data changed)
- Data package import (database replaced)
- Regularization Manager close (mappings may have changed)

**Performance**: Filter dropdowns populate in < 1 second because data is cached in memory.

### Canonical Hierarchy Cache

**Purpose**: Pre-aggregate Make/Model/Year/Fuel/VehicleType combinations from curated years.

**Population**: On-demand (first query), persists across sessions.

**Performance**: 13.4s → 0.12s (109x improvement) for regularization UI load.

**Key Insight**: Static data (curated years 2011-2022 don't change) should be materialized once, not recomputed every session.

---

## Logging Infrastructure

### Always Use os.Logger

**CRITICAL**: Production code uses `os.Logger` (AppLogger), NOT `print()`.

```swift
// ✅ CORRECT: Production code
AppLogger.database.info("Importing \(fileName, privacy: .public)")
AppLogger.logQueryPerformance(
    queryType: "Canonical Hierarchy",
    duration: executionTime,
    dataPoints: hierarchyCount
)

// ❌ WRONG: Production code
print("Importing \(fileName)")
```

**Exception**: CLI scripts in `Scripts/` directory can use `print()`.

### Log Categories

```swift
AppLogger.database      // Database connections, schema, transactions
AppLogger.dataImport    // CSV import operations
AppLogger.query         // Query execution and optimization
AppLogger.cache         // Filter cache operations
AppLogger.regularization // Regularization system
AppLogger.ui            // UI events
AppLogger.performance   // Performance benchmarks
AppLogger.geographic    // Geographic data operations
```

### Performance Logging

```swift
let performance = AppLogger.ImportPerformance(
    totalRecords: totalRecords,
    parseTime: parseTime,
    importTime: importTime,
    totalTime: totalTime
)
performance.log(logger: AppLogger.performance, fileName: fileName, year: year)
```

**Why**: Structured performance logs enable cross-machine comparisons and regression detection.

### Console.app Filtering

```bash
# View specific category
subsystem:com.endoquant.SAAQAnalyzer category:performance

# View errors only
subsystem:com.endoquant.SAAQAnalyzer level:error
```

---

## Common Regression Patterns

### 1. String Queries on Categorical Data

**Symptom**: Slow queries, full table scans.

**Root Cause**: Querying string columns instead of integer foreign keys.

**Example:**
```swift
// ❌ WRONG
"SELECT * FROM vehicles WHERE make = 'HONDA'"

// ✅ CORRECT
"SELECT * FROM vehicles
 WHERE make_id = (SELECT id FROM make_enum WHERE name = 'HONDA')"
```

**Prevention**: ALWAYS use integer foreign keys. NEVER add string columns for categorical data.

### 2. Missing Cache Invalidation

**Symptom**: UI shows stale data after import.

**Root Cause**: Cache not invalidated/rebuilt after database changes.

**Example:**
```swift
// ❌ WRONG: Import without cache refresh
await importCSVFile(url)
// UI still shows old data!

// ✅ CORRECT: Invalidate + rebuild
await importCSVFile(url)
await filterCacheManager.invalidateCache()
await filterCacheManager.initializeCache()
```

**Prevention**: Always call `invalidateCache()` before `initializeCache()` after data changes.

### 3. AppKit API Usage

**Symptom**: Code review request for NS-prefixed API.

**Root Cause**: Legacy Foundation/AppKit API used without asking.

**Example:**
```swift
// ⚠️ ASK FIRST: AppKit usage
let panel = NSOpenPanel()  // Legacy API - ask before using

// ✅ PREFER: SwiftUI equivalents
.fileImporter(isPresented: $showingImporter) { result in
    // Modern SwiftUI pattern
}
```

**Prevention**: ALWAYS ask human developer before using NS-prefixed APIs.

### 4. Main Thread Blocking

**Symptom**: UI freezes, beachball cursor.

**Root Cause**: Expensive operation on main thread.

**Example:**
```swift
// ❌ WRONG: Blocks UI
func loadData() {
    let data = expensiveComputation()  // 10+ seconds
    self.data = data
}

// ✅ CORRECT: Background task
func loadData() async {
    Task.detached(priority: .background) {
        let data = await expensiveComputation()
        await MainActor.run {
            self.data = data
        }
    }
}
```

**Prevention**: Use `Task.detached` for operations > 100ms. Update UI on MainActor.

### 5. AttributeGraph Crashes

**Symptom**: `precondition failure: exhausted data space` or `cycle detected through attribute`.

**Root Cause**: Automatic state updates during view rendering via `onChange`.

**Example:**
```swift
// ❌ WRONG: Automatic update
.onChange(of: selectedMakes) { _ in
    Task { await filterModels() }  // CRASH!
}

// ✅ CORRECT: Manual button
Button("Filter Models") {
    Task { await filterModels() }
}
```

**Prevention**: All filter state updates MUST be user-triggered (button clicks), never automatic.

### 6. Shared Database Connections

**Symptom**: Segmentation faults, crashes in concurrent code.

**Root Cause**: Multiple tasks sharing same SQLite connection.

**Example:**
```swift
// ❌ WRONG: Shared connection
let db = try openDatabase(path)
await withTaskGroup { group in
    for item in items {
        group.addTask {
            queryDatabase(db, item)  // CRASH!
        }
    }
}

// ✅ CORRECT: Pass path, open per-task
await withTaskGroup { group in
    for item in items {
        group.addTask {
            let db = try openDatabase(path)  // Fresh connection
            queryDatabase(db, item)
        }
    }
}
```

**Prevention**: Pass database paths (strings) to concurrent tasks, not connections.

### 7. Missing Indexes on Enum Tables

**Symptom**: Slow JOIN queries (seconds instead of milliseconds).

**Root Cause**: No index on enumeration table `id` columns.

**Example:**
```sql
-- ❌ WRONG: No index on id
CREATE TABLE make_enum (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE
);

-- ✅ CORRECT: Index on id for JOINs
CREATE TABLE make_enum (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE
);
CREATE INDEX idx_make_enum_id ON make_enum(id);
```

**Prevention**: ALWAYS add index on enum table `id` columns. October 11, 2025 optimization added 9 indexes, improved performance 16x.

### 8. Loading Wrong Caches

**Symptom**: License import hangs for 30+ seconds.

**Root Cause**: Loading vehicle caches (10,000+ items) during license import.

**Example:**
```swift
// ❌ WRONG: Loads all caches
func afterImport() {
    loadVehicleCaches()  // 10,000+ makes/models
    loadLicenseCaches()
}

// ✅ CORRECT: Data-type aware
func afterImport(dataType: DataEntityType) {
    if dataType == .vehicle {
        loadVehicleCaches()
    }
    if dataType == .license {
        loadLicenseCaches()  // Only 20 items
    }
}
```

**Prevention**: Pass `dataType` parameter through entire import/cache refresh chain.

### 9. Sheet-Scoped ViewModel Losing Cache

**Symptom**: Sheet has loading delay (>1s) on every open, even when no data changed.

**Root Cause**: ViewModel scoped to sheet lifecycle, destroyed on dismiss.

**Example**:
```swift
// ❌ WRONG: New ViewModel created on every sheet open
.sheet(isPresented: $showing) {
    DataEditorView(database: db)  // Passes dependencies, creates new ViewModel inside
}

struct DataEditorView: View {
    @StateObject private var viewModel: DataViewModel  // Destroyed on sheet dismiss!

    init(database: Database) {
        _viewModel = StateObject(wrappedValue: DataViewModel(database: database))
    }
}
```

**Impact**:
- User closes/reopens sheet → 60+ second reload
- Database cache exists but ViewModel discarded it
- Violates "aggressive caching" principle

**Fix**:
```swift
// ✅ CORRECT: Parent-scoped ViewModel
@State private var dataViewModel: DataViewModel?

.sheet(isPresented: $showing) {
    if dataViewModel == nil {
        dataViewModel = DataViewModel(database: db)
    }
    if let vm = dataViewModel {
        DataEditorView(viewModel: vm)
    }
}
```

**Prevention**: Ask "Will this ViewModel cache expensive data?" If yes, scope to parent.

**Real Example**: `RegularizationView` (Oct 21, 2025) - Moving ViewModel to parent scope reduced reopen time from >60s to <1s.

---

## Critical Code Patterns

### Pattern 1: Enum Population

```swift
// Step 1: Load existing values into cache
var makeCache: [String: Int] = [:]
func loadEnumCache(table: String, keyColumn: String, cache: inout [String: Int]) {
    let sql = "SELECT id, \(keyColumn) FROM \(table)"
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    while sqlite3_step(stmt) == SQLITE_ROW {
        let id = Int(sqlite3_column_int(stmt, 0))
        let key = String(cString: sqlite3_column_text(stmt, 1))
        cache[key] = id
    }
    sqlite3_finalize(stmt)
}

// Step 2: Get or create ID
func getOrCreateEnumId(table: String, column: String, value: String, cache: inout [String: Int]) -> Int? {
    // Check cache
    if let id = cache[value] {
        return id
    }

    // Insert new value
    let sql = "INSERT INTO \(table) (\(column)) VALUES (?) RETURNING id"
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    sqlite3_bind_text(stmt, 1, value, -1, nil)
    if sqlite3_step(stmt) == SQLITE_ROW {
        let id = Int(sqlite3_column_int(stmt, 0))
        cache[value] = id
        sqlite3_finalize(stmt)
        return id
    }
    sqlite3_finalize(stmt)
    return nil
}
```

### Pattern 2: Background Task with UI Update

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var data: [Item] = []
    @Published var isLoading = false

    func loadData() {
        Task.detached(priority: .background) {
            // Background work
            let result = await self.performExpensiveQuery()

            // UI update on main actor
            await MainActor.run {
                self.data = result
                self.isLoading = false
            }
        }
    }
}
```

### Pattern 3: Data-Type-Aware Cache Refresh

```swift
// Import caller
await databaseManager.endBulkImport(dataType: .vehicle)

// DatabaseManager
func endBulkImport(dataType: DataEntityType = .vehicle) async {
    sqlite3_exec(db, "COMMIT")
    sqlite3_exec(db, "ANALYZE \(dataType == .vehicle ? "vehicles" : "licenses")")
    await refreshAllCachesAfterBatchImport(dataType: dataType)
}

// Cache refresh
func refreshAllCachesAfterBatchImport(dataType: DataEntityType) async {
    await filterCacheManager.invalidateCache()
    await filterCacheManager.initializeCache(for: dataType)
}

// FilterCacheManager
func initializeCache(for dataType: DataEntityType?) async {
    guard !isInitialized else { return }

    // Shared caches (always load)
    try await loadYears()
    try await loadRegions()

    // Conditional caches
    if dataType == .vehicle || dataType == nil {
        try await loadMakes()
        try await loadModels()
        // ... vehicle-specific caches
    }

    if dataType == .license || dataType == nil {
        try await loadAgeGroups()
        try await loadGenders()
        // ... license-specific caches
    }

    isInitialized = true
}
```

### Pattern 4: Foundation Models API

```swift
// Script setup
@MainActor
func main() async throws {
    // Main logic here
    await withTaskGroup(of: Result.self) { group in
        for pair in pairs {
            group.addTask {
                // Create fresh session per task
                let session = LanguageModelSession(instructions: "...")
                let response = try await session.respond(to: prompt)
                return parseResponse(response)
            }
        }
    }
}

// Entry point
try await main()
```

### Pattern 5: Security-Scoped Resource Access

```swift
func importFile(at url: URL) async throws {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // Now can access file
    let data = try Data(contentsOf: url)
    await processData(data)
}
```

### Pattern 6: Persistent Sheet ViewModel

**Problem**: Sheet contains expensive data that takes >1s to load, user opens/closes frequently.

**Solution**: Scope ViewModel to parent, pass as dependency to sheet.

```swift
// Parent view manages ViewModel lifecycle
struct SettingsView: View {
    @State private var showingExpensiveSheet = false
    @State private var expensiveViewModel: ExpensiveViewModel?

    var body: some View {
        Button("Open") { showingExpensiveSheet = true }
            .sheet(isPresented: $showingExpensiveSheet) {
                sheetContent()
            }
    }

    @ViewBuilder
    private func sheetContent() -> some View {
        // Lazy initialization on first open
        if expensiveViewModel == nil {
            expensiveViewModel = ExpensiveViewModel(dependencies...)
        }

        if let viewModel = expensiveViewModel {
            ExpensiveSheet(viewModel: viewModel)
        }
    }
}

// Sheet view observes but doesn't own
struct ExpensiveSheet: View {
    @ObservedObject var viewModel: ExpensiveViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ExpensiveViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ContentView()
            .onAppear {
                // Only load if data not already cached
                if viewModel.cachedData.isEmpty && !viewModel.isLoading {
                    Task { await viewModel.loadData() }
                }
            }
    }
}
```

**Key Points**:
- Parent owns ViewModel with `@State`
- Sheet receives ViewModel via `@ObservedObject`
- Conditional loading checks if data already cached
- ViewModel survives sheet dismiss → instant reopen

**Example**: `RegularizationSettingsView` owns `RegularizationViewModel`, passes to `RegularizationView` sheet. Reopen time: 60s → <1s.

---

## RWI Configuration System

**Added**: October 24, 2025

### Overview

The Road Wear Index (RWI) calculation system is fully user-configurable, making assumptions transparent and allowing customization for different analytical scenarios. All configuration is managed via Settings → Road Wear Index tab.

### Architecture

**Two-Tier Fallback Strategy:**
1. **Primary**: Actual axle count data (when `max_axles` is not NULL)
2. **Fallback**: Vehicle type assumptions (when `max_axles` is NULL)
3. **Default**: Wildcard fallback for unknown vehicle types

**Configuration Model:**
- `RWIConfigurationData`: Root configuration object
  - `axleConfigurations`: [Int: AxleConfiguration] - Keyed by axle count (2-6)
  - `vehicleTypeFallbacks`: [String: VehicleTypeFallback] - Keyed by type code
  - `schemaVersion`: Int - For future migrations
- `AxleConfiguration`: Axle-specific weight distributions
  - `axleCount`: Int
  - `weightDistribution`: [Double] - Percentages (must sum to 100%)
  - `coefficient`: Double - Auto-calculated from distribution
- `VehicleTypeFallback`: Vehicle type assumptions
  - `typeCode`: String - "CA", "VO", "AB", "AU", "*"
  - `assumedAxles`: Int
  - `weightDistribution`: [Double]
  - `coefficient`: Double

### Calculation Flow

1. User modifies settings via `RWISettingsView`
2. Settings saved to UserDefaults (JSON encoded)
3. `RWICalculator` reads configuration from `RWIConfigurationManager`
4. SQL CASE expression generated dynamically
5. SQL embedded in vehicle queries via `QueryManager`
6. Database executes query with custom coefficients

### Coefficient Calculation

**Formula**: Coefficient = Σ(weight_fraction⁴)

**Example** (3 axles, 30/35/35 distribution):
```
Coefficient = (0.30)⁴ + (0.35)⁴ + (0.35)⁴ = 0.0234
```

**Rationale**: 4th power law of road wear - damage is proportional to (axle load)⁴

### SQL Generation

`RWICalculator` generates dynamic SQL CASE expression:

```sql
CASE
    -- Axle-based (when max_axles is not NULL)
    WHEN v.max_axles = 2 THEN 0.1325 * POWER(v.net_mass_int, 4)
    WHEN v.max_axles = 3 THEN 0.0234 * POWER(v.net_mass_int, 4)
    WHEN v.max_axles = 4 THEN 0.0156 * POWER(v.net_mass_int, 4)
    WHEN v.max_axles = 5 THEN 0.0080 * POWER(v.net_mass_int, 4)
    WHEN v.max_axles >= 6 THEN 0.0046 * POWER(v.net_mass_int, 4)
    -- Vehicle type fallbacks (when max_axles is NULL)
    WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'CA')
    THEN 0.0234 * POWER(v.net_mass_int, 4)
    WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'AB')
    THEN 0.1935 * POWER(v.net_mass_int, 4)
    -- Default wildcard
    ELSE 0.125 * POWER(v.net_mass_int, 4)
END
```

### Performance Optimization

**SQL Caching**: Generated SQL is cached using configuration hash
- Cache hit: <0.001ms
- Cache miss: <1ms (negligible compared to query execution)
- Cache invalidation: Automatic on configuration change

```swift
private static var cachedSQL: String?
private static var lastConfigHash: Int?

func generateSQLCalculation() -> String {
    let currentHash = configManager.configuration.hashValue
    if let cached = Self.cachedSQL, Self.lastConfigHash == currentHash {
        return cached
    }
    // Generate fresh SQL...
}
```

### Storage and Persistence

**UserDefaults with JSON Encoding:**
- Key: `"rwiConfiguration"`
- Format: JSON (exportable/importable)
- Versioning: `schemaVersion` field for future migrations
- Fallback: Default configuration if missing/corrupt

**File Locations:**
- `Settings/RWIConfiguration.swift`: Data models
- `Settings/RWIConfigurationManager.swift`: Storage and persistence
- `Utilities/RWICalculator.swift`: SQL generation
- `Settings/RWISettings.swift`: Settings UI
- `Settings/RWIEditDialogs.swift`: Edit dialogs

### Validation

**Real-time Validation in UI:**
- Weight distributions must sum to 100% (±0.01% tolerance)
- All weights must be > 0 and ≤ 100
- Number of weights must match axle count
- Axle count must be 2-6
- Save button disabled until valid

**Validation on Import:**
- JSON schema validation
- Data integrity checks
- Coefficient recalculation verification
- Graceful error handling with user feedback

### Import/Export

**Export Format** (JSON, pretty-printed):
```json
{
  "axleConfigurations": {
    "2": {
      "axleCount": 2,
      "weightDistribution": [45.0, 55.0],
      "coefficient": 0.1325
    },
    ...
  },
  "vehicleTypeFallbacks": {
    "CA": {
      "typeCode": "CA",
      "description": "Truck",
      "assumedAxles": 3,
      "weightDistribution": [30.0, 35.0, 35.0],
      "coefficient": 0.0234
    },
    ...
  },
  "schemaVersion": 1
}
```

**Use Cases:**
- Share configurations across machines
- Backup settings before experimentation
- Collaborate on analytical scenarios
- Document methodology for research

### Extensibility

**Future Enhancements:**
- Make/Model-specific overrides
- Year-specific coefficient adjustments
- Multiple named presets
- Visual coefficient calculator
- Comparative analysis tools

**Design Accommodates:**
- Schema versioning for migrations
- Additional configuration properties
- New calculation methods
- Custom validation rules

---

## Decision Log

### Database Architecture Decisions

**Sept 2024: Integer Enumeration System**
- **Decision**: ALL categorical data uses integer foreign keys
- **Rationale**: 10x query performance improvement, enables covering indexes
- **Impact**: Complete schema redesign, all imports updated
- **Status**: Production standard

**Oct 11, 2025: Canonical Hierarchy Cache**
- **Decision**: Materialize Make/Model/Year/Fuel/VehicleType combinations
- **Rationale**: 13.4s → 0.12s (109x improvement) for regularization UI
- **Impact**: One-time cache population, persists across sessions
- **Status**: Production ready

**Oct 11, 2025: Enum Table Indexes**
- **Decision**: Add indexes on all enum table `id` columns
- **Rationale**: 165s → <10s (16x improvement) for hierarchy generation
- **Impact**: 9 indexes added, no breaking changes
- **Status**: Production standard

### Concurrency Decisions

**Oct 4-5, 2025: Foundation Models API Pattern**
- **Decision**: Use `@MainActor func main() async throws` + `try await main()`
- **Rationale**: `Task + RunLoop.main.run()` pattern caused indefinite hangs
- **Impact**: All AI standardization scripts updated
- **Status**: Production standard for Foundation Models API

**Oct 5, 2025: Thread-Safe Database Access**
- **Decision**: Pass database paths (strings) to concurrent tasks, not connections
- **Rationale**: SQLite not thread-safe; segfaults with shared connections
- **Impact**: All TaskGroup code updated
- **Status**: Production standard

**Oct 11, 2025: Background Processing for Expensive Operations**
- **Decision**: Use `Task.detached(priority: .background)` for auto-regularization
- **Rationale**: Eliminated 200+ second UI blocking
- **Impact**: UI appears immediately, work continues in background
- **Status**: Production standard

### UI Architecture Decisions

**Oct 13, 2025: Analytics/Filters Separation**
- **Decision**: Split filter panel into two top-level sections with draggable divider
- **Rationale**: Clear separation between "what to measure" and "what to query"
- **Impact**: Improved UX, better discoverability
- **Status**: Production standard

**Oct 14, 2025: Manual Hierarchical Filtering**
- **Decision**: Manual button for Make → Model filtering, NOT automatic onChange
- **Rationale**: SwiftUI AttributeGraph crashes on automatic state updates
- **Impact**: Zero crashes, slight UX trade-off (one extra click)
- **Status**: Production workaround for AttributeGraph limitations

**Oct 14, 2025: Normalize to First Year as Global Toggle**
- **Decision**: Promote normalization from RWI-specific to global metric toggle
- **Rationale**: Useful for all metrics (trend analysis, comparison)
- **Impact**: Applies to Count, Sum, Average, RWI, Percentage, Coverage
- **Status**: Production feature

**Oct 21, 2025: Persistent Sheet ViewModels**
- **Decision**: Scope ViewModels with expensive data to parent, not sheet
- **Rationale**: Sheet-scoped ViewModels destroyed on dismiss, lose all cached data
- **Impact**: Regularization Manager reopen went from >60s to <1s
- **Pattern**: Parent owns with `@State`, sheet observes with `@ObservedObject`
- **Status**: Production pattern for all expensive sheets

### Import System Decisions

**Oct 15, 2025: Delegation Pattern**
- **Decision**: CSVImporter → delegates to → DatabaseManager for enum population
- **Rationale**: Separation of concerns (file parsing vs database operations)
- **Impact**: Cleaner code, easier testing
- **Status**: Production standard

**Oct 15, 2025: Data-Type-Aware Cache Refresh**
- **Decision**: Pass `dataType` parameter through entire import/cache chain
- **Rationale**: License imports shouldn't load vehicle caches (30+ second hang)
- **Impact**: License imports now complete in < 10 seconds
- **Status**: Production standard

**Oct 15, 2025: Table-Specific ANALYZE**
- **Decision**: `ANALYZE {tableName}` instead of `ANALYZE`
- **Rationale**: License imports hung analyzing 35GB vehicle table
- **Impact**: License imports complete quickly
- **Status**: Production standard

### Logging Decisions

**Oct 10, 2025: os.Logger Migration**
- **Decision**: All production code uses os.Logger (AppLogger), NOT print()
- **Rationale**: Console.app integration, performance, structured logging
- **Impact**: Migration plan created, 5/7 core files complete
- **Status**: In progress (DatabaseManager pending)

**Exception**: CLI scripts in `Scripts/` directory can use `print()`.

---

## Review & Maintenance

**When to Update This Guide:**
- After implementing major architectural changes
- When discovering new regression patterns
- After performance optimizations
- At end of significant development sessions

**How to Review:**
1. Compare current session work against principles in this guide
2. Check for new patterns or lessons learned
3. Update relevant sections
4. Commit changes with descriptive message

**Last Review**: October 21, 2025 (Initial creation from session notes)

---

## Quick Reference Checklist

Before starting new work, verify:

- [ ] Am I using integer foreign keys for categorical data?
- [ ] Will this query need an index on enum table ids?
- [ ] Should this expensive operation run in background?
- [ ] Does this state update need MainActor.run?
- [ ] Am I about to use an NS-prefixed API? (Ask first!)
- [ ] Will this import invalidate caches? (Call invalidateCache)
- [ ] Is this operation data-type aware? (Pass dataType)
- [ ] Am I using os.Logger for production code? (Not print)
- [ ] Will this onChange handler trigger during rendering? (Use button instead)
- [ ] Am I passing a database path to concurrent tasks? (Not connection)

---

**This guide is a living document. Update it as the architecture evolves.**
