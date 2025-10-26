# Test Coverage Analysis - SAAQAnalyzer

**Generated**: 2025-10-26, 07:53:31
**Status**: Comprehensive Analysis
**Purpose**: Map current test coverage and identify gaps for strategic improvement

---

## Executive Summary

**Total Test Files**: 9 files (7 unit/integration, 2 UI tests)
**Total Test Methods**: ~120+ test methods
**Coverage Level**: **Moderate** (~40-50% estimated)
**Critical Gaps**: RegularizationManager, FilterCacheManager, UI components

### Coverage By Risk Level

| Risk Level | Component | Coverage | Status |
|------------|-----------|----------|--------|
| 🔴 CRITICAL | QueryManager | ✅ 85% | **EXCELLENT** |
| 🔴 CRITICAL | CategoricalEnumManager Indexes | ✅ 90% | **EXCELLENT** |
| 🟡 HIGH | DatabaseManager | ✅ 70% | **GOOD** |
| 🟡 HIGH | CSVImporter | ✅ 75% | **GOOD** |
| 🟡 HIGH | FilterCache | ✅ 80% | **GOOD** |
| 🔴 CRITICAL | RegularizationManager | ⚠️ 0% | **MISSING** |
| 🔴 CRITICAL | FilterCacheManager | ⚠️ 0% | **MISSING** |
| 🟡 HIGH | GeographicDataImporter | ⚠️ 0% | **MISSING** |
| 🟢 MEDIUM | UI Components | ⚠️ 5% | **MINIMAL** |
| 🟢 MEDIUM | RWI Configuration | ⚠️ 0% | **MISSING** |

---

## Current Test Suite Structure

### 1. Unit Tests (SAAQAnalyzerTests/)

#### ✅ SAAQAnalyzerTests.swift (Basic Smoke Tests)
- **Purpose**: Entry point validation
- **Coverage**: 6 test methods
- **Scope**:
  - Application initialization
  - Data model enum validation
  - FilterConfiguration basics
  - AppSettings processor detection
- **Status**: ✅ Complete for basic sanity checks

#### ✅ QueryManagerTests.swift (Tier 1 Critical)
- **Purpose**: Comprehensive query logic validation
- **Coverage**: 80+ test methods
- **Scope**:
  - ✅ Filter conversion (string → integer IDs)
  - ✅ RWI calculations (all axle configurations)
  - ✅ Normalization transforms
  - ✅ Cumulative sum transforms
  - ✅ Regularization expansion logic
  - ✅ Query building for all metric types
  - ✅ License query special cases
  - ✅ Performance validation
  - ✅ Edge cases (NULL handling, large filters, special characters)
- **Status**: ✅ **EXCELLENT** - Most comprehensive test suite
- **Historical Context**: Created January 2025 to address 0% coverage on highest-risk component

#### ✅ DatabaseManagerTests.swift
- **Purpose**: Database operations and cache integration
- **Coverage**: 18 test methods
- **Scope**:
  - ✅ Database connection and table existence
  - ✅ Vehicle vs license data separation
  - ✅ Geographic hierarchy (regions, MRCs, municipalities)
  - ✅ Cache refresh triggers
  - ✅ Concurrent cache refresh handling
  - ✅ Query performance benchmarks
  - ✅ Database statistics
- **Status**: ✅ Good coverage of core operations
- **Gaps**:
  - ⚠️ Complex query scenarios (coverage, percentage modes)
  - ⚠️ Normalize to first year transform
  - ⚠️ Cumulative sum application
  - ⚠️ RWI-specific queries

#### ✅ CSVImporterTests.swift
- **Purpose**: Data import validation
- **Coverage**: 15 test methods
- **Scope**:
  - ✅ Vehicle CSV import
  - ✅ License CSV import
  - ✅ French character encoding (Montréal, Québec, etc.)
  - ✅ Encoding corruption fixes (Ã© → é)
  - ✅ Data validation (valid vs malformed)
  - ✅ Error handling (empty, malformed, header-only CSV)
  - ✅ Large file performance (500-1000 records)
  - ✅ Memory usage validation
  - ✅ Quebec-specific data patterns
