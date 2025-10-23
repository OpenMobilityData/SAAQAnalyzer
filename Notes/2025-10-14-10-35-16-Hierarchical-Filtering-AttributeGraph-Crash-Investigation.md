# Hierarchical Make/Model Filtering - AttributeGraph Crash Investigation

**Date**: October 14, 2025
**Session Status**: ⚠️ BLOCKED - Critical Bug Preventing Feature Completion
**Token Usage**: 123k/200k (61.5%) - Session ending due to complexity
**Issue**: AttributeGraph precondition failure causing app hang/crash

---

## Executive Summary

The hierarchical Make/Model filtering feature has been **implemented but is blocked by a critical SwiftUI AttributeGraph crash**. The feature works correctly for adding selections, but crashes when **deselecting a Make** while hierarchical filtering is enabled. Multiple attempted fixes (value comparison guards, re-entrance guards, debouncing, dedicated reload methods) have not resolved the issue.

**Root Cause**: SwiftUI's AttributeGraph detects a circular dependency when `configuration.vehicleMakes` changes trigger model reloads, which somehow causes the view dependency graph to re-evaluate in a way that exceeds AttributeGraph's data space limits.

---

## Current Implementation Status

### ✅ Completed Components

1. **FilterCacheManager.swift** - Lines 40, 388, 466-497, 533-540, 608
   - `modelToMakeMapping: [Int: Int]` dictionary populated during cache load
   - `getAvailableModels(limitToCuratedYears:forMakeIds:)` enhanced with optional filtering
   - `filterModelsByMakes(_:makeIds:)` helper method for O(1) filtering
   - Cache invalidation clears mapping

2. **FilterPanel.swift** - Multiple locations
   - `reloadModelsForHierarchicalFiltering()` dedicated method (lines 411-439)
   - onChange handler for `hierarchicalMakeModel` toggle (lines 321-327)
   - onChange handler for `vehicleMakes` with debouncing (lines 332-353)
   - Hierarchical filtering logic in `loadDataTypeSpecificOptions()` (lines 463-477)

3. **DataModels.swift**
   - `hierarchicalMakeModel: Bool` property in FilterConfiguration (line 1132)

### ❌ Blocking Issue

**Symptom**: App hangs with beachball, then crashes with:
```
🔄 Make selection changed, reloading models for hierarchical filtering
🔄 Make selection changed, reloading models for hierarchical filtering
AttributeGraph precondition failure: exhausted data space.
precondition failure: exhausted data space
```

**Reproducible Steps**:
1. Turn on "Hierarchical Make/Model Filtering" toggle
2. Select a Make (e.g., MAZDA) ✅ Works fine
3. Select a Model (correctly filtered) ✅ Works fine
4. **Deselect the Make** ❌ **CRASH**

**Key Finding**: The crash is triggered by **deselecting the Make**, NOT by:
- Clearing search text (earlier hypothesis, incorrect)
- Selecting makes or models
- Toggling hierarchical filtering on/off

---

## Technical Analysis

### Attempted Fixes (All Failed)

#### 1. Value Comparison Guard (First Attempt)
```swift
.onChange(of: configuration.vehicleMakes) { oldValue, newValue in
    if configuration.hierarchicalMakeModel && oldValue != newValue {
        // ...
    }
}
```
**Result**: Still crashes intermittently

#### 2. Re-Entrance Guard (Second Attempt)
```swift
@State private var isReloadingModels = false

.onChange(of: configuration.vehicleMakes) { oldValue, newValue in
    guard !isReloadingModels else { return }
    isReloadingModels = true
    Task {
        await loadDataTypeSpecificOptions()
        isReloadingModels = false
    }
}
```
**Result**: Still crashes

#### 3. Dedicated Reload Method (Third Attempt)
Created `reloadModelsForHierarchicalFiltering()` to only update models, not all data:
```swift
private func reloadModelsForHierarchicalFiltering() async {
    // Only updates availableVehicleModels, nothing else
}
```
**Result**: Still crashes

#### 4. Debounced Task Cancellation (Fourth Attempt - Current)
```swift
@State private var hierarchicalFilterTask: Task<Void, Never>?

.onChange(of: configuration.vehicleMakes) { oldValue, newValue in
    hierarchicalFilterTask?.cancel()
    hierarchicalFilterTask = Task {
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
        guard !Task.isCancelled else { return }
        await reloadModelsForHierarchicalFiltering()
    }
}
```
**Result**: **Still crashes** - The duplicate console message suggests the onChange fires twice despite debouncing

### Why Current Approaches Failed

The AttributeGraph crash indicates SwiftUI's internal dependency tracking system is detecting a **circular dependency** at a level deeper than our Task-based guards can prevent:

