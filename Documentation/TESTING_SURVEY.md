# SAAQAnalyzer - Comprehensive Testing Survey

## Executive Summary

SAAQAnalyzer is a sophisticated macOS SwiftUI application (42 Swift files, ~24K LOC) for analyzing vehicle registration and driver license data from SAAQ (Québec insurance authority). The codebase employs an integer-based enumeration architecture optimized for performance, with careful attention to concurrency, caching, and regularization of categorical data.

**Key Statistics:**
- **Total Swift Files**: 42
- **Main Codebase**: ~24K lines (DataLayer: 7.9K, Models: 3.9K, UI: 6.2K, Utilities: 2.1K)
- **Existing Tests**: 5 test files with baseline test infrastructure

---

## 1. DATALAYER COMPONENTS

### 1.1 DatabaseManager.swift (7,842 lines)
**Responsibility**: Core SQLite database abstraction and lifecycle management

**Key Classes**:
- `DatabaseManager` - Singleton managing database connection, schema, caching
  - Published properties: `databaseURL`, `dataVersion`, `testDatabaseCleanupNeeded`
  - Managers: `filterCacheManager`, `schemaManager`, `optimizedQueryManager`, `regularizationManager`

**Public APIs to Test**:
```swift
// Database Lifecycle
func setDatabaseLocation(_ url: URL)
func isYearImported(_ year: Int) async -> Bool
func clearYearData(_ year: Int) async throws

// Schema & Setup
func createTablesIfNeeded() async throws
func getSchema(for year: Int) -> DataSchema

// Query APIs (returning FilteredDataSeries)
func queryVehicleData(configuration: FilterConfiguration) async throws -> FilteredDataSeries
func queryLicenseData(configuration: FilterConfiguration) async throws -> FilteredDataSeries

// Cache Management
func invalidateCache() async
func refreshAllCaches(dataType: DataEntityType) async

// Data Retrieval (Filter Options)
func getAvailableYears(for dataType: DataEntityType) async -> [Int]
func getAvailableRegions(for dataType: DataEntityType) async -> [String]
func getAvailableMRCs(for dataType: DataEntityType) async -> [String]
func getAvailableMunicipalities(for dataType: DataEntityType) async -> [String]

// Analytics Helpers
func normalizeToFirstYear(_ values: [(Int, Double)]) -> [(Int, Double)]
func applyCumulativeSum(_ values: [(Int, Double)]) -> [(Int, Double)]
```

**Complex Logic Requiring Validation**:
1. **Query Execution** (lines ~1300-2700)
   - Vehicle query: Joins 6+ enumeration tables with optional regularization
   - License query: Separate JOIN pattern for license-specific fields
   - RWI (Road Wear Index) calculation with axle-based weighting
   - Percentage calculation with baseline subquery
   - Coverage analysis (NULL/non-NULL field counts)
   
2. **Normalization Pipeline** (lines ~399-442)
   - `normalizeToFirstYear()`: Divides all values by first year, handles edge cases (zero values)
   - `applyCumulativeSum()`: Transforms series into cumulative values
   - Order matters: Normalize BEFORE cumulative sum
   
3. **Cache Invalidation Pattern** (lines ~2900+)
   - Must call `invalidateCache()` BEFORE `initializeCache()`
   - Guard against concurrent refresh attempts using `refreshLock`
   
4. **Test Mode Handling** (lines ~65-100)
   - SAAQ_TEST_MODE environment variable for fresh installation simulation
   - Automatic cleanup of leftover test databases
   - UserDefaults filter cache clearing

**Integration Points**:
- Depends on: `CategoricalEnumManager` (enumeration creation), `FilterCacheManager` (filter loading), `OptimizedQueryManager` (integer queries), `RegularizationManager` (make/model mappings), `SchemaManager` (schema migrations)
- Publishes: `dataVersion` (triggers UI refresh), cache state changes

**Known Pitfalls** (from CLAUDE.md):
- ❌ Must NOT use string columns for categorical data (use integer foreign keys)
- ❌ Must invalidate cache BEFORE re-initialization
- ❌ All enum table IDs require indexes (16x performance difference)
- ❌ Expensive operations (>100ms) must run in background
- ✅ Pass database PATHS (strings), never share OpaquePointer across concurrent tasks

---

### 1.2 CSVImporter.swift (958 lines)
**Responsibility**: SAAQ CSV file parsing and import into database

**Key Classes**:
- `CSVImporter` - Orchestrates import workflow
- `ProgressTracker` - Thread-safe progress actor for real-time updates
- Error enums: `CSVParseError`, `ImportError`

