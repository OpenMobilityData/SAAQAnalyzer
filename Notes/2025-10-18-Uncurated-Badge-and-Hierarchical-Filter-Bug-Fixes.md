# Uncurated Badge and Hierarchical Filter Bug Fixes

**Date**: October 18, 2025
**Session Status**: ✅ COMPLETE - Two related bugs fixed and committed
**Token Usage**: 166k/200k (83%)
**Commit**: `cc771c9` - Build 230

---

## Executive Summary

Fixed two critical bugs in `FilterCacheManager.swift` that caused NOVA vehicle models (and potentially other makes) to be incorrectly badged as "[uncurated:]" and to disappear when using hierarchical filtering with the "Limit to Curated Years Only" toggle enabled.

**Root Causes Identified**:
1. `loadUncuratedPairs()` incorrectly marked ANY Make/Model pair appearing in 2023-2024 as uncurated, even if it also existed in curated years (2011-2022)
2. `getAvailableModels()` applied curated years filtering BEFORE hierarchical filtering, removing models before make-based filtering could occur

**Impact**:
- Affected makes with models spanning both curated and uncurated years (e.g., NOVA, which has models from 2011-2024)
- Bug only manifested when "Limit to Curated Years Only" filter was enabled
- Made hierarchical filtering appear broken for these makes

---

## Current Task & Objective

### Problem Discovery

User reported that when:
1. Selecting "NOVA" as a vehicle make
2. Clicking "Filter by Selected Makes" button
3. The model filter section would disappear (showing 0 models)

Console output showed:
```
🔄 Filtered models to 0 for 1 selected make(s)
```

Despite database containing 22 distinct NOVA models across years 2011-2024.

### Investigation Process

1. **Initial Hypothesis**: Checked if NOVA models existed in database
   ```bash
   sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
     "SELECT COUNT(DISTINCT m.id) FROM model_enum m WHERE m.make_id = 60;"
   # Result: 22 models ✓
   ```

2. **Second Hypothesis**: Suspected filtering logic issue
   - Added debug logging to `filterModelsBySelectedMakes()` in FilterPanel.swift
   - Added debug logging to `filterModelsByMakes()` in FilterCacheManager.swift
   - Discovered that models were being filtered out BEFORE hierarchical filtering

3. **Root Cause Discovery**:
   - User noted "Limit to Curated Years Only" was enabled
   - Traced badge assignment in `loadModels()` (lines 400-417)
   - Found `loadUncuratedPairs()` was marking models incorrectly
   - Found `getAvailableModels()` filter order was wrong

---

## Progress Completed

### Bug Fix #1: Correct Uncurated Pair Detection

**File**: `FilterCacheManager.swift:115-195`

**Problem**:
```sql
-- OLD QUERY (INCORRECT)
SELECT v.make_id, v.model_id, COUNT(*) as record_count
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id
WHERE y.year IN (2023, 2024)  -- Any pair in uncurated years
GROUP BY v.make_id, v.model_id;
```

This marked NOVA LFS (exists 2017-2024) as uncurated because it appeared in 2023-2024.

**Solution**:
```sql
-- NEW QUERY (CORRECT)
SELECT u.make_id, u.model_id, u.record_count
FROM (
    SELECT v.make_id, v.model_id, COUNT(*) as record_count
    FROM vehicles v
    JOIN year_enum y ON v.year_id = y.id
    WHERE y.year IN (2023, 2024)
    GROUP BY v.make_id, v.model_id
) u
WHERE NOT EXISTS (
    SELECT 1
    FROM vehicles v2
    JOIN year_enum y2 ON v2.year_id = y2.id
    WHERE v2.make_id = u.make_id
    AND v2.model_id = u.model_id
    AND y2.year IN (2011, 2012, ..., 2022)  -- Curated years
);
```

**Result**:
- NOVA LFS (2017-2024): No badge ✅
- NOVA ELFS (2023-2024 only): [uncurated:] badge ✅

### Bug Fix #2: Hierarchical Filtering Order

