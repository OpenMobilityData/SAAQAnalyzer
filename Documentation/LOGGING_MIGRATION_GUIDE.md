# Logging Migration Guide

## Overview
This document outlines the migration from ad-hoc `print()` statements to structured logging using Apple's `os.Logger` framework (macOS best practices).

## Benefits of os.Logger

1. **Console.app Integration**: Logs appear properly categorized in Console.app
2. **Performance**: os.Logger is highly optimized, with minimal overhead
3. **Filtering**: Can filter by subsystem and category
4. **Log Levels**: Automatic filtering based on debug/release builds
5. **Privacy**: Explicit privacy controls for sensitive data
6. **Structured**: Searchable and analyzable in unified logging system

## Log Levels

| Level | Usage | Example |
|-------|-------|---------|
| `.debug` | Detailed debugging (filtered in release) | Internal state changes, verbose loop iterations |
| `.info` | General informational messages | Successful operations, configuration changes |
| `.notice` | Important events (default visibility) | Import started, user actions, milestones |
| `.error` | Recoverable errors | Failed operations that are handled |
| `.fault` | Critical failures | Unrecoverable errors, data corruption |

## Logger Categories

```swift
AppLogger.database     // Database operations
AppLogger.dataImport   // CSV import operations
AppLogger.query        // Query execution and optimization
AppLogger.cache        // Filter cache operations
AppLogger.regularization  // Regularization system
AppLogger.ui           // UI events
AppLogger.performance  // Performance benchmarks
AppLogger.geographic   // Geographic data operations
```

## Migration Patterns

### Pattern 1: Simple Informational Message

**Before:**
```swift
print("✅ Database opened successfully")
```

**After:**
```swift
AppLogger.database.info("Database opened successfully")
```

### Pattern 2: Warning/Notice

**Before:**
```swift
print("⚠️ Year \(year) already exists. Replacing existing data...")
```

**After:**
```swift
AppLogger.dataImport.notice("Year \(year) already exists - replacing existing data")
```

### Pattern 3: Error Message

**Before:**
```swift
print("❌ Error importing batch: \(error)")
```

**After:**
```swift
AppLogger.dataImport.error("Error importing batch: \(error.localizedDescription)")
```

### Pattern 4: Performance/Benchmarking (KEEP THESE!)

**Before:**
```swift
print("🎉 Import completed successfully!")
print("📊 Performance Summary:")
print("   • CSV Parsing: \(String(format: "%.1f", parseTime))s")
print("   • Database Import: \(String(format: "%.1f", importTime))s")
print("   • Total Time: \(String(format: "%.1f", totalTime))s")
print("   • Records/second: \(String(format: "%.0f", recordsPerSecond))")
```

**After (using structured performance logging):**
```swift
let performance = AppLogger.ImportPerformance(
    totalRecords: totalRecords,
    parseTime: parseTime,
    importTime: importTime,
    totalTime: totalTime
)
performance.log(logger: AppLogger.performance, fileName: fileName, year: year)
```

### Pattern 5: Debug/Development Messages (REMOVE or convert to .debug)

**Before:**
```swift
print("Debug: Sample data (first 10 groups):")
print("  Year: \(year), Class: \(clas), Region: \(region)")
```

**After (only in DEBUG builds):**
```swift
#if DEBUG
AppLogger.database.debug("Sample data: year=\(year), class=\(clas), region=\(region)")
#endif
```

### Pattern 6: Progress Messages

**Before:**
```swift
print("   • Chunk \(completedChunks)/\(totalChunks) completed (\(progressPercent)%)")
```

**After:**
```swift
AppLogger.dataImport.debug("Parsing progress: chunk \(completedChunks)/\(totalChunks) (\(progressPercent)%)")
```

### Pattern 7: Query Performance

**Before:**
```swift
print("⚡️ Query completed in \(String(format: "%.3f", executionTime))s")
```

**After (using helper):**
```swift
AppLogger.logQueryPerformance(
    queryType: "Series",
    duration: executionTime,
    dataPoints: dataPoints,
    indexUsed: indexName
)
```

## Privacy Annotations

Use `.public` for non-sensitive data:
```swift
AppLogger.dataImport.info("Importing file: \(fileName, privacy: .public)")
```