1. `configuration.vehicleMakes` changes (user deselects)
2. onChange fires → starts Task to reload models
3. SwiftUI re-evaluates view body (because binding changed)
4. View body reads `availableVehicleMakes` (as input to `SearchableFilterList`)
5. Something in this evaluation cycle causes AttributeGraph to detect recursion
6. **The fact that we see TWO identical console messages suggests the onChange is firing twice, possibly due to SwiftUI's two-pass layout system**

---

## Architecture Context

### FilterCacheManager Integration

**Database Schema**:
```sql
CREATE TABLE model_enum (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    make_id INTEGER NOT NULL,  -- Foreign key to make_enum
    FOREIGN KEY (make_id) REFERENCES make_enum(id)
);
```

**Mapping Dictionary**:
- Populated once during `loadModels()`
- `modelToMakeMapping[modelId] = makeId`
- O(1) lookup for filtering
- ~80KB memory (10k models × 8 bytes)

**Filter Flow**:
```
User selects Make(s)
    ↓
Extract display names from FilterConfiguration
    ↓
Match against loaded FilterItems to get make IDs
    ↓
Pass IDs to getAvailableModels(forMakeIds:)
    ↓
Filter models using modelToMakeMapping
    ↓
Update availableVehicleModels @State
    ↓
SearchableFilterList re-renders with filtered list
```

### Current File States

**Modified Files**:
- `FilterCacheManager.swift` - ✅ Complete, working correctly
- `FilterPanel.swift` - ⚠️ onChange handler causing crash
- `DataModels.swift` - ✅ Complete (property only)

**Uncommitted Changes**:
```bash
M SAAQAnalyzer/DataLayer/FilterCacheManager.swift
M SAAQAnalyzer/UI/FilterPanel.swift
```

---

## Proposed Solutions (Not Yet Attempted)

### Option A: Move to Computed Property (Recommended)

**Concept**: Instead of using onChange to reload models, make the model list a **computed property** that automatically filters based on current state.

```swift
// In FilterPanel
private var filteredModelsForDisplay: [String] {
    guard configuration.hierarchicalMakeModel else {
        return availableVehicleModels
    }

    // Filter availableVehicleModels in-place based on configuration.vehicleMakes
    // This would require caching FilterItems instead of display names
}
```

**Pros**:
- No onChange handlers → no circular dependency risk
- SwiftUI handles dependency tracking automatically
- Declarative approach matches SwiftUI paradigm

**Cons**:
- Requires refactoring to store FilterItems instead of [String]
- Filtering happens on every view render (but O(n) is acceptable)

**Implementation Steps**:
1. Change `availableVehicleModels` from `[String]` to `[FilterItem]`
2. Create computed property `filteredVehicleModelsForDisplay: [FilterItem]`
3. Remove onChange handler entirely
4. Update VehicleFilterSection to use computed property

### Option B: Use @StateObject ViewModel

**Concept**: Extract hierarchical filtering logic into a dedicated ObservableObject.

```swift
@MainActor
class HierarchicalFilterViewModel: ObservableObject {
    @Published var filteredModels: [FilterItem] = []

    func updateFilters(makes: Set<String>, allModels: [FilterItem], enabled: Bool) {
        // Handle filtering with proper Combine debouncing
    }
}
```

**Pros**:
- Isolates problematic logic from SwiftUI view
- Can use Combine's `.debounce()` operator properly
- Clearer separation of concerns

**Cons**:
- More complex architecture
- Requires significant refactoring

### Option C: Defer Updates with DispatchQueue

**Concept**: Use DispatchQueue.main.async to defer the update to the next run loop.

```swift
.onChange(of: configuration.vehicleMakes) { oldValue, newValue in
    guard configuration.hierarchicalMakeModel && oldValue != newValue else { return }

    DispatchQueue.main.async {
        Task {
            await reloadModelsForHierarchicalFiltering()
        }
    }
}
```

**Pros**:
- Simple one-line change
- Breaks immediate execution cycle

**Cons**:
- Uses legacy GCD instead of modern Swift concurrency
- May not solve deep AttributeGraph issue

### Option D: Feature Flag with Warning

**Concept**: Disable hierarchical filtering by default with a warning until the bug is resolved.

```swift
// In FilterOptionsSection
VStack {
    Toggle(isOn: $hierarchicalMakeModel) { /* ... */ }

    if hierarchicalMakeModel {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Known issue: May crash when deselecting Makes. Feature under investigation.")
                .font(.caption2)
        }
    }
}
```

**Pros**:
- Allows feature to be tested/used with caution
- Transparent about limitations

**Cons**:
- Not a real solution
- Poor user experience

---

## Debugging Information

### Console Output Pattern
```
🔄 Make selection changed, reloading models for hierarchical filtering
🔄 Make selection changed, reloading models for hierarchical filtering
AttributeGraph precondition failure: exhausted data space.
```