**Public APIs to Test**:
```swift
// Main entry point
func importFile(at url: URL, year: Int, dataType: DataEntityType, skipDuplicateCheck: Bool = false) 
  async throws -> ImportResult

// Type-specific imports
func importVehicleFile(at url: URL, year: Int, skipDuplicateCheck: Bool = false) 
  async throws -> ImportResult
func importLicenseFile(at url: URL, year: Int, skipDuplicateCheck: Bool = false) 
  async throws -> ImportResult

// Results
struct ImportResult {
    let totalRecords: Int
    let successCount: Int
    let errorCount: Int
    let importedRecords: [String]  // Partial record details
}
```

**Complex Logic Requiring Validation**:
1. **Schema Detection by Year** (lines ~70-80)
   - 2017+ vehicle data: 16 fields (fuel_type added)
   - Pre-2017 vehicle data: 15 fields (no fuel_type)
   - License data: Fixed 20-field schema
   
2. **Character Encoding Handling** (lines ~180-220)
   - Multi-stage fallback: UTF-8 → ISO-Latin-1 → Windows-1252
   - Common corruption pattern fixes: "MontrÃ©al" → "Montréal"
   - French diacritics preservation
   
3. **Batch Processing Pipeline** (lines ~100-150)
   - 1000-record batches for memory efficiency
   - Parallel CSV parsing using Task.detached
   - Progress tracking with actor-based synchronization
   - Error accumulation and reporting
   
4. **Data Type Awareness** (lines ~40-45)
   - Vehicle imports: Load vehicle caches
   - License imports: Load license caches (NOT vehicle caches)
   - Selective cache refresh critical for performance
   
5. **Year Handling & Deduplication** (lines ~60-70)
   - Checks if year already imported before starting
   - Auto-clears old data for same year during replacement
   - Supports skipDuplicateCheck for SwiftUI alert handling

**Test Data Considerations**:
- Real SAAQ CSV files are massive (100K+ records)
- Test strategy: Use abbreviated CSV files (1000 rows or less)
- Must handle encoding anomalies from actual data
- License imports ignore MRC field (returns empty/NULL per CLAUDE.md)

---

### 1.3 FilterCacheManager.swift (892 lines)
**Responsibility**: Efficient in-memory enumeration-based filter cache

**Key Classes**:
- `FilterCacheManager` - Loads and caches enumeration tables
- Cached items: `FilterItem` struct (id: Int, name: String)
- Regularization info: Make/Model mappings and uncurated pair counts

**Public APIs to Test**:
```swift
// Cache Initialization
func initializeCache() async throws
func initializeCache(for dataType: DataEntityType?) async throws
func invalidateCache() async

// Getter Methods (return FilterItem arrays or Int arrays)
func getYears() -> [Int]
func getRegions() -> [FilterItem]
func getMRCs() -> [FilterItem]
func getMunicipalities() -> [FilterItem]
func getVehicleClasses() -> [FilterItem]
func getVehicleTypes() -> [FilterItem]
func getMakes() -> [FilterItem]
func getModels() -> [FilterItem]
func getColors() -> [FilterItem]
func getFuelTypes() -> [FilterItem]
func getAxleCounts() -> [Int]

// Regularization Info
func getRegularizationInfo() -> [String: (canonicalMake: String, canonicalModel: String, recordCount: Int)]
func getUncuratedPairs() -> [String: Int]
func getMakeRegularizationInfo() -> [String: (canonicalMake: String, recordCount: Int)]
func getUncuratedMakes() -> [String: Int]

// Hierarchical Filtering
func getModelToMakeMapping() -> [Int: Int]
func getModelsForMake(_ makeId: Int) -> [FilterItem]
```

**Complex Logic Requiring Validation**:
1. **Dual-Layer Cache Initialization** (lines ~50-120)
   - Guard against both completed AND in-progress initialization
   - Prevents concurrent initialization via `isInitializing` flag
   - Signposts for Instruments profiling integration
   
2. **Data Type Selective Loading** (lines ~80-110)
   - Vehicle data: Regularization tables, Makes (expensive), Models, Colors, Fuel, Axles
   - License data: License-specific tables (Types, Age Groups, Genders, Experience)
   - Shared: Years, Regions, MRCs, Municipalities
   - Optimization: Don't load vehicle caches for license-only imports
   
3. **Regularization Info Loading** (lines ~150-200)
   - Queries `canonical_hierarchy_cache` for pre-aggregated mappings
   - Maps "makeId_modelId" keys to canonical values
   - Fallback: Generate cache on first use if not pre-populated
   
4. **Uncurated Pair Detection** (lines ~210-250)
   - Identifies Make/Model pairs existing ONLY in uncurated years
   - "Uncurated" = years outside the curated year range (configurable)
   - Used for "Limit to Curated Years Only" filter toggle
   
5. **Hierarchical Model Filtering** (lines ~260-290)
   - Builds modelId → makeId mapping for fast filtering
   - Critical for "Filter Models by Selected Makes" feature
   - Enables fast in-memory filtering in FilterPanel

**Test Requirements**:
- Test initialization order and guard conditions
- Verify no data loss on re-initialization
- Validate regularization info accuracy
- Test selective loading (vehicle vs. license)
- Verify hierarchical filtering mappings

