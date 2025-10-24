# Filter UX Enhancements: Curated Years & Hierarchical Make/Model - Phase 1 Handoff

**Date**: October 13, 2025
**Session Status**: Phase 1 Complete (Foundation)
**Build Status**: ✅ Building and running successfully
**Token Usage**: 140k/200k (70%)

---

## 1. Current Task & Objective

### Overall Goal
Implement two UX enhancements to improve filter panel usability when working with regularization:

**Feature 1: "Limit to Curated Years Only" Toggle**
- **Purpose**: Allow users to exclude uncurated years entirely from analysis
- **Behavior**: When enabled, removes uncurated Make/Model pairs from filter dropdowns and restricts queries to curated years only
- **Use Case**: Users who want clean filter dropdowns without `[uncurated: X records]` badges

**Feature 2: "Hierarchical Make/Model Filtering" Toggle**
- **Purpose**: Make Model dropdown context-aware based on selected Make(s)
- **Behavior**: When enabled, Model dropdown only shows models for currently selected Make(s)
- **Use Case**: Reduces cognitive load when working with large Make/Model lists; makes regularization mapping clearer

### User Story
> "When query regularization is disabled, the filter sections in the user panel still show non-regularized options from uncurated records. There are situations where the user will want to disable query regularization and only have the canonical options appear in filter sections."

---

## 2. Progress Completed

### ✅ Phase 1: Foundation (Complete)

#### 2.1 Configuration Properties Added
**File**: `SAAQAnalyzer/Models/DataModels.swift:1131-1132`

```swift
// Regularization and filter UI configuration
var limitToCuratedYears: Bool = false  // true = exclude uncurated years from queries and filter dropdowns
var hierarchicalMakeModel: Bool = false  // true = Model dropdown shows only models for selected Make(s)
```

**Impact**:
- Both properties default to `false` (preserves current behavior)
- `FilterConfiguration` struct now has hooks for both features
- No database changes required
- App builds and runs successfully with these additions

#### 2.2 Architecture Analysis Completed
**Understanding Achieved**:
- **RegularizationManager** (`RegularizationManager.swift`):
  - Manages Make/Model regularization mappings
  - Has `curatedYears` and `uncuratedYears` sets from `RegularizationYearConfiguration`
  - `getYearConfiguration()` provides access to year curation status

- **FilterCacheManager** (`FilterCacheManager.swift`):
  - Lines 289-336: `loadMakes()` - Loads all Makes, adds badges to uncurated items
  - Lines 338-392: `loadModels()` - Loads all Models, adds badges to uncurated pairs
  - Lines 93-156: `loadUncuratedPairs()` - Identifies Make/Model pairs from uncurated years
  - Lines 176-250: `loadUncuratedMakes()` - Identifies Makes that exist ONLY in uncurated years
  - Already tracks which items are uncurated via dictionaries:
    - `uncuratedPairs: [String: Int]` (key: "makeId_modelId")
    - `uncuratedMakes: [String: Int]` (key: "makeId")

- **OptimizedQueryManager** (`OptimizedQueryManager.swift:186`):
  - Uses `regularizationEnabled` flag for query-time regularization
  - Expands Make/Model IDs bidirectionally when regularization is enabled

#### 2.3 Key Design Decisions

**Decision 1: Configuration at FilterConfiguration Level**
- Store toggle states in `FilterConfiguration` struct (not global settings)
- Allows per-query control of filtering behavior
- Consistent with existing patterns (e.g., `normalizeRoadWearIndex`)

**Decision 2: Filter Exclusion Strategy**
- Leverage existing `uncuratedMakes` and `uncuratedPairs` detection
- When `limitToCuratedYears = true`: Skip adding uncurated-only items to `results` array
- No database query changes needed - just filter the results

**Decision 3: Hierarchical Filtering Approach**
- Add new method: `getAvailableModels(forMakes: Set<String>)` to `FilterCacheManager`
- Filter `cachedModels` by comparing `make_id` against selected makes
- Falls back to all models when no makes selected or hierarchy disabled

---

## 3. Key Architectural Patterns

