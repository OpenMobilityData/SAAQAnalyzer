# Curated Years Filter and Model Lookup Bug Fixes

**Date**: October 20, 2025
**Session Status**: ✅ COMPLETE - Critical bugs fixed
**Token Usage**: 118k/200k (59%)
**Commits**: Pending
**Branch**: `rhoge-dev`

---

## Executive Summary

Fixed three critical bugs that caused the "Limit to Curated Years" filter to malfunction and queries to return zero results. The session revealed a cycle where fixes from October 18, 2025 had over-corrected one issue while introducing another, and uncovered a fundamental model ID lookup bug that prevented Make+Model filters from working correctly.

**Impact**:
- Uncurated Makes (NOVAB, NOVABUS) were appearing when they should be hidden
- Uncurated Models were appearing during hierarchical filtering
- Queries for specific Make+Model combinations returned zero records despite data existing

**Root Causes**:
1. SQL `NOT IN` with NULL values (classic SQL gotcha - 240K NULL make_ids)
2. October 18 design decision to bypass curated years filter during hierarchical filtering (reversed)
3. Model name lookups returning wrong IDs (DODGE+ART instead of NOVA+ART)

---

## Problem Discovery

### Initial Report

User reported that when "Limit to Curated Years" toggle was ON:

1. **Make Search Issue**: Typing "nova" showed NOVA, NOVAB, and NOVABUS
   - Expected: Only NOVA (NOVAB/NOVABUS are uncurated-only)
   - Actual: All three appeared

2. **Model Filtering Issue**: After clicking "Filter by Selected Makes" for NOVA
   - Expected: Only curated models without badges
   - Actual: Models showed `[uncurated:]` badges

3. **Query Results Issue**: Selecting Make=NOVA + Model=ART (NOVA)
   - Expected: 45 records across 2017-2019
   - Actual: Zero records returned

---

## Diagnostic Process

### Phase 1: Verify Data Existence

**Query 1**: Check NOVAB/NOVABUS year distribution
```sql
SELECT y.year, COUNT(*) as record_count
FROM vehicles v
JOIN make_enum m ON v.make_id = m.id
JOIN year_enum y ON v.year_id = y.id
WHERE m.name IN ('NOVAB', 'NOVABUS')
GROUP BY m.name, y.year
ORDER BY m.name, y.year;
```

**Results**:
- NOVAB: 1,929 records in 2023, 1,756 in 2024 (uncurated years only) ✓
- NOVABUS: 13 records in 2023, 155 in 2024 (uncurated years only) ✓

**Conclusion**: Data is correct - these Makes exist ONLY in uncurated years and should be hidden.

### Phase 2: Check Console Output

Console showed:
```
✅ Loaded 92560 uncurated Make/Model pairs (only in uncurated years)
```

But **NO line** showing:
```
✅ Loaded X uncurated Makes (only in uncurated years)
```

**Conclusion**: `loadUncuratedMakes()` was returning zero results.

### Phase 3: Test SQL Query

**Test Query**:
```sql
SELECT v.make_id, COUNT(*) as record_count
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
WHERE y.year IN (2023, 2024)
AND v.make_id NOT IN (
    SELECT DISTINCT v2.make_id
    FROM vehicles v2
    JOIN year_enum y2 ON v2.year_id = y2.id
    WHERE y2.year IN (2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022)
)
GROUP BY v.make_id;
```

**Result**: **Zero rows returned** (should return thousands of uncurated Makes)

### Phase 4: Identify NULL Issue

**Discovery Query**:
```sql
SELECT COUNT(*) as null_count
FROM vehicles v2
JOIN year_enum y2 ON v2.year_id = y2.id
WHERE y2.year IN (2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022)
AND v2.make_id IS NULL;
```

**Result**: **240,616 records with NULL make_id**

**Root Cause Identified**: SQL `NOT IN` with NULL values returns empty result set (classic SQL gotcha).

### Phase 5: Review October 18 Changes

Reviewed `Notes/2025-10-18-Uncurated-Badge-and-Hierarchical-Filter-Bug-Fixes.md`:

**October 18 Design Decision** (lines 162-169):
> When a user explicitly selects a vehicle make and clicks "Filter by Selected Makes", they are expressing intent to see everything for that make. Therefore:
> - Hierarchical filtering bypasses "Limit to Curated Years Only" filter