---

### 1.4 OptimizedQueryManager.swift (1,267 lines)
**Responsibility**: High-performance integer-based query execution

**Key Classes**:
- `OptimizedQueryManager` - Executes queries using enumeration table IDs
- `OptimizedFilterIds` - Holds converted filter string-to-ID mappings

**Public APIs to Test**:
```swift
// Main Query Entry Points
func queryOptimizedVehicleData(filters: FilterConfiguration) async throws -> FilteredDataSeries
func queryOptimizedLicenseData(filters: FilterConfiguration) async throws -> FilteredDataSeries

// Properties
var regularizationEnabled: Bool { get set }
var regularizationCoupling: Bool { get set }

// Internal (but complex)
private func convertFiltersToIds(filters: FilterConfiguration, isVehicle: Bool) 
  async throws -> OptimizedFilterIds
private func queryVehicleDataWithIntegers(filters: FilterConfiguration, filterIds: OptimizedFilterIds) 
  async throws -> FilteredDataSeries
private func queryLicenseDataWithIntegers(filters: FilterConfiguration, filterIds: OptimizedFilterIds) 
  async throws -> FilteredDataSeries
```

**Complex Logic Requiring Validation**:
1. **Filter String-to-ID Conversion** (lines ~70-350)
   - Extracts parenthesized codes: "Montréal (66023)" → 66023
   - Joins FilterItem arrays to integer IDs
   - Handles optional fields (empty arrays for unselected filters)
   - Validates IDs exist in enumeration tables
   
2. **Query Pattern Matching** (lines ~420-500)
   - Makes: Handles coupling requirement
   - Models: Dependent on Makes when coupling enabled
   - Geographic: Multi-level filtering (Region → MRC → Municipality)
   - Year: Range filtering with nested arrays
   
3. **RWI Calculation** (lines ~640-680)
   - Axle-based weight distribution (2-6+ axles)
   - Vehicle type fallback when axle counts unknown
   - 4th power law: damage ∝ (axle_load)^4
   - Uses `net_mass_int` integer column for precision
   
4. **Normalization Pipeline** (lines ~715-730)
   - Normalize to first year BEFORE cumulative sum
   - Handles edge cases: zero first year, NaN values
   - Automatic 2-decimal precision detection
   
5. **Query Plan Caching & Transparency** (lines ~750-850)
   - Uses EXPLAIN QUERY PLAN to analyze performance before execution
   - Generates human-readable query patterns
   - Detects table scans, temp B-trees, suboptimal indexes
   - Returns performance classification (Excellent → Slow)

**Performance Critical Paths**:
- Integer columns: `net_mass_int`, `displacement_int`, `year_id`, `vehicle_class_id`, `fuel_type_id`
- Indexes required: All ID columns on enumeration tables (15+ indexes)
- Query optimization: Regularization can add extra JOINs, requiring comprehensive indexing

**Known Performance Issues** (from CLAUDE.md):
- ❌ Missing enum table ID indexes: 165s → <10s (16x improvement)
- ❌ Regularization without coupling: Performance degrades significantly
- ✅ Covering indexes on common query patterns
- ✅ Query plan analysis prevents slow queries

---

### 1.5 CategoricalEnumManager.swift (787 lines)
**Responsibility**: Enumeration table creation and population

**Key Classes**:
- `CategoricalEnumManager` - Creates and populates enumeration tables with proper indexing

**Public APIs to Test**:
```swift
// Schema Creation
func createEnumerationTables() async throws
func createEnumerationIndexes() async throws

// Population
func populateEnumerationsFromExistingData() async throws
func populateEnumerationFromVehicleField(fieldName: String, enumTableName: String) async throws

// Lookups
func getEnumValue(for enumValue: String, from tableName: String) async throws -> Int?
func getEnumDisplay(for id: Int, from tableName: String) async throws -> String?
```

**Complex Logic Requiring Validation**:
1. **Table Schema Design** (lines ~16-200)
   - TINYINT (1-byte) tables: year, classification, vehicle_type, cylinders, axles, color, fuel_type, regions, age_groups, genders, license_types
   - SMALLINT (2-byte) tables: makes, models, model_years, MRCs, municipalities
   - Optimal size selection for index performance and memory efficiency
   
2. **Index Creation** (lines ~57-88)
   - CRITICAL INDEXES on all ID columns (9 primary indexes)
   - Secondary indexes on year, code fields
   - Index creation must happen IMMEDIATELY after table creation
   - Missing indexes: 165s → <10s performance difference
   
3. **Foreign Key Relationships** (lines ~100-200)
   - All enumeration tables properly related
   - Referential integrity enforced on vehicle/license tables
   
4. **NULL Handling in Population** (lines ~300-400)
   - Geographic: MRC field is NULL for 2023-2024 (known SAAQ data limitation)
   - Fuel type: NULL for pre-2017 vehicles
   - Model year: Can be NULL for imported vehicles with incomplete data