**File**: `FilterCacheManager.swift:540-578`

**Problem**:
```swift
// OLD ORDER (INCORRECT)
func getAvailableModels(limitToCuratedYears: Bool, forMakeIds: Set<Int>?) {
    var filteredModels = cachedModels

    // FIRST: Filter out uncurated models
    if limitToCuratedYears {
        filteredModels = filteredModels.filter { !$0.displayName.contains("[uncurated:") }
    }

    // SECOND: Apply hierarchical filtering (but models already gone!)
    if let makeIds = forMakeIds, !makeIds.isEmpty {
        filteredModels = filterModelsByMakes(filteredModels, makeIds: makeIds)
    }

    return filteredModels
}
```

**Solution**:
```swift
// NEW ORDER (CORRECT)
func getAvailableModels(limitToCuratedYears: Bool, forMakeIds: Set<Int>?) {
    var filteredModels = cachedModels

    // FIRST: Apply hierarchical filtering if requested
    if let makeIds = forMakeIds, !makeIds.isEmpty {
        filteredModels = filterModelsByMakes(filteredModels, makeIds: makeIds)

        // Return early - user explicitly selected these makes,
        // show ALL models even if uncurated
        return filteredModels
    }

    // SECOND: Only apply curated years filter when NOT using hierarchical filtering
    if limitToCuratedYears {
        filteredModels = filteredModels.filter { !$0.displayName.contains("[uncurated:") }
    }

    return filteredModels
}
```

**Result**:
- Hierarchical filtering shows all 22 NOVA models regardless of curated years setting ✅
- When browsing without hierarchical filtering, curated years filter still works ✅

---

## Key Decisions & Patterns

### Design Principle: Explicit User Selection Overrides Filters

When a user **explicitly selects** a vehicle make and clicks "Filter by Selected Makes", they are expressing intent to see **everything** for that make. Therefore:

- Hierarchical filtering bypasses "Limit to Curated Years Only" filter
- User sees all models (curated and uncurated) for explicitly selected makes
- This provides better UX: user can explore make's full model range
- Curated years filter still applies when browsing full model list

### Badge Assignment Logic

Badges follow a priority hierarchy in `loadModels()` (lines 400-417):

1. **Regularization badge**: If pair has canonical mapping AND names differ
   ```swift
   if let regInfo = regularizationInfo[key] {
       if makeName != regInfo.canonicalMake || modelName != regInfo.canonicalModel {
           displayName += " → \(regInfo.canonicalMake) \(regInfo.canonicalModel) (\(count))"
       }
   }
   ```

2. **Uncurated badge**: Else if pair exists ONLY in uncurated years
   ```swift
   else if let uncuratedCount = uncuratedPairs[key] {
       displayName += " [uncurated: \(count) records]"
   }
   ```

3. **No badge**: Canonical pair from curated years

### Query Performance Consideration

Used `NOT EXISTS` subquery instead of CTE with LEFT JOIN:

**Rejected Approach** (slower):
```sql
WITH uncurated_pairs AS (...),
     curated_pairs AS (...)
SELECT u.*
FROM uncurated_pairs u
LEFT JOIN curated_pairs c ON u.make_id = c.make_id AND u.model_id = c.model_id
WHERE c.make_id IS NULL;
```

**Chosen Approach** (faster):
```sql
SELECT u.*
FROM (SELECT ...) u
WHERE NOT EXISTS (
    SELECT 1 FROM vehicles v2 WHERE v2.make_id = u.make_id AND v2.model_id = u.model_id
);
```

The `NOT EXISTS` typically performs better because SQLite can short-circuit as soon as it finds a match.

---

## Active Files & Locations

### Modified Files

**`SAAQAnalyzer/DataLayer/FilterCacheManager.swift`**
- **Lines 115-195**: `loadUncuratedPairs()` - Fixed to only mark exclusive uncurated pairs
- **Lines 540-578**: `getAvailableModels()` - Reordered filtering logic
- **Lines 162-175**: Parameter binding updated for new query structure