**Implementation** (FilterCacheManager.swift:540-578):
```swift
if let makeIds = forMakeIds, !makeIds.isEmpty {
    filteredModels = filterModelsByMakes(filteredModels, makeIds: makeIds)
    return filteredModels  // Early return - bypasses curated years filter
}
```

**Analysis**: This was an over-correction. The October 18 session fixed two bugs:
- ✅ Bug #1: Uncurated pair detection (correct fix, kept)
- ✅ Bug #2: Filtering order (correct fix, kept)
- ❌ Bug #2 Over-correction: Added bypass (incorrect, removed)

### Phase 6: Test Query with ART (NOVA)

**Expected**: 45 records (15 in 2017, 15 in 2018, 15 in 2019)

**Console Output**:
```
✅ Found match: 'ART' -> ID 80231
🔍 Model 'ART (NOVA)' (cleaned: 'ART') -> ID 80231
```

**Result**: Zero records returned

**Verification Query**:
```sql
SELECT m.id, m.name as model, mk.id as make_id, mk.name as make
FROM model_enum m
JOIN make_enum mk ON m.make_id = mk.id
WHERE m.id = 80231;
```

**Result**: `80231|ART|8|DODGE`

**Root Cause Identified**: Model ID 80231 is **DODGE+ART**, not **NOVA+ART**. The lookup by model name alone ("ART") returned the first match instead of the correct Make+Model pairing.

**Correct Model ID Query**:
```sql
SELECT m.id, m.name as model, mk.id as make_id, mk.name as make
FROM model_enum m
JOIN make_enum mk ON m.make_id = mk.id
WHERE mk.name = 'NOVA' AND m.name = 'ART';
```

**Result**: `9488|ART|60|NOVA` (correct ID)

---

## Root Causes Identified

### Bug 1: SQL NOT IN with NULL Values

**Location**: `FilterCacheManager.swift:245-263` (`loadUncuratedMakes()`)

**Problem**:
```sql
WHERE v.make_id NOT IN (
    SELECT DISTINCT v2.make_id FROM vehicles v2 ...
)
```

When the subquery contains ANY NULL values, the entire `NOT IN` clause returns zero rows. This is a well-known SQL gotcha.

**Why it happened**: The database contains 240,616 vehicles with NULL make_id in curated years.

**Impact**: `loadUncuratedMakes()` found zero Makes, so no `[uncurated:]` badges were assigned, so `getAvailableMakes()` filtering couldn't filter them out.

### Bug 2: October 18 Over-Correction

**Location**: `FilterCacheManager.swift:540-578` (`getAvailableModels()`)

**Problem**:
```swift
if let makeIds = forMakeIds, !makeIds.isEmpty {
    filteredModels = filterModelsByMakes(filteredModels, makeIds: makeIds)
    return filteredModels  // Bypasses curated years filter
}
```

**Why it happened**: October 18 session fixed a filtering order bug but added an early return that completely bypassed the curated years filter during hierarchical filtering.

**Design Philosophy Change**: The session established that "explicit user selection overrides filters," but this contradicted the actual user intent that "Limit to Curated Years should be absolute."

**Impact**: When user clicked "Filter by Selected Makes," uncurated models appeared with badges.

### Bug 3: Model Name Lookup Ambiguity

**Location**: `OptimizedQueryManager.swift:189-198`

**Problem**:
```swift
let cleanModel = FilterConfiguration.stripModelBadge(model)  // "ART (NOVA)" -> "ART"
if let id = try await enumManager.getEnumId(table: "model_enum", column: "name", value: cleanModel) {
    // Returns first match for name="ART" (DODGE+ART = 80231)
}
```

**Why it happened**: Model names are NOT unique across makes. "ART" exists for:
- DODGE (id=80231)
- NOVA (id=9488)
- NOVAB (id=...)
- NOVABUS (id=...)
- HONDA (id=...)

The name-only lookup returns the first match (lowest ID), not the correct Make+Model combination.

**Architectural Violation**: The enumeration table system depends on unique integer IDs, but the lookup was using non-unique string names.

**Impact**: All Make+Model filtered queries returned zero results because they searched for the wrong model_id.

---

## Solutions Implemented

### Fix 1: Change NOT IN to NOT EXISTS

**File**: `FilterCacheManager.swift:245-263`