**Integration with DatabaseManager**:
- Called during initial schema creation: `createTablesIfNeeded()`
- Called during migration: `migrateToOptimizedSchema()`
- Indexes created before any queries run

---

### 1.6 RegularizationManager.swift (1,951 lines)
**Responsibility**: Make/Model regularization and canonical hierarchy management

**Key Classes**:
- `RegularizationManager` - Manages regularization mappings and query translation
- `MakeModelHierarchy` - In-memory representation of canonical relationships
- `RegularizationYearConfiguration` - Defines curated vs. uncurated years

**Public APIs to Test**:
```swift
// Configuration
func setYearConfiguration(_ config: RegularizationYearConfiguration)
func getYearConfiguration() -> RegularizationYearConfiguration

// Hierarchy Generation
func generateCanonicalHierarchy() async throws -> MakeModelHierarchy
func getCachedHierarchy() -> MakeModelHierarchy?

// Query Translation
func translateVehicleQuery(filters: FilterConfiguration) async throws -> FilterConfiguration
func translateLicenseQuery(filters: FilterConfiguration) async throws -> FilterConfiguration

// Mapping Management
func addRegularizationMapping(uncuratedMakeId: Int, uncuratedModelId: Int, 
                             canonicalMakeId: Int, canonicalModelId: Int) async throws
func getRawMakeModel(for regularizationId: Int) async throws -> (makeId: Int, modelId: Int)?
```

**Complex Logic Requiring Validation**:
1. **Canonical Hierarchy Generation** (lines ~400-600)
   - Queries all Make/Model combinations from curated years
   - Groups by canonical values
   - Performance: 13.4s → 0.12s with cache (109x improvement)
   - Materialized in `canonical_hierarchy_cache` table
   
2. **Query Translation with Coupling** (lines ~700-900)
   - When regularization enabled: Replace filter Makes/Models with canonical equivalents
   - With coupling: Model filters depend on Make filters
   - Without coupling: Independent Make and Model filters
   - Applies to BOTH vehicle and license queries
   
3. **Year Configuration Impact** (lines ~70-100)
   - "Curated years": Reliable Make/Model data
   - "Uncurated years": May have typos, variants
   - Configuration change triggers cache invalidation
   - Used to generate `canonical_hierarchy_cache`
   
4. **Regularization Table Schema** (lines ~23-70)
   - Triplet-based: (uncurated_make, uncurated_model, model_year) → (canonical_make, canonical_model)
   - Optional fuel_type and vehicle_type specificity
   - Record count tracking for statistics
   - Unique constraint on triplet key

**Test Challenges**:
- Requires understanding of curated/uncurated year boundaries
- Hierarchy generation is expensive (O(n^2) on Make/Model combinations)
- Cache invalidation must be tested carefully
- Query translation affects filter logic in complex ways

---

### 1.7 SchemaManager.swift (441 lines)
**Responsibility**: Database schema migrations and optimizations

**Key Classes**:
- `SchemaManager` - Orchestrates schema migrations to optimized enumeration format

**Public APIs to Test**:
```swift
func migrateToOptimizedSchema() async throws
func repopulateIntegerColumns() async throws
func validateMigration() async throws
func dropLegacyColumns() async throws
```

**Complex Logic Requiring Validation**:
1. **Migration Pipeline** (lines ~17-29)
   - Create enumeration tables → Populate from existing → Add integer columns → Populate integers → Create indexes → Validate
   - Order is critical
   - Each step can fail independently
   
2. **Integer Column Addition** (lines ~53-79)
   - Adds TINYINT/SMALLINT columns to vehicles and licenses tables
   - Uses ALTER TABLE (safe, backwards compatible)
   - Columns initially NULL, populated in next step
   
3. **Population of Integer Columns** (lines ~100-150)
   - Bulk UPDATE with JOIN to enumeration tables
   - Converts string values to integer IDs
   - Handles NULL source values gracefully
   - Progress tracking for large datasets
   
4. **Validation** (lines ~180-220)
   - Verifies all rows have populated integer columns
   - Checks for orphaned records (IDs with no enumeration match)
   - Reports any migration failures
   - Safe to re-run multiple times

---

### 1.8 GeographicDataImporter.swift (378 lines)
**Responsibility**: Import geographic reference data (d001 format)

**Key Classes**:
- `GeographicDataImporter` - Parses d001 files and populates geographic tables

**Public APIs to Test**:
```swift
func importGeographicData(from url: URL) async throws -> (inserted: Int, updated: Int)
```

**Data Formats**:
- D001 files: Tab-separated hierarchical geographic data
- Columns: Municipality Code, Municipality Name, MRC Code, MRC Name, Region Code, Region Name
- Creates `geographic_entities` table with hierarchical relationships

**Test Requirements**:
- Verify correct parsing of tab-separated format
- Validate hierarchy relationships (municipality → MRC → Region)
- Test duplicate detection and update logic