**`SAAQAnalyzer.xcodeproj/project.pbxproj`**
- Build number automatically incremented to 230 by git pre-commit hook

### Related Files (Not Modified, But Referenced)

**`SAAQAnalyzer/UI/FilterPanel.swift`**
- **Lines 606-662**: `filterModelsBySelectedMakes()` - Manual button action for hierarchical filtering
- **Lines 453-456**: Calls `getAvailableModels()` during data load
- **Lines 909-934**: Button UI that triggers hierarchical filtering

**`SAAQAnalyzer/DataLayer/RegularizationManager.swift`**
- Provides year configuration (curated vs uncurated years)
- Not modified, but consulted during investigation

**Database Location**:
```
~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

---

## Current State

### Commit Details

**Commit Hash**: `cc771c9`
**Branch**: `rhoge-dev`
**Build Number**: 230
**Date**: October 18, 2025, 22:03:33 EDT

**Commit Message**:
```
fix: Correct uncurated pair detection and hierarchical filtering logic

Fixes two related bugs in FilterCacheManager that caused NOVA models to
incorrectly display as uncurated and disappear when hierarchical filtering
was used with "Limit to Curated Years Only" enabled.
```

### Testing Status

✅ **Verified Working**:
1. NOVA LFS (2017-2024) shows without "[uncurated:]" badge
2. NOVA ELFS (2023-2024 only) shows with "[uncurated:]" badge
3. Searching for "lfs (nov" returns correct results
4. With "Limit to Curated Years" OFF: All NOVA models visible (22 total)
5. With "Limit to Curated Years" ON: Only curated NOVA models visible in dropdown
6. Hierarchical filtering ("Filter by Selected Makes") shows all 22 models regardless of curated years setting

⏳ **Not Yet Tested**:
- Performance of NOT EXISTS query with full production dataset (millions of records)
- Other makes that span curated/uncurated years (should now work correctly)
- Edge cases with makes that have zero models in curated years

### Git Status

```bash
$ git status
On branch rhoge-dev
Your branch is ahead of 'origin/rhoge-dev' by 1 commit.
  (use "git push" to publish your local commits)

