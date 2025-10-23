# SAAQAnalyzer Test Suite Documentation

## Overview

The SAAQAnalyzer test suite provides comprehensive coverage for critical application components, with a focus on preventing regression bugs in the cache system, database queries, and CSV import functionality. The tests are built using XCTest framework and are designed to validate both unit-level functionality and end-to-end integration workflows.

## Running the Tests

### Using Xcode (Recommended)

1. Open `SAAQAnalyzer.xcodeproj` in Xcode
2. Select the SAAQAnalyzer scheme from the scheme selector
3. Press `⌘U` or choose Product → Test from the menu
4. View test results in the Test Navigator (⌘6)

### Using Command Line

```bash
# Run all tests
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -destination 'platform=macOS'

# Run specific test class
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -destination 'platform=macOS' \
  -only-testing:SAAQAnalyzerTests/FilterCacheTests

# Run with verbose output
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -destination 'platform=macOS' \
  -quiet | xcpretty
```

## Test Structure

### Test Files Organization

```
SAAQAnalyzerTests/
├── SAAQAnalyzerTests.swift               # Basic app initialization tests
├── OptimizedQueryManagerTests.swift      # Integer query system and RWI calculation tests ✨ NEW
├── CategoricalEnumManagerTests.swift     # Enum table schema and index validation ✨ NEW
├── FilterCacheTests.swift                # Cache separation and consistency tests
├── DatabaseManagerTests.swift            # Database query and performance tests
├── CSVImporterTests.swift               # CSV import and encoding tests
└── WorkflowIntegrationTests.swift        # End-to-end workflow tests
```

## Test Categories

### 1. OptimizedQueryManagerTests ✨ **NEW - October 23, 2025**

**Priority**: CRITICAL (Tier 1)
**Coverage**: Highest-risk component with 0% prior coverage
**Purpose**: Validates integer-based query system, RWI calculations, normalization, cumulative sum transforms, and regularization logic.

**Test Count**: 40+ comprehensive test cases across 8 categories

**Key Test Categories:**

**Filter Conversion (4 tests)**
- `testYearFilterConversion`: Year integer → enum ID conversion
- `testRegionCodeExtraction`: Geographic "Name (##)" format parsing
- `testMakeModelFilterConversion`: Make/Model FilterCacheManager integration
- `testCuratedYearsFiltering`: Uncurated year exclusion logic

**RWI Calculations (9 tests)** - Tests 4th power law road wear calculations
- `testRWICalculation_2Axles`: 0.1325 × mass^4 (45/55 weight split)
- `testRWICalculation_3Axles`: 0.0234 × mass^4 (30/35/35 split)
- `testRWICalculation_6Axles`: 0.0046 × mass^4 (validates 97% damage reduction!)
- `testRWICalculation_TruckFallback`: CA/VO vehicle type fallback (3-axle assumption)
- `testRWICalculation_BusFallback`: AB vehicle type fallback (35/65 split)
- `testRWICalculation_CarFallback`: Default fallback (50/50 split)
- `testRWIMode_Average`: AVG() aggregation
- `testRWIMode_Sum`: SUM() aggregation for total damage
- `testRWIMode_Median`: CTE with window functions

**Normalization (4 tests)** - First-year normalization transforms
- `testNormalization_FirstYear`: Basic normalization (1000 → 1.0, 1100 → 1.1)
- `testNormalization_ZeroFirstYear`: Division by zero protection
- `testNormalization_NegativeFirstYear`: Edge case handling
- `testNormalization_PercentageMode`: Percentage normalization (50% → 1.0)

**Cumulative Sum (3 tests)** - Time series accumulation
- `testCumulativeSum_Basic`: Progressive summation
- `testCumulativeSum_NegativeValues`: Handling decreases
- `testTransformOrder_NormalizeThenCumulative`: **Critical** - validates correct order

