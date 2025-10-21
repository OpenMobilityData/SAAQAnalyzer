# SAAQAnalyzer Quick Reference

**Purpose**: Essential patterns and checks for every development session
**Read Time**: 5 minutes
**Full Details**: See [ARCHITECTURAL_GUIDE.md](ARCHITECTURAL_GUIDE.md)

---

## Pre-Development Checklist

Before writing any code, verify:

- [ ] Am I using **integer foreign keys** for categorical data? (NOT strings)
- [ ] Will this query need an **index on enum table IDs**?
- [ ] Should this expensive operation run in **background**? (>100ms)
- [ ] Does this state update need **MainActor.run**?
- [ ] Am I about to use an **NS-prefixed API**? (**ASK FIRST!**)
- [ ] Will this import **invalidate caches**? (Call invalidateCache → initializeCache)
- [ ] Is this operation **data-type aware**? (Pass dataType parameter)
- [ ] Am I using **os.Logger** for production code? (NOT print())
- [ ] Will this **onChange** trigger during rendering? (Use button instead)
- [ ] Am I passing a **database PATH** to concurrent tasks? (NOT connection)

---

## Critical Rules (Regression Prevention)

### 1. Integer Enumeration ONLY ⚠️

```swift
// ✅ CORRECT: Integer foreign keys
CREATE TABLE vehicles (
    make_id INTEGER REFERENCES make_enum(id),
    model_id INTEGER REFERENCES model_enum(id)
);

// Query with JOIN
SELECT make_enum.name, model_enum.name
FROM vehicles
JOIN make_enum ON vehicles.make_id = make_enum.id
JOIN model_enum ON vehicles.model_id = model_enum.id;

// ❌ WRONG: String columns
CREATE TABLE vehicles (
    make TEXT,
    model TEXT
);

// ❌ WRONG: String queries
SELECT * FROM vehicles WHERE make = 'HONDA';
```

**Why**: 10x performance improvement, enables covering indexes.

### 2. Always Ask Before NS-Prefixed APIs ⚠️

```swift
// ⚠️ ASK DEVELOPER FIRST
NSOpenPanel, NSSavePanel, NSAlert, NSColor, etc.

// ✅ PREFER: SwiftUI equivalents
.fileImporter(isPresented: $showingImporter)
.alert("Title", isPresented: $showingAlert)
```

**Why**: Project mandates modern Swift/SwiftUI patterns, avoid legacy AppKit.

### 3. Manual Triggers for Filter State ⚠️

```swift
// ✅ CORRECT: Manual button trigger
Button("Filter Models") {
    Task { await filterModels() }
}

// ❌ WRONG: Automatic onChange
.onChange(of: selectedMakes) { _ in
    Task { await filterModels() }  // AttributeGraph CRASH!
}
```

**Why**: SwiftUI AttributeGraph crashes on automatic state updates during rendering.

### 4. Background Processing for Expensive Operations ⚠️

```swift
// ✅ CORRECT: Background task
Task.detached(priority: .background) {
    let result = await heavyComputation()
    await MainActor.run {
        self.data = result
    }
}

// ❌ WRONG: Blocks UI
let result = heavyComputation()  // 10+ seconds on main thread
self.data = result
```

**Why**: Any operation >100ms blocks UI, causes beachball cursor.

### 5. Cache Invalidation Pattern ⚠️

```swift
// ✅ CORRECT: Invalidate → Initialize
await filterCacheManager.invalidateCache()
await filterCacheManager.initializeCache()

// ❌ WRONG: Initialize without invalidate
await filterCacheManager.initializeCache()  // Stale data!
```

**Why**: Cache has guard preventing re-initialization without invalidation.

### 6. Enum Table Indexes ⚠️

```sql
-- ✅ CORRECT: Always index ID column
CREATE TABLE make_enum (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE
);
CREATE INDEX idx_make_enum_id ON make_enum(id);

-- ❌ WRONG: No index on ID
-- Results in 165s queries instead of <10s
```

**Why**: Oct 11, 2025 optimization: Adding indexes improved performance 16x.