---

### 1.9 FilterConfigurationAdapter.swift (177 lines)
**Responsibility**: Bridge between UI FilterConfiguration and database query formats

**Simple APIs to Test**:
```swift
func adaptFilterConfiguration(_ config: FilterConfiguration) -> AdaptedFilterConfiguration
```

**Test Focus**:
- Verify correct transformation of UI filters to query format
- Test edge cases: empty filters, all selected, mixed selections

---

### 1.10 DataPackageManager.swift (1,285 lines)
**Responsibility**: Serialization/deserialization of analysis results as portable packages

**Key Concepts**:
- Exports charts and associated data as ZIP packages
- Supports CSV export, JSON metadata, package compression
- Used by DataInspector for data export

---

## 2. MODELS COMPONENTS

### 2.1 DataModels.swift (2,064 lines)
**Responsibility**: Core data structures and enumerations

**Major Structs/Enums to Test**:

```swift
// Core Data Models
struct VehicleRegistration: Codable, Sendable {
    let year: Int
    let vehicleSequence: String
    let classification: String
    let vehicleClass: String
    let make: String
    let model: String
    let modelYear: Int?
    let netMass: Double?
    let cylinderCount: Int?
    let displacement: Double?
    let maxAxles: Int?
    let originalColor: String?
    let fuelType: String?
    let adminRegion: String
    let mrc: String
    let geoCode: String
}

struct DriverLicense: Codable, Sendable {
    let year: Int
    let licenseSequence: String
    let ageGroup: String
    let gender: String
    // ... 16+ more fields for license classes, experience levels
}

// Enumeration Types
enum VehicleClass: String, CaseIterable, Sendable {
    case pau, pmc, pcy, phm, cau, cmc, ccy, chm, tta, tab, tas, bca, cvo, cot,
         rau, rmc, rcy, rhm, rab, rca, rmn, rot,
         hau, hcy, hab, hca, hmn, hvt, hvo, hot
}

enum FuelType: String, CaseIterable, Sendable {
    case electric, gasoline, diesel, hybrid, hydrogen, propane, naturalGas, 
         methanol, ethanol, hybridPlugin, other, nonPowered
}

enum AgeGroup: String, CaseIterable, Sendable {
    case underSixteen, sixteenToNineteen, twentyToTwentyfour, twentyfiveToThirtyfour,
         thirtyfiveToFortyfour, fortyfiveToFiftyfour, fiftyfiveToSixtyfour, sixtyfiveAndUp
}

// Filter Configuration
struct FilterConfiguration: Sendable {
    var dataEntityType: DataEntityType = .vehicle
    var years: [String] = []
    var regions: [String] = []
    var mrcs: [String] = []
    var municipalities: [String] = []
    var vehicleClasses: [String] = []
    var vehicleTypes: [String] = []
    var vehicleMakes: [String] = []
    var vehicleModels: [String] = []
    var vehicleColors: [String] = []
    var modelYears: [String] = []
    var fuelTypes: [String] = []
    var ageRanges: [String] = []
    var metricType: ChartMetricType = .count
    var metricField: String? = nil
    var limitToCuratedYearsOnly: Bool = false
    var regularizationEnabled: Bool = false
    var regularizationCoupling: Bool = true
    var normalizeToFirstYear: Bool = false
    var showCumulativeSum: Bool = false
    // ... 20+ more configuration fields
}

// Query Results
struct FilteredDataSeries: Sendable {
    let yAxisLabel: String
    let legend: String
    let data: [(year: Int, value: Double)]
    let statistics: SeriesStatistics
    let configuration: FilterConfiguration
}

struct SeriesStatistics: Sendable {
    let count: Int
    let sum: Double
    let average: Double
    let minimum: Double
    let maximum: Double
    let standardDeviation: Double
}
```

**Key Validations Required**:
1. **VehicleRegistration.age(in:)** - Verify age calculation logic
2. **FilteredDataSeries normalization** - Verify formatValue() handles all metric types
3. **ChartMetricType** - All enum cases properly documented
4. **SeriesStatistics** - Mathematical accuracy of calculations

---

### 2.2 FilterCache.swift (445 lines)
**Responsibility**: UserDefaults-based caching for filter options

**Legacy Component Note**: 
Being replaced by `FilterCacheManager` (enumeration-based) but still used for:
- Test cleanup: `FilterCache().clearCache()`
- Legacy data migration
- UserDefaults backward compatibility

**Test Focus**:
- Verify cache key isolation
- Test data persistence across app sessions
- Validate backward compatibility during migration

---

### 2.3 ImportProgressManager.swift (258 lines)
**Responsibility**: Real-time progress tracking during imports