- **Status**: ✅ Excellent coverage of import pipeline
- **Gaps**:
  - ⚠️ Duplicate detection (relies on database constraints)
  - ⚠️ Batch processing behavior

#### ✅ FilterCacheTests.swift
- **Purpose**: UserDefaults-based cache validation
- **Coverage**: 12 test methods
- **Scope**:
  - ✅ Vehicle vs license cache separation
  - ✅ Cache key correctness (prevents Oct 2025 regression)
  - ✅ Cache state management (hasCachedData flags)
  - ✅ Data version tracking and migration
  - ✅ Full vs selective cache clearing
  - ✅ Performance with realistic data sizes
- **Status**: ✅ Good coverage of UserDefaults persistence
- **Note**: Different from FilterCacheManager (in-memory hierarchical cache)

#### ✅ CategoricalEnumManagerTests.swift (Performance-Critical)
- **Purpose**: Enumeration table schema and index validation
- **Coverage**: 10 test methods (3 categories)
- **Scope**:
  - ✅ All 16 enumeration table creation
  - ✅ Table structure validation (columns, types, constraints)
  - ✅ **CRITICAL**: All 9 performance indexes (16x speedup)
  - ✅ Index idempotency (IF NOT EXISTS)
  - ✅ Foreign key relationships (model_enum → make_enum)
- **Status**: ✅ Excellent schema validation
- **Historical Context**: Oct 11, 2025 - Missing indexes caused 165s → 10s regression
- **Gaps**:
  - ⚠️ Enum population tests removed (vestigial migration code)
  - ⚠️ Enum lookup operations (ID ↔ string conversion)
  - 📝 Future: Create test database with CSV imports, add population tests

#### ✅ WorkflowIntegrationTests.swift
- **Purpose**: End-to-end workflow validation
- **Coverage**: 5 integration test methods
- **Scope**:
  - ✅ Complete vehicle workflow (import → cache → filter → query)
  - ✅ Complete license workflow
  - ✅ Mode switching (vehicle ↔ license)
  - ✅ Cache consistency across operations
  - ✅ Data quality with edge cases (empty fields)
  - ✅ Workflow performance (100 records)
- **Status**: ✅ Good end-to-end validation
- **Gaps**:
  - ⚠️ Regularization workflow integration
  - ⚠️ Data-type-aware UX features (Oct 2025)
  - ⚠️ Multi-year import scenarios

### 2. UI Tests (SAAQAnalyzerUITests/)

#### ⚠️ SAAQAnalyzerUITests.swift
- **Coverage**: Minimal (launch test only)
- **Status**: ⚠️ Placeholder - needs expansion

#### ⚠️ SAAQAnalyzerUITestsLaunchTests.swift
- **Coverage**: Minimal (screenshot capture)
- **Status**: ⚠️ Placeholder - needs expansion

---

## Critical Testing Gaps

### 🔴 Tier 1 - CRITICAL (No Coverage)

#### 1. RegularizationManager (0% coverage)
**Risk**: HIGHEST - Core feature for data quality
**Complexity**: 600+ lines
**Impact**: Merges uncurated Make/Model/Fuel/VehicleType variants

**Missing Tests**:
- Canonical hierarchy generation (caching, performance)
- Make/Model ID expansion (bidirectional mapping)
- Fuel type triplet matching (Make/Model/Year)
- Vehicle type NULL handling
- Pre-2017 fuel type regularization toggle
- Curated years configuration
- Make/Model coupling logic
- Cache invalidation on data changes

**Recommended Test Suite**: `RegularizationManagerTests.swift`
- Hierarchy cache population (109x speedup validation)
- ID expansion correctness
- Coupling ON vs OFF behavior
- NULL handling edge cases
- Performance regression prevention

#### 2. FilterCacheManager (0% coverage)
**Risk**: HIGHEST - Different from FilterCache (UserDefaults)
**Complexity**: In-memory hierarchical cache
**Impact**: Fast Make/Model filtering, dropdown population