### 7. Data-Type-Aware Operations ⚠️

```swift
// ✅ CORRECT: Pass dataType
await endBulkImport(dataType: .vehicle)
await refreshAllCaches(dataType: .vehicle)

// ❌ WRONG: Load all caches
await refreshAllCaches()  // Loads 10K+ vehicle items for license import!
```

**Why**: License imports hung 30+ seconds loading vehicle caches.

### 8. Use os.Logger in Production ⚠️

```swift
// ✅ CORRECT: Production code
AppLogger.database.info("Importing \(fileName, privacy: .public)")

// ❌ WRONG: Production code
print("Importing \(fileName)")

// ✅ EXCEPTION: CLI scripts in Scripts/ can use print()
```

**Why**: Console.app integration, performance, structured logging.

### 9. Thread-Safe Database Access ⚠️

```swift
// ✅ CORRECT: Pass path, open per-task
await withTaskGroup { group in
    for item in items {
        group.addTask {
            let db = try openDatabase(path: dbPath)  // Fresh connection
            return query(db, item)
        }
    }
}

// ❌ WRONG: Shared connection
let db = try openDatabase(path: dbPath)
await withTaskGroup { group in
    for item in items {
        group.addTask {
            return query(db, item)  // SEGFAULT!
        }
    }
}
```

**Why**: SQLite not thread-safe. Oct 5, 2025: Segfaults until pattern corrected.

### 10. Table-Specific ANALYZE ⚠️

```swift
// ✅ CORRECT: Specify table
sqlite3_exec(db, "ANALYZE vehicles")

// ❌ WRONG: Analyzes everything
sqlite3_exec(db, "ANALYZE")  // Minutes on 35GB+ database!
```

**Why**: Oct 15, 2025: License imports hung analyzing entire vehicle database.

---

## Essential Patterns

### Pattern: Enum Population During Import

```swift
// 1. Load existing enum values into cache
var makeCache: [String: Int] = [:]
loadEnumCache(table: "make_enum", keyColumn: "name", cache: &makeCache)

// 2. For each record, get or create ID
let makeId = getOrCreateEnumId(
    table: "make_enum",
    column: "name",
    value: record.make,
    cache: &makeCache
)

// 3. Write integer ID to main table
sqlite3_bind_int(stmt, index, Int32(makeId))
```

### Pattern: Background Task with UI Update

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var data: [Item] = []

    func loadData() {
        Task.detached(priority: .background) {
            let result = await self.performExpensiveQuery()

            await MainActor.run {
                self.data = result
            }
        }
    }
}
```

### Pattern: Foundation Models API

```swift
// Script setup
@MainActor
func main() async throws {
    // Create fresh session per task
    await withTaskGroup(of: Result.self) { group in
        for pair in pairs {
            group.addTask {
                let session = LanguageModelSession(instructions: "...")
                let response = try await session.respond(to: prompt)
                return parseResponse(response)
            }
        }
    }
}

// Entry point
try await main()

// ❌ NEVER use Task + RunLoop.main.run() - causes hangs!
```

### Pattern: Security-Scoped Resource Access

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

### Pattern: Data-Type-Aware Cache Refresh

```swift
// Import caller
await databaseManager.endBulkImport(dataType: .vehicle)

// DatabaseManager
func endBulkImport(dataType: DataEntityType = .vehicle) async {
    sqlite3_exec(db, "COMMIT")
    sqlite3_exec(db, "ANALYZE \(tableName)")  // Table-specific!
    await refreshAllCaches(dataType: dataType)
}