**Before**:
```sql
SELECT v.make_id, COUNT(*) as record_count
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
WHERE y.year IN (2023, 2024)
AND v.make_id NOT IN (
    SELECT DISTINCT v2.make_id
    FROM vehicles v2
    JOIN year_enum y2 ON v2.year_id = y2.id
    WHERE y2.year IN (2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022)
)
GROUP BY v.make_id;
```

**After**:
```sql
SELECT u.make_id, u.record_count
FROM (
    SELECT v.make_id, COUNT(*) as record_count
    FROM vehicles v
    JOIN year_enum y ON v.year_id = y.id
    WHERE y.year IN (2023, 2024)
    GROUP BY v.make_id
) u
WHERE NOT EXISTS (
    SELECT 1
    FROM vehicles v2
    JOIN year_enum y2 ON v2.year_id = y2.id
    WHERE v2.make_id = u.make_id
    AND y2.year IN (2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022)
);
```

**Why this works**: `NOT EXISTS` evaluates to true/false for each row individually and handles NULL values correctly.

**Result**: Now finds 7,575 uncurated Makes including NOVAB and NOVABUS.

### Fix 2: Enhanced getAvailableMakes() Filtering

**File**: `FilterCacheManager.swift:525-550`

**Before**:
```swift
if limitToCuratedYears {
    return cachedMakes.filter { make in
        let makeId = String(make.id)
        return uncuratedMakes[makeId] == nil
    }
}
```

**After**:
```swift
if limitToCuratedYears {
    return cachedMakes.filter { make in
        let displayName = make.displayName

        // Check display name for uncurated badge (more robust)
        if displayName.contains("[uncurated:") {
            return false
        }

        // Also check dictionary (defensive double-check)
        let makeId = String(make.id)
        if uncuratedMakes[makeId] != nil {
            return false
        }

        return true
    }
}
```

**Why this works**: Badge-based filtering is more robust and catches edge cases where the dictionary might be inconsistent with badge assignments.

### Fix 3: Remove Curated Years Bypass

**File**: `FilterCacheManager.swift:552-581`

**Before**:
```swift
// FIRST: Apply hierarchical filtering if requested
if let makeIds = forMakeIds, !makeIds.isEmpty {
    filteredModels = filterModelsByMakes(filteredModels, makeIds: makeIds)

    // Return early - bypass curated years filter
    return filteredModels
}

// SECOND: Only apply curated years filter when NOT hierarchical filtering
if limitToCuratedYears {
    filteredModels = filteredModels.filter { ... }
}
```

**After**:
```swift
// FIRST: Apply hierarchical filtering if requested
// (October 18 fix: order matters - hierarchical filtering must come first)
if let makeIds = forMakeIds, !makeIds.isEmpty {
    filteredModels = filterModelsByMakes(filteredModels, makeIds: makeIds)
}

// SECOND: Apply curated years filter if requested
// This applies to ALL models, including hierarchically-filtered results
// When "Limit to Curated Years" is ON, no uncurated data should appear anywhere
if limitToCuratedYears {
    filteredModels = filteredModels.filter { model in
        let displayName = model.displayName
        if displayName.contains("[uncurated:") {
            return false
        }
        return true
    }
}
```

**Why this works**:
- Preserves October 18 fix for filtering order (hierarchical first)
- Removes early return bypass
- Makes "Limit to Curated Years" absolute (no exceptions)

### Fix 4: Use FilterCacheManager for Make Lookup

**File**: `OptimizedQueryManager.swift:178-195`

**Before**:
```swift
for make in filters.vehicleMakes {
    let cleanMake = FilterConfiguration.stripMakeBadge(make)
    if let id = try await enumManager.getEnumId(table: "make_enum", column: "name", value: cleanMake) {
        makeIds.append(id)
    }
}
```

**After**:
```swift
for make in filters.vehicleMakes {
    if let filterCache = databaseManager?.filterCacheManager {
        let allMakes = try await filterCache.getAvailableMakes(limitToCuratedYears: false)

        if let matchingMake = allMakes.first(where: { $0.displayName == make }) {
            print("🔍 Make '\(make)' -> ID \(matchingMake.id) (via FilterCacheManager)")
            makeIds.append(matchingMake.id)
        }
    }
}
```

**Why this works**: FilterCacheManager already loaded all Makes with correct IDs and display names. Direct lookup by displayName ensures exact match.

### Fix 5: Use FilterCacheManager for Model Lookup

**File**: `OptimizedQueryManager.swift:189-207`