### Pattern 1: Badge System for Uncurated Items
**Current Implementation** (`FilterCacheManager.swift:320-325`, `376-381`):
```swift
// For Makes
if let uncuratedCount = uncuratedMakes[key] {
    displayName += " [uncurated: \(formattedCount) records]"
    print("   🔴 Uncurated Make: \(makeName)")
}

// For Models
if let uncuratedCount = uncuratedPairs[key] {
    displayName += " [uncurated: \(formattedCount) records]"
    print("   🔴 Uncurated: \(modelName) (\(makeName))")
}
```

**Pattern**: Items detected as uncurated get visual badges; this dictionary lookup is our filter key.

### Pattern 2: Year Configuration Access
**Location**: `RegularizationManager.swift:72-84`
```swift
func getYearConfiguration() -> RegularizationYearConfiguration {
    return yearConfig  // Contains curatedYears and uncuratedYears sets
}
```

### Pattern 3: Filter Cache Initialization
**Current**: `FilterCacheManager.initializeCache()` - Takes no parameters
**Planned**: Pass `limitToCuratedYears` parameter to control filtering behavior

---

## 4. Active Files & Locations

### Primary Implementation Files
| File | Purpose | Lines of Interest |
|------|---------|------------------|
| `SAAQAnalyzer/Models/DataModels.swift` | Configuration properties | 1131-1132 (new properties) |
| `SAAQAnalyzer/DataLayer/FilterCacheManager.swift` | Filter dropdown population | 289-336 (Makes), 338-392 (Models) |
| `SAAQAnalyzer/DataLayer/RegularizationManager.swift` | Year configuration access | 72-84 (`getYearConfiguration()`) |
| `SAAQAnalyzer/DataLayer/OptimizedQueryManager.swift` | Query execution | 100-104 (year filter building) |
| `SAAQAnalyzer/UI/FilterPanel.swift` | UI controls (not yet accessed) | TBD (regularization settings pane) |

### Supporting Files
| File | Purpose |
|------|---------|
| `SAAQAnalyzer/DataLayer/DatabaseManager.swift` | Database operations |
| `SAAQAnalyzer/Models/DataModels.swift` | `RegularizationYearConfiguration` struct (lines 736-810) |

---

## 5. Current State: Where We Are

### ✅ Completed
1. Added `limitToCuratedYears` and `hierarchicalMakeModel` properties to `FilterConfiguration`
2. Analyzed existing badge system and uncurated item detection
3. Verified app builds and runs with no regressions
4. Confirmed no database changes needed

### 🚧 In Progress (Not Started)
**Task**: Implement curated-years-only filtering in `FilterCacheManager`

**Specific Changes Needed**:
1. Add `limitToCuratedYears` property to `FilterCacheManager` class
2. Modify `initializeCache()` signature to accept `limitToCuratedYears` parameter
3. In `loadMakes()` (line 320-325): Skip uncurated Makes when flag is true
4. In `loadModels()` (line 376-381): Skip uncurated Models when flag is true

**Example Pattern** (pseudocode):
```swift
// In loadMakes():
if let uncuratedCount = uncuratedMakes[key] {
    // Uncurated Make detected
    if limitToCuratedYears {
        continue  // Skip this Make entirely
    }
    displayName += " [uncurated: \(formattedCount) records]"
}
```

---

## 6. Next Steps (Priority Order)

### Phase 2: Implement Curated-Years-Only Filtering

#### Step 2.1: Modify FilterCacheManager
**File**: `FilterCacheManager.swift`

1. **Add property** (after line 37):
   ```swift
   // Configuration: Limit to curated years only
   var limitToCuratedYears: Bool = false
   ```

2. **Update initializeCache signature** (line 46):
   ```swift
   func initializeCache(limitToCuratedYears: Bool = false) async throws {
       guard !isInitialized else { return }
       self.limitToCuratedYears = limitToCuratedYears  // Store config
       // ... rest of initialization
   ```

3. **Modify loadMakes()** (lines 320-325):
   ```swift
   } else if let uncuratedCount = uncuratedMakes[key] {
       // Uncurated but not yet regularized
       if limitToCuratedYears {
           // Skip this Make entirely when limiting to curated years
           continue
       }
       // Otherwise show badge
       let formattedCount = NumberFormatter.localizedString(...)
       displayName += " [uncurated: \(formattedCount) records]"
   ```

