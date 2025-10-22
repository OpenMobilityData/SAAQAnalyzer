# Performance Profiling Guide

## Overview

This guide walks through using Apple's Instruments to profile two specific performance bottlenecks in SAAQAnalyzer:

1. **Filter Cache Loading** - "Loading filter data..." on app launch
2. **Uncurated Pairs Loading** - "Loading uncurated pairs..." in Regularization Manager

## Instrumentation Added

The following os_signpost instrumentation has been added to make these operations visible in Instruments:

### Filter Cache Manager (FilterCacheManager.swift)

- **Top-level interval**: `"Load Filter Cache"` - Entire cache initialization
- **Nested intervals**:
  - `"Load Regularization Info"` - Loading regularization display info
  - `"Load Uncurated Pairs"` - Finding Make/Model pairs only in uncurated years
  - `"Load Makes"` - Loading Make enumeration with badges
  - `"Load Models"` - Loading Model enumeration with badges

### Regularization Manager (RegularizationManager.swift)

- **Top-level interval**: `"Find Uncurated Pairs"` - Complete pair discovery
- **Nested intervals**:
  - `"Load From Cache"` - Fast path when cache is valid
  - `"Query Uncurated Pairs"` - Slow path when recomputing

## Step-by-Step Profiling Workflow

### 1. Build for Profiling

```bash
# In Xcode: Product → Profile (⌘I)
# Or use command line:
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -configuration Release clean build
```

**Important**: Always profile Release builds, not Debug builds. Debug builds include extra overhead that skews results.

### 2. Launch Instruments

When you press ⌘I in Xcode, Instruments will open with a template chooser.

**Recommended templates**:
- **Time Profiler** - Shows where CPU time is spent
- **System Trace** - Shows scheduling, I/O, and system calls
- **os_signpost** (via Blank template + Instruments) - Custom intervals

For this analysis, start with **Time Profiler** and **os_signpost**.

### 3. Configure Time Profiler

1. Select "Time Profiler" template
2. Click the red record button (or press ⌘R)
3. The app will launch
4. Perform the operations you want to profile:
   - **Test 1**: Launch app (triggers filter cache loading)
   - **Test 2**: Open Settings → Regularization Manager (triggers uncurated pairs loading)

5. Stop recording (press ⌘R again or click stop button)

### 4. Analyze Time Profiler Results

#### View Call Tree

1. In the bottom pane, select the "Call Tree" view
2. Click the "Call Tree" button in bottom toolbar, then check:
   - ✅ **Separate by Thread** - See which threads are busy
   - ✅ **Invert Call Tree** - Start from leaves (where time is spent)
   - ✅ **Hide System Libraries** - Focus on your code
   - ✅ **Flatten Recursion** - Simplify recursive calls

3. Look for functions consuming the most time:
   - `FilterCacheManager.initializeCache()`
   - `FilterCacheManager.loadMakes()`
   - `FilterCacheManager.loadModels()`
   - `RegularizationManager.findUncuratedPairs()`

#### Identify Bottlenecks

Look for:
- **High self time** - Time spent in function itself (not callees)
- **High total time** - Time including all called functions
- **Blocking operations** - Database queries, I/O, synchronous waits

### 5. Use os_signpost for Interval Analysis

1. Create a new trace: File → New Trace
2. Choose **Blank** template
3. Click the **+** button in the top-right corner
4. Add these instruments:
   - **os_signpost** (from Instruments Library)
   - **Points of Interest** (automatically shows signpost intervals)

5. Configure os_signpost instrument:
   - Click the gear icon on the instrument
   - Filter by subsystem: `com.saaq.SAAQAnalyzer`
   - Filter by categories: `Cache`, `Regularization`

6. Record a new trace (⌘R)

7. Analyze intervals:
   - In the timeline, you'll see visual bars for each signpost interval
   - Click on a bar to see duration and metadata
   - Compare nested intervals to see which sub-operations are slowest

**Expected signpost names**:
- `Load Filter Cache` (parent)
  - `Load Regularization Info` (child)
  - `Load Uncurated Pairs` (child)
  - `Load Makes` (child)
  - `Load Models` (child)
- `Find Uncurated Pairs` (parent)
  - `Load From Cache` OR `Query Uncurated Pairs` (child)

### 6. Interpret Results

#### Filter Cache Loading