**Key Observation**: The message appears **twice**, suggesting:
1. onChange fires twice for a single deselection
2. OR SwiftUI's two-pass layout triggers it twice
3. OR the debounce isn't actually preventing the second call

### Kernel Message
```
Unable to obtain a task name port right for pid 485: (os/kern) failure (0x5)
```
**Analysis**: Likely unrelated to our issue - this is a macOS security/sandboxing message that commonly appears. Not the root cause.

### AttributeGraph Crash Pattern
This error occurs when:
- View dependencies form a cycle
- A computed property triggers its own re-computation
- State updates during view evaluation cause re-evaluation
- SwiftUI's internal graph exceeds memory limits (unlikely but possible)

---

## Related Code Locations

### FilterPanel.swift
- **Lines 49-51**: State properties (isReloadingModels, hierarchicalFilterTask)
- **Lines 321-353**: onChange handlers for hierarchicalMakeModel and vehicleMakes
- **Lines 411-439**: reloadModelsForHierarchicalFiltering() method
- **Lines 463-477**: Hierarchical filtering logic in loadDataTypeSpecificOptions()

### FilterCacheManager.swift
- **Line 40**: modelToMakeMapping property
- **Line 388**: Mapping population during loadModels()
- **Lines 466-497**: getAvailableModels() with forMakeIds parameter
- **Lines 533-540**: filterModelsByMakes() helper
- **Line 608**: Cache invalidation

### DataModels.swift
- **Line 1132**: hierarchicalMakeModel property definition

---

## Next Session Action Items

### Immediate Priority (Required to Unblock)

1. **Try Option A (Computed Property Approach)** ⭐ RECOMMENDED
   - Most aligned with SwiftUI's declarative paradigm
   - Eliminates onChange handler entirely
   - Steps:
     - Change `@State private var availableVehicleModels: [String]` to `[FilterItem]`
     - Create `private var filteredVehicleModels: [FilterItem]` computed property
     - Update VehicleFilterSection to accept `[FilterItem]` and convert internally
     - Remove onChange handler for vehicleMakes

2. **If Option A Fails, Try Option C (DispatchQueue.main.async)**
   - Simplest code change
   - May break the immediate execution cycle

3. **If Both Fail, Investigate SwiftUI Internals**
   - Use Xcode's "Debug View Hierarchy" to inspect AttributeGraph
   - Add breakpoint in onChange to see call stack
   - Check if VehicleFilterSection is being recreated unnecessarily

### Testing Checklist (Once Fixed)

- [ ] Turn on hierarchical filtering
- [ ] Select one Make → verify models filter
- [ ] Select multiple Makes → verify models show union
- [ ] **Deselect a Make → verify no crash** ⭐ Critical test
- [ ] Deselect all Makes → verify all models shown
- [ ] Toggle hierarchical filtering off → verify all models shown
- [ ] Search for make → verify filtering works
- [ ] Clear search text → verify no crash

### Documentation Updates (After Fix)

1. Update CLAUDE.md with hierarchical filtering feature description
2. Add note about AttributeGraph crash resolution to session handoff
3. Document the successful approach for future reference

---

## Key Insights for Next Developer

1. **The crash is specifically triggered by deselection**, not selection or search operations
2. **Standard async/await guards are insufficient** - the issue is at SwiftUI's AttributeGraph level
3. **The onChange handler fires twice** for a single change, suggesting deeper SwiftUI behavior
4. **All Task-based solutions failed** - need to move away from onChange pattern entirely
5. **FilterCacheManager implementation is solid** - no changes needed on data layer side

---

## Related Sessions

- **2025-10-13-Filter-UX-Enhancements-Phase2-Complete.md** - Added hierarchical toggle UI
- **2025-10-14-UI-Enhancements-and-Settings-Integration-Session-Handoff.md** - Added Filter Options section

---

## Technical References

### SwiftUI AttributeGraph
- Private framework used by SwiftUI for dependency tracking
- Maintains DAG (Directed Acyclic Graph) of view dependencies
- "Exhausted data space" = graph exceeded internal limits or detected cycle
- No official Apple documentation (private API)

### Relevant Swift Concurrency Patterns
- Task cancellation: `task?.cancel()` + `Task.isCancelled`
- Debouncing: `Task.sleep(nanoseconds:)`
- MainActor isolation: `@MainActor.run { }`

### SwiftUI onChange Behavior
- Fires when binding value changes
- May fire multiple times during single update cycle
- Two-pass layout system can trigger multiple evaluations
- State changes during onChange can cause re-evaluation

---

**End of Handoff Document**

**Status**: ⚠️ Feature 99% complete but blocked by critical crash bug
**Recommended Next Step**: Implement Option A (Computed Property approach)
**Estimated Time to Resolve**: 30-60 minutes if Option A works
**Fallback**: May need Apple DTS assistance if AttributeGraph issue is unfixable in current architecture