4. **Modify loadModels()** (lines 376-381):
   ```swift
   } else if let uncuratedCount = uncuratedPairs[key] {
       // Uncurated but not yet regularized
       if limitToCuratedYears {
           // Skip this Model entirely when limiting to curated years
           continue
       }
       // Otherwise show badge
       let formattedCount = NumberFormatter.localizedString(...)
       displayName += " [uncurated: \(formattedCount) records]"
   ```

#### Step 2.2: Update FilterCacheManager Callers
**Find where**: `initializeCache()` is called
**Add parameter**: Pass `filters.limitToCuratedYears` to initialization

#### Step 2.3: Implement Query Year Filtering
**File**: `OptimizedQueryManager.swift` (or `DatabaseManager.swift`)

**Location**: Year filter building (line 100-104 in OptimizedQueryManager)

**Logic**: When `filters.limitToCuratedYears = true`:
```swift
if filters.limitToCuratedYears {
    // Get curated years from RegularizationManager
    let yearConfig = databaseManager?.regularizationManager?.getYearConfiguration()
    let curatedYearsList = Array(yearConfig?.curatedYears ?? [])

    // Only include curated years in query
    filters.years = filters.years.intersection(Set(curatedYearsList))
}
```

### Phase 3: Implement Hierarchical Make/Model Filtering

#### Step 3.1: Add Method to FilterCacheManager
```swift
/// Get available models filtered by selected makes
/// - Parameter forMakes: Set of Make display names (or IDs)
/// - Returns: Filtered list of models
func getAvailableModels(forMakes selectedMakes: Set<String>) async throws -> [FilterItem] {
    if !isInitialized { try await initializeCache() }

    // If hierarchy disabled or no makes selected, return all models
    guard hierarchicalMakeModel, !selectedMakes.isEmpty else {
        return cachedModels
    }

    // Convert Make display names to IDs (strip badges first)
    let makeNames = selectedMakes.map { FilterConfiguration.stripMakeBadge($0) }

    // Filter models: only include if model's make is in selectedMakes
    return cachedModels.filter { model in
        // Extract make name from "Model (Make)" format
        let pattern = /\(([^)]+)\)\s*$/
        if let match = model.displayName.firstMatch(of: pattern) {
            let makeName = String(match.1)
            return makeNames.contains(makeName)
        }
        return false
    }
}
```

#### Step 3.2: Update UI (FilterPanel.swift)
- Find where `getAvailableModels()` is called
- Pass `selectedVehicleMakes` parameter
- Models dropdown updates reactively when Make selection changes

### Phase 4: Add UI Toggles

#### Step 4.1: Locate Regularization Settings Pane
**File**: `FilterPanel.swift`
**Search for**: "Apply Regularization" or "Regularization" section

#### Step 4.2: Add Toggle Controls
```swift
Toggle("Limit Analysis to Curated Years", isOn: $filters.limitToCuratedYears)
    .help("When enabled, exclude uncurated years from filters and queries")

Toggle("Hierarchical Make/Model Filtering", isOn: $filters.hierarchicalMakeModel)
    .help("When enabled, Model dropdown shows only models for selected Make(s)")
```

### Phase 5: Testing Checklist
- [ ] Build succeeds with no errors
- [ ] Toggle "Limit to Curated Years" → uncurated badges disappear from dropdowns
- [ ] Toggle "Limit to Curated Years" → queries only include curated years
- [ ] Toggle "Hierarchical Make/Model" → Model dropdown updates when Make changes
- [ ] Both features work independently
- [ ] Both features work together
- [ ] Edge case: No makes selected → all models shown (hierarchy mode)
- [ ] Edge case: All years uncurated → appropriate handling

---

## 7. Important Context

### 7.1 No Database Changes Required
**Reason**: We're filtering existing data, not changing schema
**Benefit**: Safe to implement without migration or cache rebuilding