Use `.private` (default) for sensitive data:
```swift
AppLogger.database.info("User selected filters: \(filterConfig)")  // private by default
```

## What to Keep vs Remove

### KEEP (Essential Production Logging)

✅ **Performance benchmarks** - Critical for comparing different machines
- Import timing (parse time, import time, total time, records/sec)
- Query execution time
- Database optimization timing

✅ **Important state changes**
- Import started/completed
- Database opened/closed
- Year data replaced
- Configuration changes

✅ **Errors and warnings**
- Import failures
- Database errors
- Invalid data

### REMOVE or Convert to .debug

❌ **Verbose debugging**
- "Debug: Sample data..."
- Step-by-step execution traces
- Detailed execution plans (unless using EXPLAIN QUERY PLAN)

❌ **Emoji-heavy informal messages**
- "🚀 Starting import..."  → "Starting import..."
- "🎉 Import completed!" → "Import completed successfully"

❌ **Redundant progress messages**
- Already shown in UI progress indicators
- Keep only high-level milestones

## Console.app Usage

### Filtering Logs

1. Open Console.app
2. Select your Mac in sidebar
3. Search/Filter options:
   - **Subsystem**: `com.yourcompany.SAAQAnalyzer` (or your bundle ID)
   - **Category**: `import`, `database`, `query`, `performance`, etc.
   - **Message**: Search specific keywords

### Example Filters

**View all import operations:**
```
subsystem:com.yourcompany.SAAQAnalyzer category:import
```

**View only performance metrics:**
```
subsystem:com.yourcompany.SAAQAnalyzer category:performance
```

**View errors across all categories:**
```
subsystem:com.yourcompany.SAAQAnalyzer level:error OR level:fault
```

## Performance Impact

os.Logger is **highly optimized**:
- Negligible overhead in release builds
- Debug messages automatically excluded from release
- Asynchronous logging (non-blocking)
- Efficient string interpolation (evaluated only if logged)

## Migration Checklist

### Phase 1: Core Data Layer (Priority: High)
- [x] Create AppLogger.swift utility
- [ ] CSVImporter.swift
- [ ] DatabaseManager.swift
- [ ] RegularizationManager.swift
- [ ] FilterCacheManager.swift
- [ ] CategoricalEnumManager.swift
- [ ] OptimizedQueryManager.swift

### Phase 2: UI Layer (Priority: Medium)
- [ ] SAAQAnalyzerApp.swift
- [ ] FilterPanel.swift
- [ ] ChartView.swift
- [ ] RegularizationView.swift
- [ ] DataInspector.swift

### Phase 3: Supporting Files (Priority: Low)
- [ ] GeographicDataImporter.swift
- [ ] DataPackageManager.swift
- [ ] FilterConfigurationAdapter.swift
- [ ] SchemaManager.swift
- [ ] FilterCache.swift
- [ ] DataModels.swift
- [ ] ImportProgressManager.swift

### Phase 4: Testing & Verification
- [ ] Build with zero warnings
- [ ] Test import operations
- [ ] Verify Console.app output
- [ ] Check performance (should be same or better)
- [ ] Document new logging patterns in CLAUDE.md

## Best Practices

1. **Choose the right level**:
   - User actions → `.notice`
   - Successful operations → `.info`
   - Errors → `.error`
   - Critical failures → `.fault`
   - Debugging → `.debug`

2. **Be concise**:
   - Remove emoji decorations
   - Clear, professional language
   - Include relevant context (file name, year, count)

3. **Use structured logging**:
   - Consistent format across similar operations
   - Include quantitative data (timing, counts, percentages)
   - Use helper functions for common patterns

4. **Performance benchmarks**:
   - Always log with `.notice` or higher
   - Include all relevant metrics (time, throughput, success rate)
   - Use structured format for easy parsing

5. **Privacy-aware**:
   - Mark file names as `.public` (not sensitive)
   - Keep user data `.private` by default
   - Never log authentication tokens or credentials

## Example: Complete File Migration

See `CSVImporter.swift` for a complete example of migrated logging.

## Questions?

For questions about logging strategy or migration approach, consult:
- Apple's Unified Logging documentation
- WWDC sessions on os.Logger
- This guide's migration patterns

---

**Last Updated**: October 10, 2025
**Status**: In Progress
**Next Review**: After Phase 1 completion