**Missing Tests**:
- Cache initialization from database
- Cache invalidation and refresh
- Data-type-aware loading (Oct 2025 fix)
- Curated years filtering
- Hierarchical Make→Model relationships
- Cache hit/miss performance

**Recommended Test Suite**: `FilterCacheManagerTests.swift`
- Initialization performance
- Data-type separation (vehicle vs license)
- Curated year filtering
- Cache refresh without data loss

#### 3. GeographicDataImporter (0% coverage)
**Risk**: HIGH - Data integrity for geographic hierarchy
**Complexity**: d001 file parsing
**Impact**: Region/MRC/Municipality relationships

**Missing Tests**:
- d001 file parsing (format validation)
- Geographic hierarchy insertion
- Duplicate handling
- Error handling (malformed files)
- Integration with vehicles table

**Recommended Test Suite**: `GeographicDataImporterTests.swift`

### 🟡 Tier 2 - HIGH (Partial Coverage)

#### 4. Data-Type-Aware UX Features (Oct 2025)
**Coverage**: 0% automated tests
**Implementation**: Complete (Oct 25, 2025)

**Missing Tests**:
- Filter Options visibility (vehicle-only)
- Year ranges per data type (2011-2024 vs 2011-2022)
- Year selection preservation on mode switch
- Progress badge logic (curated vs uncurated)
- Zero-value query prevention

**Recommended Test Suite**: Add to `WorkflowIntegrationTests.swift`
- Test mode switching preserves year selections
- Test badge colors for mixed curated/uncurated years
- Test year range filtering

#### 5. RWI User Configuration (Oct 2025)
**Coverage**: 0% automated tests
**Implementation**: Complete (Oct 24, 2025)

**Missing Tests**:
- Axle configuration weight distribution validation (must sum to 100%)
- Vehicle type fallback assumptions
- Auto-calculated coefficients
- Import/export configuration JSON
- UserDefaults persistence
- SQL generation from configuration

**Recommended Test Suite**: `RWIConfigurationTests.swift`
- Weight distribution validation (100% sum)
- Coefficient calculation from weights
- JSON serialization/deserialization
- Settings persistence across app launches

#### 6. Transform Logic (Partial Coverage)
**Components**: Normalize to First Year, Cumulative Sum
**Current Coverage**: Helper method tests in QueryManagerTests
**Gap**: Integration with DatabaseManager queries

**Missing Tests**:
- Transform order (normalize THEN cumulative)
- Edge cases (zero/negative first year)
- Percentage mode normalization
- Transform with RWI mode
- Legend generation with transforms

**Recommended**: Add to `DatabaseManagerTests.swift`
- Test actual query results with transforms enabled
- Test transform combinations

#### 7. Coverage & Percentage Metrics
**Coverage**: Logic documented in QueryManagerTests, not executed

**Missing Tests**:
- Coverage percentage calculation ((COUNT(field)/COUNT(*)) * 100)
- Coverage NULL count mode (COUNT(*) - COUNT(field))
- Percentage mode with baseline filtering
- Baseline vs subset queries

**Recommended**: Add to `DatabaseManagerTests.swift`

### 🟢 Tier 3 - MEDIUM (Nice to Have)

#### 8. UI Component Testing
**Current**: Launch tests only
**Gap**: No interaction or state validation

**Missing Areas**:
- FilterPanel state changes
- Chart rendering with various metrics
- Data inspector display
- Settings pane interactions
- Draggable divider behavior
- Toggle state synchronization (@AppStorage)

**Recommended**: Expand `SAAQAnalyzerUITests.swift`
- FilterPanel mode switching
- Year selection interactions
- Chart type changes
- Metric configuration

#### 9. Logging Infrastructure
**Component**: AppLogger (os.Logger wrapper)
**Coverage**: 0%

**Missing Tests**:
- Category-specific loggers
- Privacy redaction
- Performance tracking
- Log level filtering

**Recommended**: `AppLoggerTests.swift` (low priority)

#### 10. AppSettings
**Coverage**: Minimal (processor count detection only)

**Missing Tests**:
- Thread count calculation
- Performance core detection
- Settings persistence
- Regularization toggles (@AppStorage)

