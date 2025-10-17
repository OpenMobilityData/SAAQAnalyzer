# SAAQAnalyzer - Outstanding Issues & Future Enhancements

**Date**: October 17, 2025
**Status**: Comprehensive roadmap for continued development
**Priority Classification**: Critical (3) | Important (5) | Nice to Have (12)

---

## 🔴 **High Priority - Known Issues**

### 1. License Data Import - Needs End-to-End Testing
**Status**: Implementation complete but untested
**Location**: `CSVImporter.swift`, `DatabaseManager.swift:4943-5250`
**Issue**: License import was broken after September 2024 integer enumeration migration and has been reimplemented but never successfully tested end-to-end.

**Tasks**:
- Restore vehicle data from backup package
- Test single license file import (2022, ~1000 records)
- Verify enum table population (age_group_enum, gender_enum, license_type_enum)
- Verify FilterPanel displays license dropdowns correctly
- Test batch import of all 12 license files (2011-2022)
- Performance validation: Should complete < 10 seconds per file

**Reference**: `Notes/2025-10-15-License-Import-Final-Status-and-Remaining-Work.md`

---

### 2. Transaction Rollback Support for Import Cancellation
**Status**: Deferred enhancement
**Current Behavior**: Cancelling import accepts partial data in database
**Desired Behavior**: Rollback incomplete file imports on cancellation

**Implementation**:
- Add `DatabaseManager.beginTransaction()` / `.rollback()` methods
- Wrap each file import in BEGIN/COMMIT transaction
- On CancellationError, call ROLLBACK for current file
- Keep successful files from batch

**Complexity**: Medium
**Impact**: High (prevents partial year data)

**Reference**: `Notes/2025-10-17-Import-Task-Cancellation-Implementation.md:93-97`

---

### 3. Data Package Import Status Unclear
**Status**: Needs investigation
**Observation**: Import appeared to show "not yet implemented" message during testing
**Export Status**: ✅ Confirmed working
**Validation Status**: ✅ Working

**Investigation Needed**:
- Check if `importDataPackage()` method is complete
- Look for placeholder/TODO error messages
- Test full import workflow with real package
- May need implementation from scratch if deferred

**Files**: `DataPackageManager.swift:149-214`

**Reference**: `Notes/2025-10-15-License-Import-Final-Status-and-Remaining-Work.md:405-422`

---

## 🟡 **Medium Priority - Enhancements**

### 4. Make/Model Regularization Scripts - Production Ready
**Status**: Multiple experimental approaches, none production-ready
**Problem**: 2023-2024 data contains typos (VOLV0), truncations (CX3 vs CX-3), mixed with genuine new models
**Scripts**: 6 different approaches documented

**Current State**:
- ✅ `NormalizeCSV.swift` - Production ready (structural fixes)
- 🚧 `AIRegularizeMakeModel.swift` - Most advanced, needs refinement
- 🚧 `RegularizeMakeModel.swift` - Alternative approach (37K, needs documentation)

**Next Steps**:
- Refine AI prompt to eliminate contradictory responses
- Use model years instead of registration years for temporal validation
- Hybrid approach: deterministic rules + AI for ambiguous cases
- Manual review workflow before applying corrections

**Reference**: `Scripts/SCRIPTS_DOCUMENTATION.md`

---

### 5. macOS Tahoe 26 Optimization Opportunities
**Status**: Opportunity analysis
**Platform**: macOS 26 brings significant SwiftUI improvements

**Opportunities**:
- **SwiftUI List Performance**: 6x-16x faster rendering (benefits DataInspectorView)
- **3D Charts**: New Charts framework capabilities for volumetric data
- **On-Device AI**: Could enhance Make/Model regularization
- **Liquid Glass UI**: Modern aesthetic updates

**Tasks**:
- Quantify list performance improvements in DataInspector
- Explore 3D chart use cases (geographic + temporal + metric visualization)
- Consider increasing default result set limits with faster rendering
- Test existing functionality on Tahoe

**Reference**: `Documentation/macOS-Tahoe-26-Analysis.md`

---

