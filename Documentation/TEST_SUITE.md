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
├── SAAQAnalyzerTests.swift         # Basic app initialization tests
├── FilterCacheTests.swift          # Cache separation and consistency tests
├── DatabaseManagerTests.swift      # Database query and performance tests
├── CSVImporterTests.swift         # CSV import and encoding tests
└── WorkflowIntegrationTests.swift  # End-to-end workflow tests
```

## Test Categories

### 1. FilterCacheTests

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

### 2. DatabaseManagerTests

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

### 3. CSVImporterTests

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

### 4. WorkflowIntegrationTests

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

### 5. SAAQAnalyzerTests

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

### Future Test Considerations
- Chart rendering validation
- Export functionality testing
- Memory usage under stress conditions
- UI interaction testing
- Network error handling (for future features)

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