**Regularization (8 tests)** - Query expansion and coupling
- `testRegularization_InitializationFromUserDefaults`: Settings persistence
- `testRegularization_MakeIDExpansion`: Uncurated → canonical mapping
- `testRegularization_MakeModelCouplingEnabled`: Preserves hierarchy
- `testRegularization_MakeModelCouplingDisabled`: Independent filters
- `testRegularization_SkippedForCuratedYears`: Optimization for curated data
- `testRegularization_VehicleTypeWithNullHandling`: EXISTS subquery for NULL values
- `testRegularization_FuelTypeTripletMatching`: **Critical** - Make/Model/Year triplets
- `testRegularization_Pre2017FuelTypeToggle`: Pre-2017 NULL fuel_type handling

**Query Building (8 tests)** - SQL generation validation
- `testQueryBuilding_CountMetric`: COUNT(*) queries
- `testQueryBuilding_SumWithIntegerColumn`: net_mass_int optimization
- `testQueryBuilding_AverageVehicleAge`: Computed field with JOIN
- `testQueryBuilding_MedianWithCTE`: Window functions
- `testQueryBuilding_CoveragePercentage`: Data completeness calculations
- `testQueryBuilding_CoverageNullCount`: NULL counting
- `testQueryBuilding_AgeRangeFilter`: BETWEEN clause generation
- `testQueryBuilding_AxleCountFilter`: Critical for RWI accuracy

**License Queries (2 tests)** - License-specific query logic
- `testLicenseQuery_ExperienceLevelAllColumns`: OR logic across 4 columns
- `testLicenseQuery_LicenseClassBooleanColumns`: Boolean column OR logic

**Performance & Edge Cases (5 tests)**
- `testPerformance_IntegerVsStringQuery`: Validates >2x improvement
- `testPerformance_QueryExecutionTime`: <5s target
- `testPerformance_EmptyResultDetection`: Empty result logging
- `testEdgeCase_LargeFilterSet`: 100+ filter values
- `testEdgeCase_SpecialCharacters`: French diacritics handling

**Critical Validations:**
- ✅ RWI formula correctness across all axle configurations
- ✅ Transform order preservation (normalize THEN cumulative)
- ✅ Fuel type triplet matching (prevents cross-model-year errors)
- ✅ Integer enumeration query performance
- ✅ Regularization coupling behavior

**Known Limitations:**
- Tests currently validate configuration objects and formulas
- Database integration requires mock database setup (future work)
- No `OptimizedQueryManager` instantiation (causes SIGABRT with singleton)
- Tests serve as comprehensive documentation of expected behavior

**Test Pattern Established:**
- MainActor annotation for FilterConfiguration tests
- Local helper methods for pure calculations (normalization, cumulative sum)
- Documentation-style tests that validate understanding without problematic instantiations
- Precise RWI calculations with appropriate accuracy tolerances

### 2. CategoricalEnumManagerTests ✨ **NEW - October 23, 2025**

**Priority**: CRITICAL (Tier 1)
**Coverage**: Schema creation and index validation for 16 enumeration tables
**Purpose**: Prevents catastrophic performance regressions from missing enum ID indexes (165s → 10s queries = 16x slower)

**Test Count**: 11 focused tests across 4 categories

**Key Test Categories:**

**Schema Creation (7 tests)** - Validates all 16 enumeration tables
- `testCreateEnumerationTables`: All tables created (year, make, model, fuel_type, vehicle_type, etc.)
- `testYearEnumTableStructure`: Column validation (id, year)
- `testMakeEnumTableStructure`: Column validation (id, name)
- `testModelEnumTableStructure`: Foreign key validation (id, name, make_id)
- `testVehicleClassEnumTableStructure`: Code/description structure
- `testVehicleTypeEnumTableStructure`: Code/description structure
- `testFuelTypeEnumTableStructure`: Code/description structure

**Index Creation (3 tests)** - ⚠️ **CRITICAL FOR PERFORMANCE**
- `testEnumerationIndexesCreated`: Validates **all 9 performance indexes** exist
  - **Historical Context**: Oct 11, 2025 - Missing these caused 165s queries instead of <10s
  - Primary indexes: idx_year_enum_id, idx_make_enum_id, idx_model_enum_id, idx_model_year_enum_id, idx_fuel_type_enum_id, idx_vehicle_type_enum_id
  - Secondary indexes: idx_year_enum_year, idx_vehicle_type_enum_code, idx_fuel_type_enum_code