**Key Classes**:
```swift
@MainActor
@Observable
class ImportProgressManager {
    var overallProgress: Double
    var currentStage: ImportStage
    var stageProgress: StageProgress
    var isImporting: Bool
    
    enum ImportStage: Int, CaseIterable {
        case idle, reading, parsing, importing, indexing, completed
    }
    
    enum StageProgress {
        case idle
        case reading
        case parsing(processed: Int, total: Int, workersActive: Int)
        case importing(batch: Int, totalBatches: Int, recordsProcessed: Int, totalRecords: Int)
        case indexing(operation: String)
        case completed(duration: TimeInterval, recordsImported: Int, recordsPerSecond: Int)
    }
}
```

**Test Requirements**:
- Verify stage progression (idle → reading → parsing → importing → indexing → completed)
- Test batch progress updates
- Validate thread safety with @MainActor
- Test batch import (multiple files) vs. single file

---

### 2.4 AppSettings.swift (243 lines)
**Responsibility**: Application preferences and user settings

**Key Properties**:
- `appearanceMode` - Light/Dark/System preference
- `regularizationEnabled` - Global regularization toggle
- `limitToCuratedYearsOnly` - Global curated years toggle
- All properties use `@AppStorage` for automatic UserDefaults persistence

**Test Requirements**:
- Verify @AppStorage property persistence
- Test Settings UI bindings
- Validate preference propagation to query system

---

## 3. UI COMPONENTS

### 3.1 FilterPanel.swift (2,743 lines)
**Responsibility**: Left panel for filter configuration and analytics setup

**Complex Nested Components**:
- **Analytics Section** (draggable divider, 200-600pt height range)
  - Y-Axis Metric configuration
  - RWI mode selector
  - Cumulative sum toggle
  - Normalize to first year toggle
  
- **Filters Section** (hierarchical structure)
  1. Filter Options (toggles for curation, regularization, coupling)
  2. Years (single-select)
  3. Geographic Location (region → MRC → municipality)
  4. Vehicle/License Characteristics
     - Hierarchical Make/Model filtering (manual button-triggered)
     - Make selection → "Filter by Selected Makes" button
     - State tracking: ready/filtering/reset states

**State Management Complexity**:
- 20+ @State variables for filter options
- 8+ @State variables for section expansion states
- Expansion state synchronization with localStorage
- Draggable divider position persistence

**Critical Implementation Details** (from CLAUDE.md):
- ❌ NEVER use `.onChange` for filter state updates (causes AttributeGraph crashes)
- ✅ Use manual button triggers for expensive operations
- ❌ Never trigger filterModels() automatically
- ✅ Use background tasks for cache loading
- ✅ Parent-scope ViewModels for expensive sheet data

**Test Requirements**:
- Verify filter option loading (years, regions, makes, models)
- Test hierarchical filtering (Make → Model dependency)
- Validate draggable divider bounds (200-600pt)
- Test expansion state persistence
- Verify no AttributeGraph circular dependencies
- Test regularization toggle integration

---

### 3.2 ChartView.swift (879 lines)
**Responsibility**: Center panel for time series visualization

**Key Features**:
- Chart type selection (line, bar, area)
- Legend with series selection
- Y-axis formatting (automatic precision for normalized values)
- Clipboard export capability
- Query preview bar (persistent transport controls)

**Chart Metric Formatting** (critical logic):
```swift
enum ChartMetricType: String, CaseIterable {
    case count
    case sum
    case average
    case percentage
    case coverage
    case roadWearIndex
}

// formatValue() logic for each metric type
// - Count: Integer formatting
// - RWI: Scientific notation with normalization awareness
// - Percentage: Decimal (0.5 = 50%)
// - Coverage: Percentage with NULL count fallback
// - Average: 2 decimal places
```

**Test Requirements**:
- Verify all chart types render correctly
- Test Y-axis label generation with normalization
- Validate metric-specific formatting (RWI vs. count vs. percentage)
- Test legend rendering and series selection
- Verify export functionality

---

### 3.3 DataInspectorView (866 lines)
**Responsibility**: Right panel for detailed series inspection and data export

**Tabs**:
1. **Summary** - Overview, statistics, export buttons
2. **Data** - Tabular data view with year/value pairs
3. **Statistics** - Min/Max/Avg/StdDev calculations

**Export Functionality**:
- CSV export (year, value columns)
- Package export (.zip with metadata)
- Clipboard copy

**Test Requirements**:
- Verify all three tabs render correctly
- Test CSV export formatting
- Validate statistics calculations
- Test package export structure

---

### 3.4 ImportProgressView.swift (364 lines)
**Responsibility**: Animated progress display during imports

**Features**:
- Multi-stage progress visualization (5 stages)
- Batch progress (current file / total files)
- Detailed stage descriptions
- Completion summary

**Test Requirements**:
- Verify stage animation and progression
- Test batch import display
- Validate progress percentage calculations
- Test error state handling

---

### 3.5 RegularizationView.swift (2,176 lines)
**Responsibility**: UI for managing Make/Model regularization mappings