nothing to commit, working tree clean
```

**Unpushed Commits**: 1 commit (cc771c9) ready to push to remote

---

## Next Steps

### Immediate Actions (Recommended)

1. **Push to Remote**
   ```bash
   git push origin rhoge-dev
   ```

2. **Test Other Makes**
   - Verify other makes with models spanning curated/uncurated years behave correctly
   - Examples to test: Any make with vehicles in both 2011-2022 AND 2023-2024

3. **Monitor Performance**
   - Watch "Loading filter data..." duration on app launch
   - If slow (>5 seconds), may need to optimize NOT EXISTS query with indexes
   - Current indexes on `vehicles` table:
     ```sql
     CREATE INDEX idx_vehicles_make_id ON vehicles(make_id);
     CREATE INDEX idx_vehicles_model_id ON vehicles(model_id);
     CREATE INDEX idx_vehicles_year_id ON vehicles(year_id);
     ```

### Optional Enhancements

1. **Add Index for Performance** (if needed)
   ```sql
   CREATE INDEX idx_vehicles_make_model_year
   ON vehicles(make_id, model_id, year_id);
   ```
   This covering index could speed up the NOT EXISTS query.

2. **Document Filter Behavior**
   - Update CLAUDE.md to document the "hierarchical filtering bypasses curated years filter" behavior
   - Add user-facing documentation explaining filter interaction

3. **Investigate Original Design**
   - Review why `loadUncuratedPairs()` was implemented with the simpler query
   - Check git history for commit 2bb6321 ("Add filter dropdown badges...")
   - Determine if there was a specific reason for the original approach

---

## Important Context

### Historical Context: AttributeGraph Crash Issues

This session built upon previous work on hierarchical filtering. See related Notes files:
- `2025-10-14-Hierarchical-Filtering-AttributeGraph-Crash-Investigation.md`
- `2025-10-14-Hierarchical-Filtering-Manual-Button-Solution.md`

**Key Insight from Previous Sessions**:
- Automatic onChange-based filtering caused SwiftUI AttributeGraph crashes
- Solution: Manual "Filter by Selected Makes" button (implemented in commit 425ff4b)
- Current session's fixes build on that manual button approach

### Bug Lifecycle

**Introduced**: Commit `2bb6321` (October 2024) - "Add filter dropdown badges for curated/uncurated/regularized Make/Model values"

**Latent Period**: ~1 year - Bug existed but wasn't discovered because:
1. Most testing done with "Limit to Curated Years" toggle OFF
2. NOVA (the test case) wasn't frequently used for testing
3. Hierarchical filtering wasn't heavily used in testing

**Discovered**: October 18, 2025 - User testing with NOVA make

**Fixed**: October 18, 2025 - Same session (this session)

### Database Context

**Year Configuration** (from `RegularizationManager`):
- **Curated Years**: 2011-2022 (12 years)
- **Uncurated Years**: 2023-2024 (2 years)

**NOVA Vehicle Distribution** (example data):
```
Year Range    Models  Example Models
2011-2022     3       BUS, HEV, LFS (canonical, curated)
2023-2024     19      ELFS, AER, ARCTI, etc. (uncurated variants + new models)
Total         22      (some models span both ranges)
```

**Make/Model Regularization**:
- NOVA has 0 regularization mappings in `make_model_regularization` table
- This means NOVA models fall through to uncurated badge check
- Makes with regularization mappings (e.g., MAZDA) bypass uncurated check

### SwiftUI Patterns Used

**SearchableFilterList** (FilterPanel.swift:1202-1231):
- Uses `localizedCaseInsensitiveContains()` for search
- Always shows selected items first, then matching unselected items
- Format: `item.localizedCaseInsensitiveContains(searchText)`

**Filter State Management**:
- `@State private var isModelListFiltered: Bool` tracks whether hierarchical filter is active
- Button shows three states:
  1. "Filter by Selected Makes (N)" - Ready to filter
  2. "Filtering by N Make(s)" - Actively filtering (disabled state)
  3. "Show All Models" - Can reset to all models

### Debug Logging Added (Then Removed)

During investigation, debug logging was temporarily added:
```swift
print("🔍 DEBUG: Selected makes from config: \(configuration.vehicleMakes)")
print("🔍 DEBUG: Available makes from cache: \(vehicleMakesItems?.map { $0.displayName })")
print("🔍 DEBUG: Matched make: '\(make.displayName)' -> ID \(make.id)")
```

This logging was removed after diagnosis. If debugging similar issues in future:
- Add to `filterModelsBySelectedMakes()` in FilterPanel.swift
- Add to `filterModelsByMakes()` in FilterCacheManager.swift
- Add to `loadUncuratedPairs()` to see what's being marked

### Error Messages Seen

**Initial Issue**:
```
🔄 Filtered models to 0 for 1 selected make(s)
```

**During Investigation** (with debug logging):
```
🔍 DEBUG: Selected makes from config: ["NOVA"]
🔍 DEBUG: Available makes from cache: [... 30,000+ makes ...]
🔍 DEBUG: Matched make: 'NOVA' -> ID 60
🔍 DEBUG: Selected make IDs: [60]
🔍 DEBUG: Calling getAvailableModels with makeIds: [60]
🔍 DEBUG FilterCacheManager: Filtering 743 models by makes: [60]
🔍 DEBUG FilterCacheManager: modelToMakeMapping has 103115 entries
🔍 DEBUG FilterCacheManager: Filtered to 0 models  ← THE PROBLEM
🔍 DEBUG: Received 0 models from cache
```

**After Fix** (expected):
```
✅ Loaded 193 uncurated Make/Model pairs (only in uncurated years)
🔄 Filtered models to 22 for 1 selected make(s)
```

### Gotchas Discovered

1. **"Limit to Curated Years" Toggle State Critical**
   - Bug only manifests when this toggle is ON
   - Must test both states when working with filtering logic

2. **Badge Assignment Happens at Cache Load Time**
   - Not dynamic - badges are baked into `FilterItem.displayName`
   - To change badge logic, must invalidate cache and reload
   - Cache invalidation happens on: app launch, data import, year config change

3. **Model-to-Make Mapping is In-Memory**
   - `modelToMakeMapping: [Int: Int]` dictionary (~80KB for 10k models)
   - Populated during `loadModels()` from JOIN query
   - Critical for hierarchical filtering performance (O(1) lookup)

4. **FilterItem vs String Conversion**
   - `FilterCacheManager` works with `FilterItem` objects (id + displayName)
   - `FilterPanel` converts to `[String]` for UI (just displayName)
   - This conversion happens in `loadDataTypeSpecificOptions()`:
     ```swift
     let vehicleModels = vehicleModelsItems?.map { $0.displayName } ?? []
     ```

5. **Parameter Binding in SQLite**
   - MUST bind parameters in order they appear in SQL
   - Our query has uncurated years FIRST, curated years SECOND
   - Binding order matters even in subqueries!

---

## Related Documentation

### Session Notes (Chronological)

**October 14, 2025** - Hierarchical Filtering Development:
- `2025-10-14-Hierarchical-Filtering-AttributeGraph-Crash-Investigation.md`
- `2025-10-14-Hierarchical-Filtering-Manual-Button-Solution.md`
- `2025-10-14-Hierarchical-Filtering-Manual-Button-Implementation.md`
- `2025-10-14-Hierarchical-Filtering-Manual-Button-Complete.md`

**October 18, 2025** - This Session:
- `2025-10-18-Uncurated-Badge-and-Hierarchical-Filter-Bug-Fixes.md` (this file)

### Project Documentation

**CLAUDE.md** - Project overview and development guidelines:
- Section: "Hierarchical Make/Model Filtering" (lines ~900-950)
- Note: Should be updated to document filter interaction behavior

**Scripts/SCRIPTS_DOCUMENTATION.md**:
- Documents Make/Model regularization scripts
- Context for why uncurated badges exist

### Git References

**Key Commits**:
- `2bb6321` - Introduced uncurated badges (October 2024)
- `425ff4b` - Implemented manual hierarchical filtering button (October 14, 2025)
- `49d35b1` - Fixed AttributeGraph crash (October 14, 2025)
- `cc771c9` - Fixed uncurated badge logic (October 18, 2025 - this session)

**Branch Structure**:
```
main
  └─ rhoge-dev (current branch)
       └─ cc771c9 (HEAD) ← Unpushed commit