**Before**:
```swift
for model in filters.vehicleModels {
    let cleanModel = FilterConfiguration.stripModelBadge(model)  // "ART (NOVA)" -> "ART"
    if let id = try await enumManager.getEnumId(table: "model_enum", column: "name", value: cleanModel) {
        // Returns WRONG ID (first match for name="ART")
        modelIds.append(id)
    }
}
```

**After**:
```swift
// For models, we MUST use FilterCacheManager to get the correct model_id
// because model names are NOT unique (e.g., "ART" exists for multiple makes)
// The FilterItem already has the correct model_id for the Make+Model combination
for model in filters.vehicleModels {
    if let filterCache = databaseManager?.filterCacheManager {
        let allModels = try await filterCache.getAvailableModels(limitToCuratedYears: false, forMakeIds: nil)

        if let matchingModel = allModels.first(where: { $0.displayName == model }) {
            print("🔍 Model '\(model)' -> ID \(matchingModel.id) (via FilterCacheManager)")
            modelIds.append(matchingModel.id)
        }
    }
}
```

**Why this works**:
- FilterCacheManager loads models with correct model_id from JOIN with make_enum
- Display name "ART (NOVA)" uniquely identifies the Make+Model combination
- Direct lookup preserves the correct model_id (9488 for NOVA+ART, not 80231 for DODGE+ART)

---

## Testing Results

### Test 1: Make Dropdown Filtering

**Setup**: "Limit to Curated Years" ON

**Action**: Type "nova" in Make search field

**Before**: NOVA, NOVAB, NOVABUS all appeared
**After**: ✅ Only NOVA appears

**Console Output**:
```
✅ Loaded 7575 uncurated Makes (only in uncurated years)
```

### Test 2: Model Dropdown During Hierarchical Filtering

**Setup**:
- "Limit to Curated Years" ON
- Select Make: NOVA
- Click "Filter by Selected Makes"

**Before**: Models showed `[uncurated:]` badges
**After**: ✅ Only 4 curated models shown (ART, BUS, HEV, LFT) with no badges

### Test 3: Query Results Accuracy

**Setup**:
- Model: ART (NOVA)
- Years: 2011-2022 selected

**Before**: Zero records returned
**After**: ✅ 45 records returned (15 in 2017, 15 in 2018, 15 in 2019)

**Console Output**:
```
🔍 Model 'ART (NOVA)' -> ID 9488 (via FilterCacheManager)
✅ Optimized vehicle query completed in 0.030s - 3 data points
```

**Verification**:
- Correct model_id: 9488 (NOVA+ART) ✓
- Not wrong model_id: 80231 (DODGE+ART) ✓

---

## Design Principles Clarified

### "Limit to Curated Years" is Absolute

**Before October 18**: Feature didn't exist (toggle added in earlier session)

**October 18 Decision**: "Explicit user selection overrides filters"
- When hierarchical filtering active, show all models for selected makes
- Rationale: User wants to explore full model range

**October 20 Reversal**: "Limit to Curated Years is absolute"
- When toggle is ON, zero uncurated data visible anywhere
- No exceptions for hierarchical filtering or any other feature
- Rationale: User intent is to analyze only curated data

### Integer-Based Architecture Enforcement

**Principle**: All categorical data uses integer enumeration tables
- Makes use `make_enum.id` (integer foreign key)
- Models use `model_enum.id` (integer foreign key)
- Display names are for UI only, never for queries

**Violation**: OptimizedQueryManager was using string name lookups
- Broke down with non-unique model names
- Violated architectural integrity

**Correction**: All ID lookups now use FilterCacheManager
- Preserves Make+Model pairing
- Uses pre-loaded FilterItems with correct IDs
- Maintains integer-based architecture

---

## Files Modified

### FilterCacheManager.swift

**Line 245-263**: `loadUncuratedMakes()` - Changed NOT IN to NOT EXISTS
```swift
// Use NOT EXISTS instead of NOT IN to handle NULL make_ids correctly
```

**Lines 525-550**: `getAvailableMakes()` - Enhanced filtering with badge check
```swift
// Check display name for uncurated badge (more robust)
if displayName.contains("[uncurated:") {
    return false
}
```

**Lines 552-581**: `getAvailableModels()` - Removed curated years bypass
```swift
// SECOND: Apply curated years filter if requested
// This applies to ALL models, including hierarchically-filtered results
```