### 6. Automated Testing Infrastructure
**Status**: Basic structure exists, minimal coverage
**Location**: `SAAQAnalyzerTests/`
**Framework**: XCTest

**Testing Gaps**:
- No unit tests for CSVImporter cancellation logic
- No integration tests for database imports
- No UI tests for filter panel interactions
- No performance regression tests

**Suggested Tests**:
- CSV import cancellation (mock importer, verify throws CancellationError)
- Enum table population during import
- Cache invalidation/refresh logic
- Filter configuration persistence
- Query performance benchmarks

---

### 7. AppKit Dependency Reduction
**Status**: Documented analysis available
**Current Usage**: NSOpenPanel, NSSavePanel, NSAlert for file operations
**Goal**: Prefer SwiftUI and Swift-native APIs

**Analysis Done**: `Documentation/AppKit-Dependency-Analysis.md`

**Recommendations**:
- Keep NSOpenPanel/NSSavePanel (no SwiftUI equivalents for multi-file selection)
- Consider replacing NSAlert with SwiftUI .alert() where possible
- Document remaining AppKit dependencies as necessary

**Priority**: Low (framework preferences, not functionality issues)

---

### 8. FilterCacheManager NULL Safety Improvement
**Status**: Known edge case, low risk
**Location**: `FilterCacheManager.swift:591`
**Issue**: Force-unwraps `sqlite3_column_text()` result without NULL check

**Current Behavior**:
- Never crashes for vehicle imports (enum tables always have data)
- Only crashes when enum tables completely empty (failed license import scenario)

**Fix**:
```swift
// Current (unsafe)
let text = String(cString: sqlite3_column_text(stmt, 1))

// Proposed (safe)
guard let cString = sqlite3_column_text(stmt, 1) else {
    continue // Skip NULL entries
}
let text = String(cString: cString)
```

**Priority**: Low (only affects empty database edge case)

**Reference**: `Notes/2025-10-15-License-Import-Final-Status-and-Remaining-Work.md:423-430`

---

## 🟢 **Low Priority - Nice to Have**

### 9. License Enum Table Indexes
**Status**: Optimization opportunity
**Current**: Only PRIMARY KEY indexes exist
**Scope**: < 150 total entries across all license enum tables

**Recommendation**:
- Add after license import works
- Measure if performance improvement is measurable
- Likely unnecessary given small data size

---

### 10. Enhanced Chart Export Options
**Status**: Basic export exists
**Current Settings**:
- Background brightness (0-100%)
- Line thickness (1-12pt)
- Export scale (1-4x)
- Bold axis labels toggle
- Include legend toggle

**Potential Enhancements**:
- Custom resolution presets (presentation, publication, web)
- Multiple format support (PDF, PNG, SVG)
- Batch export all series at once
- Chart template library

---

### 11. Query Performance Monitoring Dashboard
**Status**: Console logging exists, no UI
**Current**: `SeriesQueryProgressView` shows real-time status
**Enhancement**: Historical performance tracking

**Features**:
- Query execution time trends
- Index usage statistics
- Slowest queries report
- Performance degradation alerts

**Use Case**: Detect when database maintenance (ANALYZE) is needed

---

### 12. Advanced Filtering - Saved Filter Presets
**Status**: Not implemented
**Current**: FilterConfiguration persists in UI state only

**Feature**:
- Save commonly used filter combinations
- Quick access to "Montreal Electric Vehicles", "Quebec Trucks 2020-2024", etc.
- Import/export filter presets
- Share presets between users

---

### 13. Data Quality Dashboard
**Status**: Coverage metric exists, no dedicated UI
**Current**: Can analyze NULL values via Coverage metric

**Enhancement**:
- Dedicated data quality view
- Year-by-year completeness heatmap
- Field-level quality scores
- Import audit log viewer

---

### 14. Regularization Management UI Improvements
**Status**: Functional but could be enhanced
**Current**: Settings → Regularization tab manages mappings

**Potential Improvements**:
- Batch approve/reject UI for AI-generated suggestions
- Confidence score indicators
- Undo/redo support
- Export regularization mappings for peer review

---

