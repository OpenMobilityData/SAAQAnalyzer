# Regularization UI Blocking Refactor - Session Handoff

**Date**: October 20, 2025
**Status**: In Progress - Critical Performance Issue
**Session Duration**: Extended debugging and refactoring session

---

## 1. Current Task & Objective

### Primary Goal
Fix synchronous blocking (beachball cursor) when opening:
1. Settings → Regularization pane
2. Regularization Manager window

### The Problem
Despite launching database queries in background threads with `Task.detached`, the UI freezes for 29-30 seconds with a beachball cursor. The application becomes completely unresponsive during:
- Loading regularization statistics (78,512 mappings)
- Loading uncurated Make/Model pairs (102,372 pairs)
- Computing regularization status for pairs

### Root Cause Discovery
The blocking was caused by **computed properties being evaluated repeatedly during SwiftUI view rendering**, not just by the database queries themselves. Specifically:
- `getRegularizationStatus(for:)` was called 300,000+ times (102k pairs × 3 different view properties)
- Each call performed dictionary lookups on 78k mappings
- This happened synchronously on the main thread during every body evaluation

---

## 2. Progress Completed

### A. Initial Threading Fixes (Attempted)
1. ✅ Removed `@MainActor` from `RegularizationViewModel` class
2. ✅ Created `nonisolated` async methods: `loadVehicleTypesAsync()`, `loadExistingMappingsAsync()`, `loadUncuratedPairsAsync()`, etc.
3. ✅ Changed `.task` modifier to `.onAppear` with `DispatchQueue.main.async` deferral
4. ✅ Fixed nested `Task.detached` patterns to avoid MainActor inheritance
5. ✅ Fixed `loadStatistics()` to avoid jumping back to MainActor mid-query

### B. Major Architectural Refactoring (Status Caching)
**Problem Identified**: Status was being computed on every view render, not cached.

**Solution Implemented**: Embed status directly in the data model
1. ✅ Created `RegularizationStatus` enum in `DataModels.swift`
   - Cases: `.unassigned`, `.partial`, `.complete`
   - Made `Sendable` and `Hashable` for Swift 6 concurrency
2. ✅ Added `regularizationStatus` property to `UnverifiedMakeModelPair` struct
3. ✅ Modified `RegularizationManager.findUncuratedPairs()` to compute status at creation time
4. ✅ Added `computeRegularizationStatus()` helper method
5. ✅ Removed obsolete cache layer (`pairStatusCache`, `rebuildStatusCacheAsync()`, `computeStatus()`)
6. ✅ Updated all UI code to use `pair.regularizationStatus` instead of calling methods

### C. Terminology Updates
Changed from "Needs Review" to "Partial" throughout:
- ❌ `.none` / `.needsReview` / `.fullyRegularized` (old)
- ✅ `.unassigned` / `.partial` / `.complete` (new)

Updated in:
- Enum cases
- UI labels, filter buttons, badges
- Comments and documentation
- Status computation logic

### D. Status Computation Logic Refinement
Made status requirements more strict:
- **Complete**: VehicleType assigned AND at least some triplets exist AND ALL triplets have fuel types
- **Partial**: Some assignments exist but not comprehensive
- **Unassigned**: No mappings exist

### E. UI Loading State Improvements
Changed List rendering to show immediately with loading indicator instead of conditional rendering that blocks appearance.

---

## 3. Key Decisions & Patterns

### Architectural Decisions

1. **Status as Data, Not Computation**
   - Status is now a **property** of `UnverifiedMakeModelPair`, not a method call
   - Computed once during database load, stored with the data
   - This is the correct pattern - view should read data, not compute it

2. **Wildcard vs Triplet Mappings**
   - Wildcard mapping: `modelYearId == nil` → VehicleType assignment applies to all years
   - Triplet mapping: `modelYearId != nil` → FuelType assignment for specific year
   - Complete status requires BOTH wildcard and triplets