### OptimizedQueryManager.swift

**Lines 178-195**: Make lookup - Use FilterCacheManager instead of name lookup
```swift
// For makes, use FilterCacheManager to ensure correct ID lookup
let allMakes = try await filterCache.getAvailableMakes(limitToCuratedYears: false)
if let matchingMake = allMakes.first(where: { $0.displayName == make }) {
    makeIds.append(matchingMake.id)
}
```

**Lines 189-207**: Model lookup - Use FilterCacheManager to preserve Make+Model pairing
```swift
// For models, we MUST use FilterCacheManager to get the correct model_id
// because model names are NOT unique (e.g., "ART" exists for multiple makes)
let allModels = try await filterCache.getAvailableModels(limitToCuratedYears: false, forMakeIds: nil)
if let matchingModel = allModels.first(where: { $0.displayName == model }) {
    modelIds.append(matchingModel.id)
}
```

---

## Performance Impact

### FilterCacheManager Lookups

**Before**: Direct SQL queries for each Make/Model
- Query time: ~1-5ms per lookup
- For 10 filters: 10-50ms total

**After**: In-memory array search
- Search time: <1ms per lookup (array of ~400 models)
- For 10 filters: <10ms total

**Verdict**: ✅ Performance improvement (faster and cached)

### Memory Impact

**Before**: No additional memory (direct SQL)
**After**: FilterItems already loaded at startup
- Makes: ~2,000 items × 50 bytes = 100KB
- Models: ~10,000 items × 100 bytes = 1MB

**Verdict**: ✅ Negligible (data already cached)

---

## Known Remaining Issues

### Minor UX Issue: Year Auto-Selection

**Problem**: When "Limit to Curated Years" toggle is switched ON:
- Years 2023-2024 become greyed out ✅
- BUT they remain selected and get auto-reselected ❌

**Expected**: Uncurated years should be auto-deselected when toggle is ON

**Impact**: Low - queries correctly exclude uncurated years via `OptimizedQueryManager.swift:105-113`
```swift
if filters.limitToCuratedYears {
    yearsToQuery = filters.years.intersection(curatedYears)  // Filters at query time
}
```

**Status**: Not fixed in this session (deferred to future work)

---

## Related Sessions

### October 18, 2025
**Document**: `2025-10-18-Uncurated-Badge-and-Hierarchical-Filter-Bug-Fixes.md`

**Context**: Fixed two bugs in badge detection and filtering order:
- ✅ Bug #1: Uncurated pair detection (using NOT EXISTS) - Correct
- ✅ Bug #2: Filtering order (hierarchical first, then curated) - Correct
- ❌ Bug #2 Over-correction: Added early return bypass - Incorrect (reversed in this session)

**Design Decision**: "Explicit user selection overrides filters"
- Reversed in this session to "Limit to Curated Years is absolute"

### October 14, 2025
**Document**: `2025-10-14-Hierarchical-Filtering-AttributeGraph-Fix-Complete.md`

**Context**: Implemented manual button-based hierarchical filtering
- Resolved AttributeGraph crashes by using manual button instead of onChange
- Established pattern for avoiding circular binding issues
- This session's fixes preserve the manual button approach

---

## Key Insights for Future Development

### 1. SQL NOT IN with NULL is Dangerous

**Rule**: Always use `NOT EXISTS` instead of `NOT IN` for subqueries
- `NOT IN` with ANY NULL values returns empty result set
- `NOT EXISTS` handles NULLs correctly
- This is a well-known SQL gotcha but easy to miss

### 2. Design Decisions Can Over-Correct

**Observation**: October 18 session fixed a real bug (filtering order) but added an unnecessary bypass
- The bypass solved the immediate problem but violated user intent
- Sometimes the simplest fix is not adding extra logic, but removing it

### 3. String Lookups Break Integer Architecture

**Lesson**: When using integer enumeration tables, NEVER do string-based lookups
- Non-unique strings (model names) cause wrong IDs
- Always use pre-loaded FilterItems with correct ID+displayName pairs
- Architectural integrity matters more than code simplicity

### 4. Console Logging is Critical

**Value**: Detailed console output enabled rapid diagnosis
- `🔍` emoji for lookups made it easy to spot wrong IDs
- `✅` emoji for successes confirmed correct behavior
- Logging SQL queries and bind values revealed the exact issue

### 5. Historical Context Documents Save Time