Expected slow operations:
- **loadMakes()** - Iterates through all Makes, checks regularization status
- **loadModels()** - Iterates through all Models, joins with Make table, checks badges
- **loadUncuratedPairs()** - Complex SQL with NOT EXISTS subquery

**Questions to answer**:
1. Which loader takes the most time?
2. Is the time spent in SQL execution or Swift processing?
3. Are there N+1 query patterns (multiple queries in a loop)?

#### Uncurated Pairs Loading

Expected paths:
- **Fast path (< 1s)**: Cache valid, loads from `uncurated_pairs_cache` table
- **Slow path (10-30s)**: Cache invalid, runs complex CTE query with JOINs

**Questions to answer**:
1. Is the cache being used? (Check for "Load From Cache" signpost)
2. If recomputing, which part of the query is slow?
   - SQL execution time (in database)
   - Status computation loop (in Swift)
3. Is the status computation loop parallelizable?

### 7. Database Query Analysis

For SQL-heavy operations, use **System Trace** template:

1. Profile → System Trace
2. Record the operation
3. In the timeline, filter by "File Activity" or "Virtual Memory"
4. Look for:
   - **File reads** - SQLite reading database pages
   - **Page faults** - Database not fitting in memory
   - **Thread blocking** - Waiting for I/O

### 8. Optimization Strategies

Based on profiling results, consider:

#### For Filter Cache Loading

**Problem**: Sequential loading blocks UI thread
**Solution**: Parallelize independent loaders using TaskGroup

```swift
await withTaskGroup(of: Void.self) { group in
    group.addTask { try? await loadYears() }
    group.addTask { try? await loadRegions() }
    group.addTask { try? await loadMRCs() }
    // ... etc
}
```

**Problem**: Make/Model loaders iterate dictionaries in-memory
**Solution**: Move badge computation to SQL query

**Problem**: Uncurated pairs query is slow
**Solution**: Already cached - verify cache is being used

#### For Uncurated Pairs Loading

**Problem**: Cache not being used
**Solution**: Fix cache validation logic or pre-populate on import

**Problem**: Status computation loop is slow
**Solution**: Batch status computation or use database query

**Problem**: Database query is inherently slow
**Solution**: Add covering indexes or denormalize data

## Console.app Logging

To view structured logs alongside profiling:

1. Open **Console.app** (Applications → Utilities → Console)
2. Select your device (macOS)
3. Click "Start streaming"
4. Filter by:
   - **Subsystem**: `com.saaq.SAAQAnalyzer`
   - **Category**: `performance`, `cache`, `regularization`

5. Run the app and watch logs appear in real-time

**Example queries**:
```
subsystem:com.saaq.SAAQAnalyzer category:performance
subsystem:com.saaq.SAAQAnalyzer category:cache
subsystem:com.saaq.SAAQAnalyzer level:error
```

## Key Performance Metrics

Track these metrics before and after optimizations:

| Operation | Current (estimated) | Target | Metric |
|-----------|---------------------|--------|--------|
| Filter Cache Load | 5-10s | < 2s | Time to first UI update |
| Uncurated Pairs (cache) | 0.5s | < 0.5s | Acceptable (fast path) |
| Uncurated Pairs (query) | 20-30s | < 5s | Needs optimization |

## Next Steps

1. **Profile current performance** - Get baseline measurements
2. **Identify top 3 slowest operations** - Focus on biggest wins
3. **Implement optimizations** - One at a time, measure each
4. **Re-profile** - Verify improvements, watch for regressions
5. **Iterate** - Continue until targets met

## Common Pitfalls

- ❌ **Profiling Debug builds** - Results will be misleading
- ❌ **Not using signposts** - Hard to correlate time to specific operations
- ❌ **Optimizing without measuring** - Don't guess, measure first
- ❌ **Premature optimization** - Profile to find real bottlenecks
- ❌ **Ignoring background threads** - Check all threads, not just main

## References

- [Instruments Help](https://help.apple.com/instruments/)
- [Using Time Profiler](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance)
- [os_signpost Documentation](https://developer.apple.com/documentation/os/logging/recording_performance_data)
- [WWDC Videos on Performance](https://developer.apple.com/videos/performance)

---

**Last Updated**: October 2025
**Instrumentation Version**: 1.0 (os_signpost support)