- `testIndexCreationIdempotent`: IF NOT EXISTS safety
- `testIndexCreatedOnCorrectColumn`: Validates index targets correct columns

**Schema Validation (1 test)**
- `testModelEnumForeignKeyToMakeEnum`: Validates foreign key relationships

**Tests Removed** (documented in code):
- Enum population tests - Depend on vestigial migration code that queries old string columns
- Enum lookup tests - Require populated data
- Duplicate handling tests - Require populated data

**Future Work**: Create test database with TestData CSV imports for population/lookup testing

**Test Pattern Established:**
- Local `createEnumManager()` instances to avoid SIGABRT from singleton cleanup
- MainActor annotations on all helper methods accessing `databaseManager.db`
- Integration tests using production database (idempotent operations with IF NOT EXISTS)
- Clear documentation of removed tests and rationale

**Why These Tests Matter:**
- **Regression Prevention**: Missing indexes = 16x slower queries
- **Critical Rule #6 (CLAUDE.md)**: ALL enum tables MUST have indexes on ID columns
- **Fast, Reliable**: No dependencies on external data or vestigial code

### 3. FilterCacheTests

**Purpose**: Validates cache separation between vehicle and license modes, preventing cross-contamination bugs.

**Key Test Cases:**
- `testVehicleCacheSeparation`: Ensures vehicle cache updates don't affect license cache
- `testLicenseCacheSeparation`: Ensures license cache updates don't affect vehicle cache
- `testCacheKeyCorrectness`: Validates the fix for the experience levels cache key mismatch bug
- `testCacheDataPresence`: Verifies cache state management
- `testDataVersionHandling`: Tests version tracking and migration
- `testFullCacheClear`: Validates complete cache clearing
- `testLicenseOnlyCacheClear`: Tests selective cache clearing
- `testCachePerformance`: Performance testing with realistic data sizes

**Critical Bug Prevention:**
- Prevents the "experience levels showing in vehicle mode" bug
- Ensures proper cache key namespacing between modes

### 4. DatabaseManagerTests

**Purpose**: Tests database operations, query performance, and prevents the 66M record scan issue.

**Key Test Cases:**
- `testDatabaseConnection`: Validates database connectivity
- `testDatabaseTablesExist`: Ensures all required tables are present
- `testVehicleDataQueries`: Tests vehicle-specific query methods
- `testLicenseDataQueries`: Tests license-specific query methods
- `testDataEntityTypeSeparation`: Validates separation between vehicle and license queries
- `testGeographicHierarchy`: Tests municipality/MRC/region relationships
- `testConcurrentCacheRefresh`: Tests thread safety of cache operations
- `testLicenseCharacteristicsPerformance`: Prevents 66M record scan regression

**Performance Benchmarks:**
- Query operations should complete within 5 seconds
- Cache refresh should complete within 3 seconds
- Basic filter queries should complete within 1 second

### 5. CSVImporterTests

**Purpose**: Validates CSV import functionality, French character encoding, and data integrity.

**Key Test Cases:**
- `testVehicleCSVImport`: Tests vehicle data import pipeline
- `testLicenseCSVImport`: Tests license data import pipeline
- `testFrenchCharacterEncoding`: Validates handling of French accents (é, è, à, etc.)
- `testEncodingIssueCorrection`: Tests fixes for common encoding corruptions
- `testMalformedCSVHandling`: Ensures graceful handling of invalid data
- `testEmptyCSVHandling`: Tests edge case of empty files
- `testLargeFilePerformance`: Performance testing with 500-1000 records
- `testQuebecSpecificPatterns`: Validates Quebec-specific data formats

**Encoding Validation:**
- Tests correction of "Montréal" → "Montréal" type corruptions
- Validates proper handling of all French diacritical marks
- Ensures data integrity through import pipeline

### 6. WorkflowIntegrationTests

**Purpose**: Tests complete end-to-end workflows from CSV import through data analysis.