**Impact**: Session notes from October 18 prevented wasted time
- Immediately understood why the bypass existed
- Could evaluate whether to keep or reverse the decision
- Avoided re-breaking the October 18 fixes

---

## Commit Message (Recommended)

```
fix: Correct curated years filtering and model ID lookup bugs

Fixes three critical bugs affecting "Limit to Curated Years" filter:

1. SQL NOT IN with NULL values
   - Changed loadUncuratedMakes() to use NOT EXISTS pattern
   - Handles 240K NULL make_ids correctly
   - Now finds 7,575 uncurated Makes (was finding 0)

2. Curated years filter bypass during hierarchical filtering
   - Removed October 18 early return that bypassed filter
   - "Limit to Curated Years" now absolute (no exceptions)
   - Uncurated models no longer appear during hierarchical filtering

3. Model ID lookup returning wrong IDs
   - Changed from string name lookup to FilterCacheManager lookup
   - Preserves correct Make+Model pairing (model names not unique)
   - Example: NOVA+ART (9488) vs DODGE+ART (80231)

Testing:
- Make search "nova" shows only NOVA (NOVAB/NOVABUS hidden) ✓
- Hierarchical filtering shows only curated models ✓
- NOVA+ART query returns 45 records (was 0) ✓

Files changed:
- FilterCacheManager.swift: NOT EXISTS, enhanced filtering, removed bypass
- OptimizedQueryManager.swift: Use FilterCacheManager for Make/Model lookups

Related: October 18 session (reversed over-correction), October 14 session (preserved manual button approach)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Appendix A: Diagnostic Queries Used

### Find NULL make_ids
```sql
SELECT COUNT(*) as null_count
FROM vehicles v2
JOIN year_enum y2 ON v2.year_id = y2.id
WHERE y2.year IN (2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022)
AND v2.make_id IS NULL;
```

### Verify uncurated Makes
```sql
SELECT u.make_id, m.name, u.record_count
FROM (
    SELECT v.make_id, COUNT(*) as record_count
    FROM vehicles v
    JOIN year_enum y ON v.year_id = y.id
    WHERE y.year IN (2023, 2024)
    GROUP BY v.make_id
) u
JOIN make_enum m ON u.make_id = m.id
WHERE NOT EXISTS (
    SELECT 1
    FROM vehicles v2
    JOIN year_enum y2 ON v2.year_id = y2.id
    WHERE v2.make_id = u.make_id
    AND y2.year IN (2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022)
)
AND m.name IN ('NOVAB', 'NOVABUS')
ORDER BY m.name;
```

### Find correct model_id for Make+Model pair
```sql
SELECT m.id, m.name as model, mk.id as make_id, mk.name as make
FROM model_enum m
JOIN make_enum mk ON m.make_id = mk.id
WHERE mk.name = 'NOVA' AND m.name = 'ART';
```

### Verify year distribution for Make+Model pair
```sql
SELECT y.year, COUNT(*) as record_count
FROM vehicles v
JOIN make_enum mk ON v.make_id = mk.id
JOIN model_enum m ON v.model_id = m.id
JOIN year_enum y ON v.year_id = y.id
WHERE mk.name = 'NOVA' AND m.name = 'ART'
GROUP BY y.year
ORDER BY y.year;
```

---

## Appendix B: Console Output Patterns

### Successful Make Lookup
```
🔍 Make 'NOVA' -> ID 60 (via FilterCacheManager)
```

### Successful Model Lookup
```
🔍 Model 'ART (NOVA)' -> ID 9488 (via FilterCacheManager)
```

### Failed Lookup (Before Fix)
```
⚠️ Model 'ART' not found in enum table
```

### Wrong Model ID (Before Fix)
```
✅ Found match: 'ART' -> ID 80231
🔍 Model 'ART (NOVA)' (cleaned: 'ART') -> ID 80231
```

### Uncurated Makes Loaded
```
✅ Loaded 7575 uncurated Makes (only in uncurated years)
```

### Query Results
```
✅ Optimized vehicle query completed in 0.030s - 3 data points
```

---

**End of Handoff Document**

**Status**: ✅ All critical bugs fixed, ready for commit
**Next Steps**: Stage and commit changes, then address year auto-selection UX issue
**Session Time**: ~2 hours of diagnosis and fixes
**Key Achievement**: Preserved integer-based architecture while fixing filter logic