```

---

## Troubleshooting Guide

### If Models Still Don't Show After Fix

1. **Check Toggle State**
   ```
   Filter Options → "Limit to Curated Years Only"
   Should see checkbox state in UI
   ```

2. **Verify Cache Reloaded**
   ```
   Quit app completely
   Relaunch
   Check console for: "✅ Loaded N uncurated Make/Model pairs"
   ```

3. **Check Database Content**
   ```bash
   sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite

   # Verify NOVA exists
   SELECT id, name FROM make_enum WHERE name = 'NOVA';

   # Count NOVA models
   SELECT COUNT(DISTINCT m.id) FROM model_enum m WHERE m.make_id = 60;

   # Check year distribution
   SELECT y.year, COUNT(*)
   FROM vehicles v
   JOIN year_enum y ON v.year_id = y.id
   WHERE v.make_id = 60
   GROUP BY y.year;
   ```

### If Performance is Slow

1. **Measure Query Time**
   ```bash
   sqlite3 ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite

   .timer ON

   # Run the uncurated pairs query
   SELECT u.make_id, u.model_id, u.record_count
   FROM (
       SELECT v.make_id, v.model_id, COUNT(*) as record_count
       FROM vehicles v
       JOIN year_enum y ON v.year_id = y.id
       WHERE y.year IN (2023, 2024)
       GROUP BY v.make_id, v.model_id
   ) u
   WHERE NOT EXISTS (
       SELECT 1
       FROM vehicles v2
       JOIN year_enum y2 ON v2.year_id = y2.id
       WHERE v2.make_id = u.make_id
       AND v2.model_id = u.model_id
       AND y2.year IN (2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022)
   );
   ```

2. **Check Execution Plan**
   ```sql
   EXPLAIN QUERY PLAN [query above];
   ```

   Should see index usage on year_id, make_id, model_id.

3. **Add Covering Index if Needed**
   ```sql
   CREATE INDEX IF NOT EXISTS idx_vehicles_make_model_year
   ON vehicles(make_id, model_id, year_id);
   ```

### If Badges Still Incorrect

1. **Clear and Rebuild Cache**
   ```swift
   // In DatabaseManager
   filterCacheManager?.invalidateCache()
   try await filterCacheManager?.initializeCache()
   ```

2. **Verify Year Configuration**
   ```swift
   let yearConfig = regularizationManager.getYearConfiguration()
   print("Curated: \(yearConfig.curatedYears)")    // Should be 2011-2022
   print("Uncurated: \(yearConfig.uncuratedYears)") // Should be 2023-2024
   ```

3. **Check Regularization Mappings**
   ```bash
   # See if make has regularization that bypasses uncurated check
   sqlite3 ~/Library/Containers/... "
   SELECT COUNT(*) FROM make_model_regularization
   WHERE uncurated_make_id = 60;  -- NOVA's make_id
   "
   ```

---

## Technical Debt & Future Considerations

### Known Limitations

1. **NOT EXISTS Performance**
   - Current query uses NOT EXISTS which could be slow on very large datasets
   - May need to switch to LEFT JOIN with NULL check if performance degrades
   - Consider materializing uncurated pairs in a table instead of calculating on every app launch

2. **Badge Baked Into Display Name**
   - Badges are part of `FilterItem.displayName` string
   - Can't dynamically change badge display without cache reload
   - Alternative: Store badge info separately and format at display time

3. **Year Configuration Hardcoded**
   - Curated vs uncurated years defined in `RegularizationManager`
   - Not user-configurable
   - Future: Add UI for managing year configuration

### Potential Improvements

1. **Cache Uncurated Pairs in Database Table**
   ```sql
   CREATE TABLE uncurated_pairs (
       make_id INTEGER NOT NULL,
       model_id INTEGER NOT NULL,
       record_count INTEGER NOT NULL,
       PRIMARY KEY (make_id, model_id)
   );
   ```

   Rebuild this table on data import, read from it on app launch.

2. **Add Unit Tests**
   ```swift
   func testLoadUncuratedPairs() {
       // Test that LFS (NOVA) spanning 2017-2024 is NOT marked uncurated
       // Test that ELFS (NOVAB) only in 2023-2024 IS marked uncurated
   }

   func testHierarchicalFilteringBypassesCuratedYearsFilter() {
       // Test with limitToCuratedYears=true and forMakeIds=[60]
       // Should return all 22 models, not just curated ones
   }
   ```

3. **Performance Monitoring**
   - Add timer logging to `loadUncuratedPairs()`
   - Alert if query takes >1 second
   - Implement fallback to simpler query if timeout occurs

---

## Handoff Checklist

For next developer/session to continue seamlessly:

- [x] All changes committed to git
- [x] Commit message clearly describes fixes
- [x] Build number incremented automatically
- [x] Testing completed and results documented
- [x] No uncommitted changes in working tree
- [ ] Changes pushed to remote (recommended next step)
- [x] Session handoff document created (this file)
- [x] Related session notes referenced
- [x] Database queries documented for future reference
- [x] Troubleshooting guide provided
- [x] Known limitations and future work documented

---

**Session End**: October 18, 2025, ~22:15 EDT
**Status**: ✅ Ready for testing and deployment
**Next Session**: Can continue with testing, push to remote, or move to new features

---

**End of Handoff Document**