// FilterCacheManager
func initializeCache(for dataType: DataEntityType?) async {
    guard !isInitialized else { return }

    // Shared caches (always)
    try await loadYears()
    try await loadRegions()

    // Conditional caches
    if dataType == .vehicle || dataType == nil {
        try await loadMakes()  // 10K+ items
        try await loadModels()
    }

    if dataType == .license || dataType == nil {
        try await loadAgeGroups()  // 20 items
        try await loadGenders()
    }

    isInitialized = true
}
```

---

## Common Mistakes & Fixes

### Mistake: SwiftUI Computed Property Runs on Every Render

**Problem**: 100K+ item loops in computed properties cause beachballs.

**Fix**: Add fast-path checks at the top.

```swift
var statusCounts: (unassigned: Int, needsReview: Int, complete: Int) {
    // Fast path: if no mappings, skip expensive loop
    if viewModel.existingMappings.isEmpty {
        return (unassigned: totalPairs, needsReview: 0, complete: 0)
    }

    // Only compute when necessary
    for pair in viewModel.uncuratedPairs {
        // ... expensive work
    }
}
```

### Mistake: Missing Indexes on Enum Tables

**Problem**: 6-way JOINs take 165 seconds instead of <10 seconds.

**Fix**: Always add indexes on enum table ID columns.

```sql
CREATE INDEX idx_year_enum_id ON year_enum(id);
CREATE INDEX idx_make_enum_id ON make_enum(id);
CREATE INDEX idx_model_enum_id ON model_enum(id);
-- etc for all enum tables
```

### Mistake: Shared Database Connections in Concurrent Code

**Problem**: Segmentation faults in TaskGroup.

**Fix**: Pass database path (string), open fresh connection per task.

```swift
// Pass path, not connection
let dbPath = "~/path/to/database.sqlite"
await withTaskGroup { group in
    for item in items {
        group.addTask {
            let db = try DatabaseHelper(path: dbPath)  // Fresh!
            return process(db, item)
        }
    }
}
```

---

## Performance Targets

- **Filter dropdown population**: < 1 second
- **Chart query execution**: < 5 seconds (millions of records)
- **UI interactions**: < 100ms response time
- **Regularization UI load**: < 1 second
- **CSV import**: ~1000 records/second
- **License import**: < 10 seconds per file

---

## Key Architecture Decisions

### Database
- **Integer enumeration**: ALL categorical data (Sept 2024)
- **Canonical hierarchy cache**: 109x improvement (Oct 11, 2025)
- **Enum table indexes**: 16x improvement (Oct 11, 2025)

### Concurrency
- **Foundation Models pattern**: `@MainActor func main()` (Oct 4-5, 2025)
- **Thread-safe DB access**: Pass paths, not connections (Oct 5, 2025)
- **Background processing**: Task.detached for >100ms ops (Oct 11, 2025)

### UI
- **Manual hierarchical filtering**: Avoid AttributeGraph crashes (Oct 14, 2025)
- **Analytics/Filters separation**: Two-section filter panel (Oct 13, 2025)
- **Normalize to First Year**: Global toggle for all metrics (Oct 14, 2025)

### Import
- **Delegation pattern**: CSVImporter → DatabaseManager (Oct 15, 2025)
- **Data-type-aware caches**: Prevent cross-contamination (Oct 15, 2025)
- **Table-specific ANALYZE**: Avoid analyzing entire DB (Oct 15, 2025)

### Logging
- **os.Logger migration**: All production code (Oct 10, 2025)
- **Exception**: CLI scripts can use print()

---

## When in Doubt

1. **Check ARCHITECTURAL_GUIDE.md** for detailed explanations
2. **Review recent Notes/** for session context
3. **Ask the human developer** before using NS-prefixed APIs
4. **Prefer background tasks** for anything that might take >100ms
5. **Always invalidate caches** before rebuilding
6. **Pass dataType** through import/cache chains
7. **Use integer foreign keys**, never string queries on categorical data

---

## Quick Command Reference

```bash
# Database inspection
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT COUNT(*) FROM vehicles;"

# Check enum table has indexes
sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%enum_id';"

# Console.app filtering
# subsystem:com.endoquant.SAAQAnalyzer category:performance
# subsystem:com.endoquant.SAAQAnalyzer level:error

# Compile Swift scripts
swiftc Script.swift -o Script -O

# Build project
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer build
```

---

**Last Updated**: October 21, 2025
**For Full Details**: See [ARCHITECTURAL_GUIDE.md](ARCHITECTURAL_GUIDE.md)