**Complex Features**:
- Add/edit/delete regularization mappings
- Bulk import from CSV
- Hierarchy visualization
- Mapping statistics
- Year configuration editor

**Test Requirements**:
- Verify mapping CRUD operations
- Test bulk import validation
- Validate year configuration updates
- Test hierarchy visualization accuracy

---

## 4. UTILITIES COMPONENTS

### 4.1 AppLogger.swift (200+ lines)
**Responsibility**: Centralized logging infrastructure using os.Logger

**Logger Categories** (8 total):
```swift
AppLogger.database      // Connection, schema, transactions
AppLogger.dataImport    // CSV parsing, file processing
AppLogger.query         // Query execution, optimization
AppLogger.cache         // Filter/enum cache operations
AppLogger.regularization // Make/Model mappings
AppLogger.ui            // UI events, user interactions
AppLogger.performance   // Benchmarks, timing
AppLogger.geographic    // Geographic data operations
AppLogger.app           // Lifecycle, version info
```

**Key Utilities**:
- `measureTime()` - Elapsed time tracking with logging
- `logQueryPerformance()` - Automatic performance classification
- `ImportPerformance` struct - Structured import metrics

**Test Requirements**:
- Verify all loggers initialized correctly
- Test logging output format
- Validate performance measurement accuracy

---

### 4.2 AppVersion.swift (small utility)
**Responsibility**: Build version and timestamp extraction

**Features**:
- Automatic build number (git commit count)
- Build timestamp from executable metadata
- Pre-commit hook for version updates

---

## 5. EXISTING TEST COVERAGE

### Test Files (5 total):

1. **DatabaseManagerTests.swift**
   - Database connection validation
   - Table existence checks
   - Basic query functionality
   - ~80 lines, 8-10 test methods

2. **CSVImporterTests.swift**
   - Vehicle CSV import
   - License CSV import
   - Character encoding tests
   - ~200 lines, 10+ test methods

3. **FilterCacheTests.swift**
   - Cache separation (vehicle vs. license)
   - Cache persistence
   - Data retrieval validation
   - ~150 lines, 5+ test methods

4. **WorkflowIntegrationTests.swift**
   - End-to-end import → query workflows
   - ~100 lines, 3-5 test methods

5. **UI Tests** (minimal)
   - Launch tests only
   - No functional UI tests yet

### Coverage Gaps:
- ❌ OptimizedQueryManager (no integer conversion tests)
- ❌ FilterCacheManager (new enumeration-based cache, no tests)
- ❌ RegularizationManager (critical but untested)
- ❌ CategoricalEnumManager (schema creation, no tests)
- ❌ ChartView metrics (RWI calculation, normalization)
- ❌ Data model validations (age calculation, statistics)
- ❌ Concurrent operations (race conditions, locking)
- ❌ Edge cases (NULL handling, empty results)
- ❌ Performance benchmarks (index efficiency, query plans)

---

## 6. CRITICAL TESTING PRIORITIES

### Tier 1 (Foundation - Must Have):
1. **Integer Query Path** - OptimizedQueryManager filter conversion
2. **Enumeration Table Indexes** - Performance validation (16x difference)
3. **Cache Invalidation Pattern** - invalidate() before initialize()
4. **Regularization Query Translation** - Make/Model coupling logic
5. **Normalization Pipeline** - First-year division, cumulative sum order
6. **Character Encoding** - UTF-8 fallback chain for French diacritics
7. **Data Type Awareness** - Vehicle vs. license cache loading

### Tier 2 (Functional - Should Have):
1. **RWI Calculation** - Axle-based weight distribution accuracy
2. **Percentage Metric** - Baseline query logic
3. **Coverage Analysis** - NULL field counting
4. **Hierarchical Filtering** - Make → Model dependency
5. **Year Configuration Impact** - Curated/uncurated boundaries
6. **Geographic Hierarchy** - Multi-level filtering (region → MRC → municipality)
7. **Batch Import** - File-to-file progress tracking

### Tier 3 (Robustness - Nice to Have):
1. **Concurrent Cache Refresh** - Race condition handling
2. **Large Dataset Performance** - Index effectiveness
3. **Database Migration** - Schema upgrade safety
4. **Error Recovery** - Partial import handling
5. **UI State Consistency** - Filter panel synchronization
6. **Memory Management** - Large result set handling

---

## 7. TESTING ARCHITECTURE RECOMMENDATIONS

### Test Database Strategy:
- **Test Mode Isolation**: Use `SAAQ_TEST_MODE` environment variable
- **Ephemeral Databases**: Create in temp directory, auto-cleanup
- **Sample Data Sets**:
  - Minimal (1-10 records): Basic functionality
  - Small (100-1K records): Performance validation
  - Medium (10K records): Real-world patterns
  - Large (100K+ records): Index effectiveness (separate performance suite)