3. **Threading Pattern**
   ```swift
   // CORRECT: For @MainActor methods launching background work
   @MainActor
   func loadInitialData() {  // Synchronous, returns immediately
       DispatchQueue.main.async {  // Defer to next run loop
           // Launch detached tasks
           Task.detached { ... }
       }
   }
   ```

4. **Status Computation Location**
   - Happens in `RegularizationManager.findUncuratedPairs()` during pair creation
   - Loads mappings BEFORE the continuation (since it's async)
   - Computes status for each pair as it's created from the query

### Coding Patterns Established

```swift
// Status is embedded in the struct
struct UnverifiedMakeModelPair {
    let makeId: Int
    let modelId: Int
    // ... other properties
    var regularizationStatus: RegularizationStatus  // ← Computed at creation
}

// View code just reads it
ForEach(filteredAndSortedPairs) { pair in
    UncuratedPairRow(
        pair: pair,
        regularizationStatus: pair.regularizationStatus  // ← Simple property access
    )
}
```

---

## 4. Active Files & Locations

### Modified Files

1. **SAAQAnalyzer/Models/DataModels.swift** (lines 1840-1864)
   - Added `RegularizationStatus` enum (3 cases)
   - Added `regularizationStatus` property to `UnverifiedMakeModelPair`

2. **SAAQAnalyzer/DataLayer/RegularizationManager.swift**
   - Lines 357-366: Load mappings before continuation
   - Lines 405-420: Compute status when creating pairs
   - Lines 447-481: `computeRegularizationStatus()` helper method
   - Status computation logic uses `vehicleType` and `fuelType` properties (String?)

3. **SAAQAnalyzer/UI/RegularizationView.swift**
   - Removed `@MainActor` from class declaration (line 926)
   - Removed `pairStatusCache` property
   - Removed `rebuildStatusCacheAsync()` method
   - Removed `computeStatus()` method
   - Removed `getRegularizationStatus()` method
   - Updated `statusCounts` computed property (lines 96-113)
   - Updated `filteredAndSortedPairs` filter logic (lines 127-136)
   - Updated List ForEach (lines 432-447)
   - Updated `loadInitialData()` to use `Task.detached` (lines 1001-1041)
   - Changed status filter state variable: `showPartial` instead of `showNeedsReview`
   - Updated status badges and indicators (lines 489-531)

4. **SAAQAnalyzer/SAAQAnalyzerApp.swift** (lines 2227-2298)
   - Changed `.task` to `.onAppear` with `DispatchQueue.main.async`
   - Fixed `loadInitialData()` to be synchronous
   - Fixed nested `Task.detached` for statistics loading

### Key Data Structures

```swift
// RegularizationMapping (existing)
struct RegularizationMapping {
    let uncuratedMakeId: Int
    let uncuratedModelId: Int
    let modelYearId: Int?        // nil = wildcard (VehicleType)
    let fuelType: String?        // nil = "Not Assigned"
    let vehicleType: String?     // nil = "Not Assigned"
    // ... other fields
}

// RegularizationStatus (new)
enum RegularizationStatus: Sendable, Hashable {
    case unassigned
    case partial
    case complete
}
```

---

## 5. Current State

### What Works
- ✅ Code compiles successfully
- ✅ Status badges display (though may need refinement)
- ✅ Terminology updated to "Unassigned/Partial/Complete"
- ✅ Status embedded in data model correctly
- ✅ Status computed at load time, not render time

### What Doesn't Work
- ❌ **UI still blocks with beachball for ~30 seconds**
- ❌ Settings → Regularization pane shows beachball before appearing
- ❌ Regularization Manager shows beachball during "Loading uncurated pairs" phase
- ❌ Despite all threading fixes, the UI freezes completely

### Console Output Pattern
```
Updated regularization year configuration: Curated=2011–2022 (12 years), Uncurated=2023–2024 (2 years)
Loaded 13 vehicle types from schema
Loaded 10 vehicle types from regularization mappings
Generating canonical hierarchy from 12 curated years: [...]
Finding uncurated Make/Model pairs in 2 uncurated years: [2023, 2024], includeExactMatches=true
🐌 Find Uncurated Pairs query: 29.450s, 102372 points, Very Slow
Found 102372 uncurated Make/Model pairs in 29.450s
Loaded 78512 mappings (10844 pairs, 67668 triplets)
Loaded 102372 uncurated pairs in 29.727s
```

The query completes, but the UI is frozen the entire time despite:
- `Task.detached` usage
- `nonisolated` methods
- `DispatchQueue.main.async` deferral
- Status pre-computation

### Mystery: Why Still Blocking?

Even though:
1. Database queries run on background threads
2. Status is pre-computed (not computed during render)
3. UI should appear immediately with loading indicator

The UI still blocks. Possible causes:
- **Memory pressure** from loading 102k+ objects at once
- **SwiftUI publishing** when updating `@Published var uncuratedPairs` with 102k items
- **Database lock contention** blocking main thread indirectly
- **SQLite WAL checkpoint** blocking on main thread
- **`filteredAndSortedPairs` computed property** still expensive (filters/sorts 102k items)

---

## 6. Next Steps (Priority Order)

### Immediate Investigation Needed

1. **Profile Where Blocking Actually Occurs**
   - Use Instruments Time Profiler
   - Check if blocking happens during:
     - Database query execution
     - Result set processing
     - SwiftUI update when `uncuratedPairs` is set
     - `filteredAndSortedPairs` evaluation

2. **Test Hypothesis: Publishing Large Arrays**
   ```swift
   // Try setting isLoading = false BEFORE setting uncuratedPairs
   await MainActor.run {
       self.isLoading = false  // UI shows loading state ends
   }
   // Delay before publishing data
   try? await Task.sleep(nanoseconds: 500_000_000)
   await MainActor.run {
       self.uncuratedPairs = pairs  // Does THIS block?
   }
   ```

3. **Cache `filteredAndSortedPairs` Results**
   - Change from computed property to `@State` variable
   - Update in background when filters change
   - This prevents 102k filter/sort operations on every body evaluation

### Short-Term Solutions

4. **Implement Pagination**
   - Load first 1000 pairs immediately
   - Load remaining 101k pairs lazily
   - Or use virtual scrolling

5. **Lazy Status Computation** (Alternative Approach)
   - Return pairs with `.unassigned` immediately
   - Compute actual status asynchronously
   - Update pairs incrementally in batches

6. **Cache Query Results to Disk**
   - Serialize uncurated pairs to JSON/binary
   - Load cached results instantly on subsequent launches
   - Invalidate cache when mappings change

### Long-Term Solutions

7. **Database Schema Optimization**
   - Pre-compute status in a materialized view
   - Add `regularization_status` column to database
   - Update via triggers when mappings change

8. **Incremental Loading Architecture**
   - Load metadata first (count, stats)
   - Load pairs in chunks as user scrolls
   - Use `LIMIT/OFFSET` or cursor-based pagination

---

## 7. Important Context

### Database Details
- **Total uncurated pairs**: 102,372
- **Total regularization mappings**: 78,512
  - Unique pairs: 10,844
  - Triplet mappings: 67,668
- **Query performance**: 29-30 seconds (consistently)
- **Database size**: Large (14M+ records in uncurated years)

### SQLite Configuration
- WAL mode enabled
- 64MB cache size
- Indexes exist on relevant columns
- Query uses joins and CTEs (Common Table Expressions)

### Regularization Mapping Structure
```
make_model_regularization table:
- id (primary key)
- uncurated_make_id (int, indexed)
- uncurated_model_id (int, indexed)
- model_year_id (int, nullable) ← NULL = wildcard
- canonical_make_id (int)
- canonical_model_id (int)
- fuel_type_id (int, nullable) ← -1 = "Unknown", NULL = "Not Assigned"
- vehicle_type_id (int, nullable)
```

### Status Computation Rules
```swift
// Complete: VehicleType + all triplets have fuel types
if hasVehicleType && !triplets.isEmpty {
    let allTripletsHaveFuelType = triplets.allSatisfy { $0.fuelType != nil }
    return allTripletsHaveFuelType ? .complete : .partial
}

// Partial: Some work done
else if wildcardMapping != nil || !triplets.isEmpty {
    return .partial
}

// Unassigned: No mappings
else {
    return .unassigned
}
```

### Swift Concurrency Gotchas Discovered

1. **`Task { }` inherits actor context**
   ```swift
   @MainActor func foo() {
       Task { await bar() }  // ← Still runs on MainActor!
   }
   ```
   Must use `Task.detached` to break free.

2. **`.task` modifier blocks view appearance**
   ```swift
   .task { await loadData() }  // ← View doesn't appear until done!
   ```
   Must use `.onAppear` instead.

3. **Nested `await MainActor.run` is dangerous**
   ```swift
   Task.detached {
       await MainActor.run {
           someMethod()  // ← If this is @MainActor, we're stuck!
       }
   }
   ```

4. **`withCheckedThrowingContinuation` can't contain `await`**
   Must load async data BEFORE entering the continuation.

### Errors Resolved

1. **"Cannot pass function of type '(CheckedContinuation) async -> Void'"**
   - Fixed by moving `getAllMappings()` call outside continuation

2. **"Value of type 'RegularizationMapping' has no member 'vehicleTypeId'"**
   - Fixed by using `vehicleType` (String?) instead of `vehicleTypeId`

3. **"Cannot infer type of closure parameter '$0'"**
   - Fixed by adding explicit closure parameter: `{ mapping in }`

### Testing Observations

User reported:
- First launch: Beachball on Settings pane open, beachball on Regularization Manager open
- Second launch: Same behavior (no improvement from caching)
- Pairs display correctly after load completes
- Status badges were showing many "Complete" incorrectly (now fixed with stricter logic)
- Progress indicator shows "No uncurated pairs found" briefly, then "Loading uncurated pairs" with beachball

### Critical Logs to Monitor

```bash
# Watch for these patterns:
grep "Finding uncurated Make/Model pairs" console.log
grep "🐌 Find Uncurated Pairs query" console.log
grep "Loaded.*uncurated pairs" console.log
grep "Detailed regularization statistics" console.log
```

---

## Next Session Checklist

1. [ ] Review this entire document
2. [ ] Run Instruments Time Profiler during Regularization Manager open
3. [ ] Identify exact function where 29s is spent
4. [ ] Test hypothesis: Does `uncuratedPairs = pairs` block main thread?
5. [ ] Implement caching for `filteredAndSortedPairs`
6. [ ] Consider pagination or lazy loading approach
7. [ ] If all else fails, consider background-only updates with "Refresh" button

---

## Files Reference

**Quick Open Locations**:
```
/SAAQAnalyzer/Models/DataModels.swift:1840  # RegularizationStatus enum
/SAAQAnalyzer/DataLayer/RegularizationManager.swift:286  # findUncuratedPairs()
/SAAQAnalyzer/DataLayer/RegularizationManager.swift:447  # computeRegularizationStatus()
/SAAQAnalyzer/UI/RegularizationView.swift:926  # RegularizationViewModel class
/SAAQAnalyzer/UI/RegularizationView.swift:75  # UncuratedPairsListView
/SAAQAnalyzer/UI/RegularizationView.swift:417  # List rendering (loading state)
/SAAQAnalyzer/SAAQAnalyzerApp.swift:1912  # RegularizationSettingsView
/SAAQAnalyzer/SAAQAnalyzerApp.swift:2244  # loadInitialData()
```

**Build Command**:
```bash
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -configuration Debug build
```

**Test Procedure**:
1. Clean build
2. Launch app
3. Open Settings (Cmd+,)
4. Click Regularization tab → **Should show beachball here** ❌
5. Click "Open Regularization Manager" → **Should show beachball here** ❌

---

## Additional Notes

- User is experienced and expects production-quality performance
- This is a critical UX issue blocking regular use of the regularization feature
- The 29-second query itself may be unavoidable, but the UI freeze is unacceptable
- Need to show progress and keep UI responsive during long operations
- Consider adding "This database query takes ~30 seconds" warning in UI
- May need to re-architect if simple fixes don't work

**End of Handoff Document**