### 7.2 Existing Infrastructure We're Leveraging
- ✅ Uncurated item detection already implemented
- ✅ Badge system already implemented
- ✅ Year curation configuration already implemented
- ✅ Regularization system fully functional

**This is just UI/filtering work** - all the hard infrastructure is done!

### 7.3 Gotchas Discovered
1. **Make/Model display names include badges**: Use `stripMakeBadge()` and `stripModelBadge()` helper methods when comparing
2. **Model display format**: "MODEL (MAKE)" - need regex to extract make name
3. **Filter cache is singleton**: Changes apply globally until cache is invalidated

### 7.4 Related Code Patterns to Follow
**Badge stripping** (DataModels.swift:1177-1187):
```swift
static func stripMakeBadge(_ displayName: String) -> String {
    if let arrowRange = displayName.range(of: " → ") {
        return String(displayName[..<arrowRange.lowerBound])
    }
    if let bracketRange = displayName.range(of: " [") {
        return String(displayName[..<bracketRange.lowerBound])
    }
    return displayName
}
```

### 7.5 Performance Considerations
- Filter cache loads ~400 makes, ~10,000 models
- Filtering should happen in-memory (already cached)
- No performance concerns expected

---

## 8. Design Rationale

### Why Store in FilterConfiguration?
**Alternatives Considered**:
- Global app settings (rejected - too inflexible)
- DatabaseManager property (rejected - wrong layer)

**Chosen Approach**:
- Store in `FilterConfiguration` (per-query control)
- Consistent with existing patterns (`normalizeRoadWearIndex`, `showCumulativeSum`)
- Allows different chart series to use different filtering modes

### Why Not Modify Database Queries?
**For Curated Years**:
- Filter cache already identifies uncurated items
- Just skip adding them to results array
- Cleaner than modifying SQL queries

**For Hierarchical Filtering**:
- All models already cached
- Simple in-memory filter by `make_id`
- Reactive updates via SwiftUI bindings

---

## 9. Testing Commands

### Build and Run
```bash
cd /Users/rhoge/Desktop/SAAQAnalyzer
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -configuration Debug build
```

### Quick Test Plan
1. Open app in Xcode
2. Navigate to Regularization settings
3. Enable "Limit to Curated Years"
4. Verify filter dropdowns no longer show uncurated badges
5. Run a query → verify only curated years included
6. Enable "Hierarchical Make/Model"
7. Select a Make → verify Model dropdown updates
8. Disable both → verify return to original behavior

---

## 10. Session Statistics

- **Duration**: ~90 minutes
- **Token Usage**: 140k/200k (70%)
- **Files Modified**: 1 (`DataModels.swift`)
- **Lines Added**: 2
- **Build Status**: ✅ Success
- **Tests**: N/A (foundation phase)

---

## 11. Questions for Next Session

1. **Where in FilterPanel.swift is the regularization settings pane?**
   - Need to locate to add UI toggles

2. **Should hierarchical filtering persist Make selection?**
   - If user clears all Makes, return to all models or keep empty?
   - Recommendation: Return to all models (better UX)

3. **Should we add logging?**
   - Consider adding `AppLogger.cache.info()` for filter mode changes
   - Consistent with existing logging patterns

---

## 12. Continuation Guide for Next Claude

**To Continue This Work**:

1. **Start with Phase 2**: Implement curated-years-only filtering
   - Focus on `FilterCacheManager.swift` lines 320-325 and 376-381
   - Add `continue` statements to skip uncurated items

2. **Key Files to Edit**:
   - `FilterCacheManager.swift` (main implementation)
   - Find where `initializeCache()` is called (pass config parameter)
   - `OptimizedQueryManager.swift` (query year restriction)

3. **Testing Strategy**:
   - Build after each phase
   - Test toggles independently before combined testing
   - Verify no regressions (badges should still work when toggles OFF)

4. **If Stuck**:
   - Review existing badge system implementation (it's the pattern to follow)
   - Check `RegularizationManager.getYearConfiguration()` for year access
   - Look at `uncuratedMakes` and `uncuratedPairs` dictionaries - they're the filter keys

**Estimated Work Remaining**: 2-3 hours (Phases 2-4)

---

**End of Handoff Document**