**Key Test Cases:**
- `testVehicleDataCompleteWorkflow`: Full vehicle data pipeline test
- `testLicenseDataCompleteWorkflow`: Full license data pipeline test
- `testModeSwitchingWorkflow`: Validates mode switching maintains data separation
- `testCacheConsistencyAcrossOperations`: Tests cache coherence
- `testDataQualityThroughWorkflow`: Validates data integrity with edge cases
- `testWorkflowPerformance`: End-to-end performance benchmarks

**Workflow Coverage:**
1. CSV file import
2. Database insertion
3. Cache refresh
4. Filter option population
5. Data querying with filters
6. Result validation

### 6. SAAQAnalyzerTests

**Purpose**: Basic application initialization and setup tests.

**Key Test Cases:**
- `testApplicationInitialization`: Core component initialization
- `testDataModelTypes`: Enum configuration validation
- `testDataEntityTypes`: Vehicle vs License type validation
- `testFilterConfiguration`: Default filter state validation
- `testAppSettings`: System configuration and performance settings

## Important Test Patterns

### @MainActor Isolation

Many test methods are marked with `@MainActor` due to SwiftUI's actor isolation requirements:

```swift
@MainActor
func testVehicleDataCompleteWorkflow() async throws {
    // Test code that accesses @MainActor isolated properties
}
```

### Async/Await Testing

Database operations use async/await patterns:

```swift
func testDatabaseQuery() async throws {
    let result = try await databaseManager.queryVehicleData(filters: config)
    XCTAssertGreaterThanOrEqual(result.points.count, 0)
}
```

### Performance Testing

Critical operations include performance assertions:

```swift
let startTime = Date()
let result = try await csvImporter.importFile(at: url, year: 2023, dataType: .vehicle)
let duration = Date().timeIntervalSince(startTime)
XCTAssertLessThan(duration, 5.0, "Import should complete within 5 seconds")
```

## Test Data Management

### Temporary Files

Tests create temporary CSV files for import testing:

```swift
let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("TestData-\(UUID().uuidString)")
```

### Mock Data

Tests use realistic Quebec data patterns:
- Region codes: 2-digit numeric (01-17)
- MRC codes: 2-digit numeric
- Municipality codes: 5-digit numeric
- License types: REGULIER, PROBATOIRE, APPRENTI
- Experience levels: "Moins de 2 ans", "2 à 5 ans", etc.

### Cleanup

All tests implement proper cleanup in `tearDownWithError()`:
- Remove temporary files
- Clear cache state
- Reset test fixtures

## Common Test Assertions

### Cache Tests
```swift
XCTAssertTrue(filterCache.hasCachedData)
XCTAssertEqual(filterCache.getCachedYears(for: .vehicle), expectedYears)
XCTAssertTrue(filterCache.getCachedLicenseTypes().isEmpty) // No cross-contamination
```

### Import Tests
```swift
XCTAssertEqual(result.totalRecords, 100)
XCTAssertEqual(result.successCount, 100)
XCTAssertEqual(result.errorCount, 0)
```

### Query Tests
```swift
let filteredData = try await databaseManager.queryVehicleData(filters: config)
XCTAssertGreaterThanOrEqual(filteredData.points.count, 0)
XCTAssertTrue(filteredData.name.contains("TOYOTA"))
```

## Debugging Failed Tests

### Common Issues and Solutions

1. **Cache Contamination Failures**
   - Clear UserDefaults before running: `defaults delete com.saaqanalyzer.SAAQAnalyzer`
   - Check FilterCache key namespacing in implementation

2. **Database Query Timeouts**
   - Verify indexes exist on year, classification, fuel_type columns
   - Check for missing WHERE clauses causing full table scans

3. **Import Failures**
   - Verify CSV encoding (should be UTF-8)
   - Check for unique constraint violations in database
   - Ensure year parameter matches CSV data

4. **@MainActor Isolation Errors**
   - Add @MainActor to test methods accessing UI-related code
   - Use `await` when calling main actor isolated methods

### Verbose Test Output

For detailed test failure information:

```bash
# Run with detailed output
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer \
  -destination 'platform=macOS' -enableCodeCoverage YES | tee test_output.log

# Search for failures
grep -A 10 "error:" test_output.log
grep -A 5 "Test Case.*failed" test_output.log
```

## Continuous Integration

### GitHub Actions Configuration (if needed)

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v2
    - name: Run tests
      run: |
        xcodebuild test -project SAAQAnalyzer.xcodeproj \
          -scheme SAAQAnalyzer -destination 'platform=macOS'
```

## Test Coverage Goals

### Current Coverage Areas
- ✅ Cache separation logic (preventing mode cross-contamination)
- ✅ Database query performance (preventing full table scans)
- ✅ CSV import with French character encoding
- ✅ End-to-end workflows
- ✅ Geographic data hierarchy
- ✅ Filter configuration management

### Pending Test Coverage (October 2025 Features)

The following features were added in October 2025 and **require test coverage**:

#### Road Wear Index (RWI) Metric
- ✅ **Implemented**: October 2025 (enhanced with axle-based calculation)
- ⚠️ **Tests Needed**:
  - Calculation correctness (4th power law: damage ∝ axle_load^4)
  - Axle-based weight distribution (2-6+ axles, coefficients 0.1325 to 0.0046)
  - Vehicle-type fallback when max_axles is NULL (AU, CA, AB vehicles)
  - Normalization toggle (normalize to first year = 1.0)
  - Average vs Sum modes
  - Raw vs Normalized display formats

**Test Cases to Add**:
```swift
testRoadWearIndexCalculation()           // Verify 4th power law math
testRoadWearIndexAxleBasedDistribution() // Test actual axle count calculations (2-6+ axles)
testRoadWearIndexVehicleTypeFallback()   // Test AU/CA/AB fallback when max_axles is NULL
testRoadWearIndexNormalization()         // Verify normalization to year 1
testRoadWearIndexModes()                 // Test Average vs Sum modes
```

#### Cumulative Sum Transform
- ✅ **Implemented**: October 2025
- ⚠️ **Tests Needed**:
  - Cumulative sum calculation (running total)
  - Transformation order (normalize → cumulative)
  - Works with all metric types (Count, RWI, Average, etc.)
  - Vehicle and license data paths

**Test Cases to Add**:
```swift
testCumulativeSumCalculation()           // Verify running total logic
testCumulativeSumWithNormalization()     // Test RWI normalize → cumulative order
testCumulativeSumAllMetrics()            // Test with Count, Average, Percentage, etc.
testCumulativeSumLicenseData()           // Test license data path
```

#### Regularization System Performance
- ✅ **Implemented**: October 2025
- ⚠️ **Tests Needed**:
  - Canonical hierarchy cache (109x speedup)
  - Background auto-regularization
  - Database indexes on enum table IDs
  - Triplet-based fuel type filtering

**Test Cases to Add**:
```swift
testCanonicalHierarchyCachePerformance() // Verify 109x improvement
testBackgroundAutoRegularization()       // Test async processing
testRegularizationIndexes()              // Verify JOIN performance
testTripletFuelTypeFiltering()           // Test Make/Model/Year matching
```

### Future Test Considerations
- Chart rendering validation
- Export functionality testing (Data Package with canonical cache)
- Memory usage under stress conditions
- UI interaction testing
- Network error handling (for future features)
- RWI vehicle type edge cases (unknown types, mixed fleets)

## Maintenance Notes

### When to Update Tests

1. **After Bug Fixes**: Add regression tests for any fixed bugs
2. **New Features**: Add tests for new functionality before implementation (TDD)
3. **Performance Issues**: Add performance benchmarks when optimization is needed
4. **Data Format Changes**: Update mock data and validation logic

### Test Naming Convention

Tests follow the pattern: `test<Component><Scenario>`

Examples:
- `testVehicleCacheSeparation`
- `testLicenseDataQueries`
- `testFrenchCharacterEncoding`
- `testWorkflowPerformance`

## Contact and Support

For test-related questions or issues:
- Review test failure output in Xcode's Test Navigator
- Check this documentation for common issues
- Consult CLAUDE.md for project-specific guidance
- Review git history for test evolution context