### 15. Geographic Data Enhancements
**Status**: Basic hierarchy exists (Region → MRC → Municipality)

**Potential Additions**:
- Map visualization integration
- Population data for per-capita analysis
- Economic indicators (GDP, employment)
- Climate zones for analysis correlation

---

### 16. Time Series Forecasting
**Status**: Historical data only
**Current**: Charts show 2011-2024 data

**Enhancement**:
- Trend projection based on historical patterns
- Growth rate indicators
- Anomaly detection (unusual year-over-year changes)

**Use Case**: Policy impact projection, infrastructure planning

---

### 17. Internationalization (i18n)
**Status**: English only, French data labels
**Current**: UI in English, data contains French placenames

**Tasks**:
- Localize UI strings to French
- Bilingual data labels (English/French toggle)
- Currency/number formatting for Quebec locale

**Priority**: Low unless broader adoption planned

---

### 18. Performance Profiling & Optimization
**Status**: Ad-hoc optimization done

**Systematic Approach**:
- Instruments.app profiling sessions
- Memory usage analysis
- SQLite query plan optimization
- SwiftUI view rendering profiling

**Known Fast Paths**:
- Integer enumeration (5.6x improvement documented)
- 32KB page size (2-4x improvement)
- Canonical hierarchy cache (109x improvement)

**Potential Gains**: Unknown without systematic profiling

---

### 19. Legacy Code Cleanup Decision
**Status**: Deferred from October 2025
**Location**: Legacy query paths still exist alongside optimized paths

**Options**:
1. **Remove**: Delete legacy string-based queries (cleaner codebase)
2. **Keep**: Maintain for fallback/migration scenarios

**Consideration**: Migration code may be useful for future schema changes

**Reference**: `Notes/2025-10-16-Package-Export-Import-Fixes-Complete.md`

---

### 20. Documentation Improvements
**Status**: Well-documented codebase, room for enhancement

**Gaps**:
- No user manual
- No video tutorials
- Limited API documentation
- Regularization workflow needs detailed guide

**Priority**: Depends on intended audience (personal tool vs public release)

---

## 📊 **Metrics & Success Criteria**

### Import Performance (Current Targets)
- Vehicle CSV: < 2 minutes per 7M records
- License CSV: < 10 seconds per 5K records
- Batch import: < 30 minutes for full dataset

### Query Performance (Current Targets)
- Simple filter: < 1 second
- Complex multi-filter: < 5 seconds
- Percentage metric: < 10 seconds
- RWI calculation: < 15 seconds

### Data Quality
- Make/Model coverage: > 90% for curated years (2011-2022)
- Geographic completeness: 100% (all Quebec regions/MRCs)
- Fuel type coverage: > 95% for 2017+ (field didn't exist pre-2017)

---

## 🎯 **Recommended Next Steps** (Priority Order)

1. **Test License Import End-to-End** (Highest priority - core functionality)
2. **Implement Transaction Rollback for Import Cancellation** (Quality of life)
3. **Investigate Data Package Import Status** (May be blocking restoration workflow)
4. **Finalize Make/Model Regularization Approach** (Research completion)
5. **Add NULL Safety to FilterCacheManager** (Quick win, prevents edge case crash)

---

## 📈 **Summary Statistics**

**Total Outstanding Items**: 20
**Critical (🔴)**: 3
**Important (🟡)**: 5
**Nice to Have (🟢)**: 12

---

## 🔗 **Related Documentation**

- `CLAUDE.md` - Project architecture and development guidelines
- `Notes/2025-10-15-License-Import-Final-Status-and-Remaining-Work.md` - License import implementation details
- `Notes/2025-10-17-Import-Task-Cancellation-Implementation.md` - Task cancellation implementation
- `Scripts/SCRIPTS_DOCUMENTATION.md` - Make/Model regularization research
- `Documentation/macOS-Tahoe-26-Analysis.md` - Platform upgrade opportunities
- `Documentation/AppKit-Dependency-Analysis.md` - Framework dependency analysis

---

**Document Status**: Comprehensive roadmap for continued development
**Next Review**: After completing high-priority items (license import testing, transaction rollback)