**Recommended**: Add to `SAAQAnalyzerTests.swift`

---

## Test Plan Recommendations

### Phase 1: Critical Gaps (2-3 days)

**Priority**: Fill Tier 1 gaps first

1. **Create RegularizationManagerTests.swift**
   - 20-25 test methods
   - Focus: Canonical hierarchy, ID expansion, coupling logic
   - Validation: 109x speedup from caching

2. **Create FilterCacheManagerTests.swift**
   - 15-20 test methods
   - Focus: Initialization, data-type awareness, curated filtering
   - Validation: Cache hit performance

3. **Create GeographicDataImporterTests.swift**
   - 10-15 test methods
   - Focus: d001 parsing, hierarchy insertion
   - Validation: Data integrity

**Estimated Addition**: ~50 test methods, ~25% coverage increase

### Phase 2: Recent Features (1-2 days)

4. **Extend WorkflowIntegrationTests.swift**
   - Add data-type-aware UX tests (5 methods)
   - Add transform integration tests (5 methods)

5. **Create RWIConfigurationTests.swift**
   - 10-15 test methods
   - Focus: Weight validation, JSON serialization

6. **Extend DatabaseManagerTests.swift**
   - Add coverage/percentage metric tests (5 methods)
   - Add transform application tests (5 methods)

**Estimated Addition**: ~30 test methods, ~15% coverage increase

### Phase 3: UI & Infrastructure (1-2 days)

7. **Expand SAAQAnalyzerUITests.swift**
   - FilterPanel interactions (10 methods)
   - Chart rendering (5 methods)
   - Settings pane (5 methods)

8. **Create AppLoggerTests.swift** (optional)
   - 5-10 test methods

**Estimated Addition**: ~25 test methods, ~10% coverage increase

---

## Test Data Strategy

### Current Approach
- **Inline CSV strings** in test methods
- **Temporary directories** for file operations
- **Shared database** (DatabaseManager.shared)

### Limitations
- No reusable test fixtures
- Hard to test with realistic data volumes
- Enum population tests removed (no test database)

### Recommended Improvements

#### 1. Test Fixtures
Create `SAAQAnalyzerTests/Fixtures/` directory:
```
Fixtures/
├── VehicleTestData_2023_1000rows.csv
├── LicenseTestData_2023_1000rows.csv
├── GeographicData_d001_sample.txt
├── RegularizationMappings_sample.json
└── README.md (describes each fixture)
```

#### 2. Test Database Setup
Create `DatabaseTestHelper.swift`:
- `createTestDatabase()` - Fresh SQLite in temp directory
- `populateTestEnums()` - Seed enumeration tables
- `importTestFixture(type:)` - Load fixture CSV
- `cleanupTestDatabase()` - Remove temp files

#### 3. Mock/Stub Pattern
For singleton dependencies:
- Inject database path (not connection)
- Use protocol-based testing for heavy components
- Consider dependency injection for better testability

---

## Performance Testing Strategy

### Current State
- Basic performance tests exist (measure blocks)
- CSV import performance tracked
- Query execution timing validated
- No production-scale load testing

### Gaps
- **No large-scale tests** (1M+ records)
- **No concurrent query stress tests**
- **No memory leak detection** (Instruments integration)
- **No battery/energy impact tests**

### Recommended Performance Suite

#### Create `PerformanceTests.swift`
```swift
// Large-scale data tests
testImportPerformance_1MillionRecords()  // Should complete in <60s
testQueryPerformance_6WayJoin()          // Should complete in <10s with indexes
testCacheRefreshPerformance_FullDB()     // Should complete in <5s

// Concurrent operations
testConcurrentQueries_10Simultaneous()   // No deadlocks
testConcurrentCacheRefresh()             // Safe concurrent access

// Memory tests
testMemoryLeaks_RepeatedQueries()        // No unbounded growth
testMemoryPressure_LargeResultSets()     // Graceful degradation
```

---

## Test Organization