### Fixture Management:
```swift
// CSV test fixtures (sample/abbreviated data)
- Vehicule_En_Circulation_2017.csv (1000 sample rows)
- Vehicule_En_Circulation_2023.csv (1000 rows with encoding anomalies)
- Permis_En_Circulation_2020.csv (1000 sample rows)

// Geographic data
- d001_test_data.txt (sample MRC/municipality hierarchy)

// Regularization test data
- regularization_mappings_test.csv (Make/Model typo samples)
```

### Concurrency Testing:
- Use `@MainActor` test helpers for UI state
- Test Swift Task spawning patterns
- Validate actor-based synchronization (ProgressTracker)
- Use weak references properly

### Performance Testing Strategy:
- Baseline: EXPLAIN QUERY PLAN analysis
- Benchmark: Execute timing for 1K/10K/100K records
- Regression: Compare across commits using Instruments signposts
- Profile: RWI calculation accuracy vs. performance

---

## 8. KNOWN ARCHITECTURAL CONSTRAINTS

### From CLAUDE.md Critical Rules:

1. **No String Columns for Categorical Data**
   - ✅ MUST use integer enumeration IDs
   - ❌ Never query on string Make/Model directly
   - Impact: Performance, index effectiveness, data consistency

2. **Enum Table ID Indexes Are Mandatory**
   - ✅ All 16 enumeration table IDs require indexes
   - Missing any: 165s → <10s performance drop
   - Tests MUST verify index presence and efficiency

3. **Cache Invalidation Pattern**
   - ✅ ALWAYS call `invalidateCache()` BEFORE `initializeCache()`
   - ❌ Guard prevents re-initialization if already initialized
   - Impact: Stale data if pattern violated

4. **No Automatic Filter State Updates**
   - ❌ NEVER use `.onChange` for filter updates
   - ✅ Use manual button triggers only
   - Reason: SwiftUI AttributeGraph circular dependency limits

5. **Background Processing for Expensive Ops**
   - ✅ Any operation >100ms must use `Task.detached`
   - ❌ Blocking UI causes beachball cursor
   - Impact: UI responsiveness, UX quality

6. **Database Path Passing for Concurrency**
   - ✅ Pass database PATHS (strings) to concurrent tasks
   - ❌ Never share OpaquePointer across tasks
   - Reason: SQLite thread safety (segfaults if violated)

7. **Parent-Scope ViewModels for Expensive Sheet Data**
   - ✅ Keep expensive ViewModels in parent scope
   - ❌ Sheet-scoped ViewModels destroyed on dismiss
   - Impact: 60+ second beachball if re-initializing on each open

---

## Summary Table: Test Coverage Matrix

| Component | Responsibility | Size | Tests | Priority | Comments |
|-----------|-----------------|------|-------|----------|----------|
| DatabaseManager | Core DB abstraction | 7.8K | Basic | Tier 1 | Singleton, many interdependencies |
| CSVImporter | CSV parsing/import | 958 | Moderate | Tier 1 | Encoding handling critical |
| FilterCacheManager | Enumeration cache | 892 | None | Tier 1 | New component, needs full coverage |
| OptimizedQueryManager | Integer queries | 1.3K | None | Tier 1 | High complexity, performance critical |
| CategoricalEnumManager | Enum tables | 787 | None | Tier 1 | Index presence validation critical |
| RegularizationManager | Make/Model mappings | 1.9K | None | Tier 1 | Coupling logic complex |
| SchemaManager | Schema migrations | 441 | None | Tier 2 | Safe to run multiple times |
| GeographicDataImporter | D001 file parsing | 378 | None | Tier 2 | Hierarchical validation |
| DataModels | Data structures | 2.1K | Minimal | Tier 2 | Model logic lightweight |
| FilterPanel | Filter UI | 2.7K | None | Tier 2 | State complexity high |
| ChartView | Visualization | 879 | None | Tier 2 | Metric formatting critical |
| DataInspectorView | Details panel | 866 | None | Tier 2 | Export functionality |
| RegularizationView | Regularization UI | 2.2K | None | Tier 3 | Complex UI state |
| AppLogger | Logging infra | ~200 | None | Tier 3 | Infrastructure, low risk |

---

## Conclusion

SAAQAnalyzer employs sophisticated data structures and query optimization patterns that require comprehensive test coverage. The integer enumeration architecture is performant but fragile—missing indexes or incorrect query patterns can cause severe (165s) performance degradation. Critical test focus areas are:

1. **Query system** (DatabaseManager, OptimizedQueryManager, FilterCacheManager)
2. **Enumeration infrastructure** (CategoricalEnumManager indexes)
3. **Data transformation** (regularization, normalization, cumulative sum)
4. **Concurrency safety** (cache locking, database connections)
5. **Character encoding** (French diacritics preservation)

Existing test infrastructure provides a foundation but lacks coverage of the most performance-sensitive components (OptimizedQueryManager, CategoricalEnumManager) and advanced features (regularization, normalization pipelines).