### Current Structure
```
SAAQAnalyzerTests/
├── SAAQAnalyzerTests.swift              (smoke tests)
├── DatabaseManagerTests.swift           (database ops)
├── QueryManagerTests.swift              (query logic - comprehensive)
├── CSVImporterTests.swift               (import pipeline)
├── FilterCacheTests.swift               (UserDefaults cache)
├── CategoricalEnumManagerTests.swift    (schema/indexes)
└── WorkflowIntegrationTests.swift       (end-to-end)

SAAQAnalyzerUITests/
├── SAAQAnalyzerUITests.swift
└── SAAQAnalyzerUITestsLaunchTests.swift
```

### Recommended Structure
```
SAAQAnalyzerTests/
├── Unit/
│   ├── DataLayer/
│   │   ├── DatabaseManagerTests.swift
│   │   ├── QueryManagerTests.swift ✅
│   │   ├── CSVImporterTests.swift
│   │   ├── GeographicDataImporterTests.swift ⚠️ MISSING
│   │   ├── CategoricalEnumManagerTests.swift
│   │   ├── RegularizationManagerTests.swift ⚠️ MISSING
│   │   ├── FilterCacheManagerTests.swift ⚠️ MISSING
│   │   └── FilterCacheTests.swift
│   ├── Models/
│   │   ├── DataModelsTests.swift
│   │   ├── FilterConfigurationTests.swift
│   │   └── TimeSeriesPointTests.swift
│   ├── Settings/
│   │   ├── RWIConfigurationTests.swift ⚠️ MISSING
│   │   └── AppSettingsTests.swift
│   └── Utilities/
│       ├── AppLoggerTests.swift (optional)
│       └── RWICalculatorTests.swift ⚠️ MISSING
├── Integration/
│   ├── WorkflowIntegrationTests.swift
│   ├── DataTypeAwareUXTests.swift ⚠️ MISSING
│   └── TransformIntegrationTests.swift ⚠️ MISSING
├── Performance/
│   └── PerformanceTests.swift ⚠️ MISSING
├── Fixtures/
│   ├── VehicleTestData_2023_1000rows.csv
│   ├── LicenseTestData_2023_1000rows.csv
│   └── README.md
└── Helpers/
    ├── DatabaseTestHelper.swift
    ├── CSVTestHelper.swift
    └── XCTestCase+Async.swift

SAAQAnalyzerUITests/
├── FilterPanelUITests.swift ⚠️ MISSING
├── ChartViewUITests.swift ⚠️ MISSING
├── DataInspectorUITests.swift ⚠️ MISSING
├── SettingsUITests.swift ⚠️ MISSING
└── SAAQAnalyzerUITestsLaunchTests.swift
```

---

## Coverage Metrics

### Estimated Current Coverage
- **Overall**: ~40-50%
- **DataLayer**: ~55% (QueryManager excellent, gaps in Regularization)
- **Models**: ~30% (basic validation only)
- **UI**: ~5% (launch tests only)
- **Settings**: ~10% (minimal)

### Target Coverage (Recommended)
- **Overall**: ~75-80%
- **Critical Path (Tier 1)**: ~90% (RegularizationManager, QueryManager, FilterCacheManager)
- **DataLayer**: ~80%
- **UI**: ~40-50% (focus on critical interactions)

### Measuring Coverage
Xcode provides built-in code coverage:
1. Edit Scheme → Test → Options
2. Enable "Gather coverage for all targets" or select specific targets
3. Run tests (Cmd+U)
4. View Report Navigator → Coverage tab

**Recommended**: Add coverage requirement to CI/CD
```bash
# Fail build if coverage drops below threshold
xcodebuild test -scheme SAAQAnalyzer -enableCodeCoverage YES | \
  xcpretty --report json-compilation-database && \
  ./scripts/check_coverage.sh --threshold 75
```

---

## Test Execution Strategy

### Local Development
```bash
# Run all tests
xcodebuild test -scheme SAAQAnalyzer -destination 'platform=macOS'

# Run specific test suite
xcodebuild test -scheme SAAQAnalyzer -only-testing:SAAQAnalyzerTests/QueryManagerTests

# Run with coverage
xcodebuild test -scheme SAAQAnalyzer -enableCodeCoverage YES

# Parallel execution (faster)
xcodebuild test -scheme SAAQAnalyzer -parallel-testing-enabled YES
```

### CI/CD Integration (GitHub Actions)
```yaml
- name: Run Tests
  run: |
    xcodebuild test \
      -scheme SAAQAnalyzer \
      -destination 'platform=macOS' \
      -enableCodeCoverage YES \
      -parallel-testing-enabled YES \
      -resultBundlePath TestResults.xcresult

- name: Upload Coverage
  uses: codecov/codecov-action@v3
  with:
    files: ./TestResults.xcresult
```

---

## Key Testing Principles (From CLAUDE.md)

### Critical Rules to Test

1. **Integer Enumeration** (Rule #1)
   - ✅ Tested: CategoricalEnumManagerTests validates schema
   - ⚠️ Gap: No tests validating queries never use string columns

2. **Enum Table Indexes** (Rule #6)
   - ✅ Tested: CategoricalEnumManagerTests validates all 9 indexes
   - ✅ Historical: Oct 11, 2025 regression prevented

3. **Background Processing** (Rule #4)
   - ⚠️ Gap: No tests validating Task.detached usage
   - ⚠️ Gap: No tests for MainActor.run correctness

4. **Cache Invalidation Pattern** (Rule #5)
   - ⚠️ Gap: No tests for invalidate → initialize order
   - Recommend: Add to FilterCacheManagerTests

5. **Thread-Safe Database Access** (Rule #9)
   - ⚠️ Gap: No concurrent access stress tests
   - Recommend: Add to PerformanceTests

6. **Table-Specific ANALYZE** (Rule #10)
   - ⚠️ Gap: No tests validating ANALYZE doesn't run on full DB
   - Recommend: Add to DatabaseManagerTests

7. **Parent-Scope ViewModels** (Rule #11)
   - ⚠️ Not testable in unit tests (SwiftUI lifecycle)
   - Recommend: UI test for sheet open/close performance

---

## Recommendations Summary

### Immediate Actions (This Week)
1. ✅ **Save test plan to disk** (respond "Yes" to Xcode prompt)
2. 🔴 **Create RegularizationManagerTests.swift** (highest priority)
3. 🔴 **Create FilterCacheManagerTests.swift** (highest priority)
4. 🟡 **Create test fixtures directory** (enables better tests)

### Short-Term (Next 2 Weeks)
5. 🔴 **Create GeographicDataImporterTests.swift**
6. 🟡 **Add data-type-aware UX tests** to WorkflowIntegrationTests
7. 🟡 **Create RWIConfigurationTests.swift**
8. 🟡 **Extend DatabaseManagerTests** with coverage/percentage metrics

### Medium-Term (Next Month)
9. 🟢 **Create PerformanceTests.swift** with production-scale tests
10. 🟢 **Expand UI tests** (FilterPanel, ChartView interactions)
11. 🟢 **Reorganize test structure** (Unit/Integration/Performance folders)
12. 🟢 **Set up CI/CD** with coverage tracking

### Long-Term (Ongoing)
13. 📈 **Monitor coverage trends** (target 75-80% overall)
14. 📈 **Add tests for each new feature** (test-first development)
15. 📈 **Performance regression tests** (benchmark critical operations)

---

## Conclusion

**Current State**: Moderate coverage (~40-50%) with excellent coverage in critical areas (QueryManager, enum indexes) but significant gaps in RegularizationManager, FilterCacheManager, and UI testing.

**Biggest Wins**:
- Fill RegularizationManager gap (0% → 80%) = ~10% overall coverage increase
- Fill FilterCacheManager gap (0% → 80%) = ~8% overall coverage increase
- Add UI interaction tests = ~5% overall coverage increase
- **Total Potential**: ~65-70% coverage with Phase 1 + Phase 2 complete

**Risk Mitigation**: Prioritize Tier 1 gaps (RegularizationManager, FilterCacheManager) to protect core data quality and performance features.

---

**Next Step**: When Xcode prompts to save test plan, click "Yes" to save the auto-generated .xctestplan file to disk for version control and CI/CD integration.
