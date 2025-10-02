# SAAQAnalyzer

A macOS SwiftUI application for importing, analyzing, and visualizing vehicle and driver data from SAAQ (Société de l'assurance automobile du Québec).

## Features

### Data Import & Management
- **Dual Data Types**: Support for both vehicle and driver data with unified workflow
- **CSV Import**: Import CSV files with automatic encoding detection for French characters
- **Integer-Based Optimization**: Categorical data stored as integer foreign keys for 50-70% storage reduction and faster queries
- **Enumeration Tables**: On-the-fly population of lookup tables during import for instant string-to-ID mapping
- **Data Type Switching**: Seamless switching between vehicle and driver data analysis modes
- **SQLite Database**: Efficient storage with WAL mode, strategic indexing, and aggressive performance optimizations
- **32KB Page Size**: New databases automatically configured with optimal 32KB page size for 2-4x query performance improvement
- **Batch Processing**: Handle large datasets (77M+ records) with intelligent batch processing and parallel workers
- **Batch Import Progress**: Comprehensive multi-file import tracking with file-by-file progress, "Preparing import..." instant feedback, and total elapsed time reporting
- **Enumeration-Based Cache**: Filter options loaded from database enumeration tables, eliminating cache rebuild overhead
- **Data Package Export/Import**: Transfer complete databases (39GB+) with enumeration tables intact - no recomputation needed
- **Instant Package Import**: Imported packages are immediately query-ready with all indexes and enumerations preserved

### Advanced Filtering System
- **Temporal Filters**: Filter by years and model years (vehicle data)
- **Geographic Filters**: Filter by administrative regions, MRCs, and municipalities (vehicle-only)
- **Vehicle Characteristics**: Filter by classification, make, model, color, fuel type, and age ranges
- **Driver Demographics**: Filter by age groups, gender, license types, classes, and experience levels
- **Data Type Aware**: Dynamic filter panels that adapt based on selected data type
- **Enumeration-Based Filters**: Filter options loaded directly from database enumeration tables for instant availability
- **No Cache Rebuild**: Filter data always synchronized with database, no separate cache refresh needed
- **Mode-Specific Options**: Filter lists show only values present in the currently selected data type

### Query Performance & Transparency
- **Deterministic Index Analysis**: Real-time analysis of SQLite execution plans before query execution
- **Progress Indicators**: Transparent progress views showing actual query patterns and expected performance
- **Query Pattern Display**: Shows exact filter combinations being queried (e.g., "Vehicle • MRCs: Montréal • Classifications: PAU")
- **Index Usage Detection**: Automatically detects whether queries will use optimized indexes or require table scans
- **Performance Classification**: Queries categorized as "Using optimized index" or "Limited indexing - may take longer"
- **Console Transparency**: Detailed execution plan output with performance metrics (time, data points, index usage)
- **Smart Predictions**: Uses `EXPLAIN QUERY PLAN` to accurately predict query performance before execution
- **Educational Feedback**: Clear explanations of why queries are slow (missing indexes, temp B-trees, etc.)

### Flexible Chart System
- **Multiple Chart Types**: Line charts, bar charts, and area charts using native Charts framework
- **Dynamic Y-Axis Metrics**:
  - **Count**: Number of vehicles (default)
  - **Sum**: Total values (mass, displacement, cylinders, etc.)
  - **Average**: Mean values with smart decimal formatting
  - **Minimum**: Minimum values for numeric fields
  - **Maximum**: Maximum values for numeric fields
  - **Percentage**: Sophisticated percentage calculations with baseline comparisons
  - **Coverage**: Data quality analysis showing NULL value statistics (see Data Coverage Analysis below)
- **Smart Formatting**: Automatic K/M abbreviations, unit handling, and mixed-metric support

### Percentage Analysis
- **Baseline Calculations**: Compare filtered data against broader baselines
- **Category Dropping**: Select which filter category to use as numerator vs. baseline
- **Percentage in Superset**: Clear terminology for percentage calculations showing proportion within larger dataset
- **Intelligent Naming**: Automatic generation of clear percentage labels like "% [Red Cars] in [All Toyota Vehicles]"

### Data Coverage Analysis
- **Coverage in Superset Metric**: Analyze data completeness and NULL value patterns across years
- **Field Selection**: Choose any categorical field to analyze (Fuel Type, Vehicle Make, Model Year, etc.)
- **Dual Display Modes**:
  - **Percentage Mode**: Shows % of records with non-NULL values (data coverage rate)
  - **Raw Count Mode**: Shows absolute count of NULL values per year
- **Toggle Control**: Easy switch between percentage and count views
- **Quality Monitoring**: Track data completeness trends over time
- **Field Availability Insights**: Identify when new fields were introduced (e.g., Fuel Type from 2017)
- **Use Cases**:
  - Verify field availability before analysis
  - Track data quality improvements over time
  - Identify incomplete records requiring cleanup
  - Understand temporal data collection changes

### Data Visualization
- **Interactive Charts**: Hover tooltips, zoom, and pan capabilities
- **Series Management**: Multiple data series with hide/show toggles and color coding
- **Export Options**: PNG export with proper UI appearance matching
- **Responsive Layout**: Three-panel NavigationSplitView optimized for different screen sizes

## System Requirements

### Minimum Requirements
- **Platform**: macOS 13.0+ (Ventura) - *Required for NavigationSplitView*
- **Architecture**: Universal (Intel and Apple Silicon)
- **RAM**: 16GB - *Essential for large dataset processing*
- **Storage**: 100GB+ free space - *Database files can grow very large*
- **CPU**: 4+ cores - *For parallel CSV processing and cache operations*

### Recommended Specifications
- **Platform**: macOS 14.0+ (Sonoma) or later
- **RAM**: 32GB+ - *Optimal for 77M+ record datasets*
- **Storage**: 500GB+ SSD - *Fast I/O critical for SQLite performance*
- **CPU**: 8+ cores (Apple M2/M3 or Intel i7/i9) - *Significant performance boost*

### Development Requirements
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **Dependencies**: SQLite3, Charts framework, UniformTypeIdentifiers

### Performance Considerations

**Memory Usage:**
- CSV import: 2-4GB peak during batch processing
- Database operations: 1-2GB for query processing
- Cache building: 500MB-1GB depending on data size
- UI rendering: 200-500MB for chart visualization

**Storage Requirements:**
- Raw CSV files: 15-25GB per complete vehicle dataset
- SQLite database: 12-27GB with integer-based optimization and 32KB page size
- Data packages: 20GB+ for complete export (77M+ vehicle + 66M+ driver records)
- Enumeration tables: Included in database, no separate cache files needed
- Temporary files: 5-10GB during large imports

**Hardware Notes:**
- **Apple Silicon (M1/M2/M3)**: Excellent performance due to unified memory architecture and fast SSD I/O
- **Intel Macs**: Require more RAM due to discrete memory architecture; benefit significantly from SSD storage

## Installation

### Prerequisites
1. Install Xcode from the Mac App Store
2. Ensure macOS 13.0 or later

### Building from Source
```bash
# Clone the repository
git clone https://github.com/yourusername/SAAQAnalyzer.git
cd SAAQAnalyzer

# Open in Xcode
open SAAQAnalyzer.xcodeproj

# Build and run (⌘+R)
```

### Build Commands
```bash
# Build the project
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -configuration Debug build

# Run comprehensive test suite
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -destination 'platform=macOS'

# Clean build folder
xcodebuild clean -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer
```

### Testing

SAAQAnalyzer includes a comprehensive XCTest-based test suite covering:

- **FilterCacheTests**: Cache separation validation, preventing cross-contamination between vehicle/driver modes
- **DatabaseManagerTests**: Database operations, performance benchmarks, and query validation
- **CSVImporterTests**: CSV import validation with French character encoding and Quebec data patterns
- **WorkflowIntegrationTests**: End-to-end testing from import through analysis with mode switching
- **Performance Testing**: Prevents regression to expensive 66M+ record database scans

## Usage

### First Launch
1. Launch SAAQAnalyzer
2. The app will automatically:
   - Create a unified SQLite database with 32KB page size for optimal performance
   - Create 15 enumeration tables for integer-based queries
   - Import bundled geographic reference data (no manual setup required)
   - Load filter options directly from enumeration tables (no cache rebuild needed)
3. Use the data type selector in the toolbar to choose between Vehicle or Driver data
4. Import your first dataset using File → Import Vehicle CSV or File → Import Driver CSV

### Importing Data

#### Vehicle Data
1. **File Format**: CSV files named `Vehicule_En_Circulation_YYYY.csv`
2. **Data Schema**:
   - 2017+: 16 fields including fuel type
   - Pre-2017: 15 fields without fuel type
3. **Encoding**: Automatic detection (UTF-8, ISO-Latin-1, Windows-1252)
4. **Size**: Handles large files (20GB+, 77M+ records)

#### Driver Data
1. **File Format**: CSV files with driver demographics and license information
2. **Data Schema**: 20 fields including age groups, gender, license types, classes, and experience
3. **Geographic Data**: Human-readable region and MRC names (no d001 mapping required)
4. **Years Available**: 2011-2022 data with consistent schema across years
5. **Import Process**: Uses same parallel processing and progress indication as vehicle data

#### Geographic Reference Data (Vehicle Data Only)
1. **File Format**: `d001_min.txt` format
2. **Content**: Municipality codes, names, and hierarchical relationships
3. **Purpose**: Enables proper municipality name display in vehicle data filters
4. **Note**: Not required for driver data as geographic names are already human-readable

### Data Package Management

#### Exporting Data Packages
Data packages allow you to transfer complete databases between machines without re-importing CSVs:

1. **Export Package**: Click Export toolbar button → "Export Data Package"
2. **Choose Location**: Select where to save the `.saaqpackage` file (20-27GB for full datasets)
3. **Package Contents**:
   - Complete SQLite database with all records and enumeration tables
   - 32KB page size configuration preserved
   - All 48 indexes for optimal query performance
   - Metadata and statistics
4. **Transfer**: Copy the package file to another machine via external drive or network
5. **Performance**: Fast export leveraging optimized database structure

#### Importing Data Packages
Import a data package to instantly access all data without processing:

1. **Import Package**: Click Import toolbar button → "Import Data Package..."
2. **Select Package**: Choose the `.saaqpackage` file
3. **Automatic Setup**: Database with enumeration tables restored immediately
4. **No Recomputation**: Enumeration tables already populated, filter options instantly available
5. **Ready to Query**: All indexes and optimizations preserved, full performance immediately
6. **Verification**: Check Settings → Database Statistics to confirm page size and record counts

#### Database Statistics Verification
After importing a data package, verify the import in Settings → Database Statistics:

- **Vehicle Records**: Confirm total record count matches source
- **License Records**: Verify driver data imported correctly
- **Page Size**: Should show "32 KB" for optimal performance (older databases may show "4 KB")
- **Database Size**: Check total database size
- **Last Updated**: Confirm import timestamp

Note: If page size shows "4 KB", the database was created before the 32KB optimization. Consider re-importing from CSV or a newer data package for 2-4x query performance improvement.

### Test Mode for Safe Import Testing

Test mode allows you to test data package imports on a separate test database without affecting your production data:

**Setup**:
1. **In Xcode**: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
2. **Add Variable**: Name: `SAAQ_TEST_MODE`, Value: `1`
3. **Enable**: Check the checkbox to activate test mode
4. **Run**: Launch the app from Xcode

**Behavior**:
- Uses `saaq_data_test.sqlite` instead of production `saaq_data.sqlite`
- Test database gets 32KB page size automatically on creation
- On startup with existing test database, prompts:
  - **Keep Existing**: Continue with current test data
  - **Delete and Start Fresh**: Remove test database and start clean
- Import operations write to test database only
- Production database remains completely untouched
- Disable `SAAQ_TEST_MODE` to return to normal operation
- Filter options load from test database enumeration tables

**Use Cases**: Testing package imports, validating enumeration tables, testing 32KB page size benefits, development without production data risk

### Data Analysis Workflow

1. **Select Data Type**: Use the toolbar selector to choose Vehicle or Driver data
2. **Set Filters**: Use the left panel to select years, regions, and data-specific characteristics:
   - **Vehicle Data**: Classification, make, model, color, fuel type, age ranges
   - **Driver Data**: Age groups, gender, license types, classes, experience levels
3. **Choose Metrics**: Select count, sum, average, or percentage calculations
4. **Generate Charts**: Data automatically updates with interactive visualizations
5. **Compare Series**: Add multiple filter combinations as separate data series
6. **Export Results**: Save charts as PNG images for presentations

### Advanced Features

#### Percentage Analysis
- Select "Percentage" as your metric type
- Choose which filter category to use as the numerator
- The app automatically calculates percentages against the appropriate baseline
- Example: "% [Red] in [All Toyota Vehicles]" shows red cars as percentage of all Toyota vehicles

#### Data Coverage Analysis
- Select "Coverage in Superset" as your metric type
- Choose a field to analyze from the dropdown menu (e.g., Fuel Type, Vehicle Make, Model Year)
- Toggle between two display modes:
  - **Percentage Mode (default)**: Shows what % of records have non-NULL values for that field
  - **Raw Count Mode**: Shows the absolute number of NULL values per year
- Use this to:
  - Verify field availability across different years
  - Track data quality trends over time
  - Identify when new fields were introduced to the dataset
  - Understand gaps in your data before running analyses
- Example: Analyzing Fuel Type coverage will show 0% for pre-2017 years and ~100% for 2017+ years, confirming that field was added in 2017

#### Multi-Series Analysis
- Create multiple data series with different filter combinations
- Toggle series visibility with eye icons
- Compare trends across different vehicle segments
- Automatic color coding and legend management

## Architecture

### Core Components

```
SAAQAnalyzer/
├── DataLayer/          # Database and import logic
│   ├── DatabaseManager.swift      # SQLite operations with async/await
│   ├── CSVImporter.swift          # CSV parsing with encoding fixes
│   └── GeographicDataImporter.swift   # d001 file processing
├── Models/             # Data structures and business logic
│   ├── DataModels.swift           # Core entities and enums
│   └── FilterCache.swift          # Performance caching system
├── UI/                # SwiftUI views and components
│   ├── FilterPanel.swift          # Left panel filtering interface
│   ├── ChartView.swift            # Center panel chart display
│   └── DataInspector.swift        # Right panel data details
└── SAAQAnalyzerApp.swift         # Main app entry point
```

### Database Schema

- **vehicles**: Vehicle data with 15-16 fields (year-dependent schema)
- **licenses**: Driver data with 20 fields including demographics and license details
- **geographic_entities**: Hierarchical geographic reference data (for vehicle data only)
- **import_log**: Import operation tracking and status for both data types

### Filter Cache Architecture

- **Enumeration Table-Based**: Filter options loaded directly from database enumeration tables (make_enum, model_enum, etc.)
- **No Separate Cache**: Eliminated UserDefaults-based caching, filter data always synchronized with database
- **Instant Availability**: Filter options available immediately on app launch from enumeration tables
- **Data Type Aware**: Filter queries automatically route to appropriate enumeration tables based on data type
- **Always Fresh**: No cache invalidation needed, enumeration tables updated during import

### Key Design Patterns

- **MVVM Architecture**: ObservableObject with @StateObject and @EnvironmentObject
- **Structured Concurrency**: Async/await throughout data layer
- **Generic Data Infrastructure**: Unified handling of multiple data types with type routing
- **Protocol-Oriented Design**: Shared interfaces for common fields across data types
- **Enum-Driven UI**: Type-safe metric and filter selection with data-aware components

## Data Sources

SAAQAnalyzer works with public data from SAAQ (Société de l'assurance automobile du Québec):

- **Vehicle Data**: Annual CSV exports of registered vehicles (2009-2022)
- **Driver Data**: Annual CSV exports of driver demographics (2011-2022)
- **Geographic Reference**: Municipality and region mapping files (for vehicle data)
- **Data Availability**: Multiple years of historical data for both data types
- **Update Frequency**: Annual releases

*Note: Data files are not included in this repository. Obtain them from official SAAQ sources.*

## Data Schema Documentation

Detailed documentation for SAAQ data formats is available in the `Documentation/` folder:

- **[Vehicle Schema](Documentation/Vehicle-Registration-Schema.md)**: Complete field definitions, classification codes, color codes, fuel types, and geographic variables for vehicle data
- **[Driver Schema](Documentation/Driver-License-Schema.md)**: Comprehensive documentation for driver demographics, license types, classes, and experience variables

These documents provide essential reference information for understanding the data structure, valid values, and relationships between fields.

## Contributing

### Development Setup
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Follow the existing code style and patterns
4. Add tests for new functionality
5. Ensure builds pass: `xcodebuild build`
6. Submit a pull request

### Code Style
- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add documentation for public APIs
- Maintain existing architectural patterns

### Adding New Features

#### New Filter Types
1. Update `FilterConfiguration` in `DataModels.swift`
2. Add UI components in `FilterPanel.swift` (consider data type compatibility)
3. Update query building in `DatabaseManager.queryVehicleData()` or `queryLicenseData()`
4. Add caching support in `FilterCache.swift`

#### New Chart Types
1. Extend `ChartType` enum in `ChartView.swift`
2. Add new case in chart content switch statement
3. Update toolbar picker to include new option

## Performance

SAAQAnalyzer is optimized for high-performance analysis of massive datasets (58GB+ databases, 143M+ records) on modern Apple Silicon systems.

### Query Performance Optimizations

**Municipality-Based Queries**: Achieved **7.7x performance improvement** through strategic database optimizations:

| Optimization Stage | Query Time | Improvement | Cumulative Gain |
|-------------------|------------|-------------|-----------------|
| Baseline (no optimization) | 160.3s | - | - |
| Strategic composite indexes | 77.7s | 2.1x faster | 2.1x |
| SQLite ANALYZE statistics | **20.8s** | 3.7x faster | **7.7x total** |

**Example**: Montreal electric passenger car analysis improved from nearly 3 minutes to 20 seconds.

### Apple Silicon Optimizations

**Aggressive Database Configuration** for Mac Studio M3 Ultra and similar systems:
- **32KB Page Size**: Automatically set on new databases for 2-4x query performance (vs default 4KB)
- **8GB SQLite Cache**: Leverages unified memory architecture
- **32GB Memory Mapping**: Maps majority of database into RAM
- **16-Thread Processing**: Utilizes all efficiency and performance cores
- **Smart Index Strategy**: 48 composite indexes for common query patterns
- **Integer-Based Queries**: Enumeration table joins replace string comparisons for 5-6x speedup

### Database Optimizations

- **Strategic Indexing**: Composite indexes designed for typical query patterns:
  - Municipality queries: `(geo_code, classification, year)`
  - Fuel type analysis: `(year, fuel_type, classification)`
  - Regional analysis: `(year, admin_region, classification)`
- **Query Planner Intelligence**: ANALYZE command updates statistics for optimal index selection
- **Parallel Processing**: Concurrent execution for percentage calculations (numerator + baseline)
- **Smart Year Filtering**: Dynamic year constraints based on data availability

### System Requirements by Performance Level

#### **High Performance (Recommended)**
- **Mac Studio M3 Ultra** or equivalent (24-core CPU, 96GB+ RAM)
- **Expected Performance**: 20s for complex municipality queries
- **Memory Usage**: ~40GB active (8GB cache + 32GB mmap)

#### **Standard Performance**
- **Apple Silicon Macs** (M1/M2/M3 with 32GB+ RAM)
- **Expected Performance**: 30-60s for complex queries
- **Memory Usage**: Scaled to available RAM

#### **Minimum Performance**
- **Intel Macs** or **Apple Silicon with 16GB RAM**
- **Expected Performance**: 60-120s for complex queries
- **Limitations**: Reduced cache sizes, no memory mapping

### Performance Monitoring

Real-time query timing available in console:
```
🚀 Vehicle query completed in 20.785s - 6 data points
📊 Raw vehicle query completed in 8.442s - 12 data points
⚡ Parallel percentage queries completed in 26.757s
```

### Memory Architecture Benefits

**Apple Silicon Unified Memory** provides significant advantages:
- **Direct Memory Mapping**: Database pages shared between CPU and GPU
- **No Memory Copy Overhead**: Unified memory eliminates data transfer bottlenecks
- **Massive Cache Utilization**: 8GB SQLite cache leverages high-bandwidth memory

### Legacy Performance Notes

- **Database**: SQLite with WAL mode, comprehensive indexing, and adaptive caching
- **Import Speed**: 1000-record batches with parallel processing
- **UI Responsiveness**: Cached filter options and async data loading
- **Memory Usage**: Optimized for large datasets with streaming processing

## Data Quality and Formatting

SAAQAnalyzer includes built-in data quality monitoring that helps identify formatting inconsistencies in SAAQ data files.

### Filter Duplicate Detection and Data-Type Awareness

The application uses a **data-type-aware filtering system** that shows only values present in the currently selected data type, while maintaining complete transparency about data quality issues within each dataset.

**How it works**:
- **Vehicle Mode**: Shows only admin regions, MRCs, and other geographic values present in vehicle data
- **Driver Mode**: Shows only values present in driver data, including formatting variations found within that dataset

**Admin Region Formatting Example**:
When analyzing driver data, you may see both "Montréal(06)" and "Montréal (06)" in the Admin Region filter. This indicates:
- Driver data from different years uses inconsistent formatting (with/without space before parentheses)
- Both formats represent the same geographic region but exist as separate values in the driver dataset
- You should select both options to ensure complete coverage of Montreal drivers
- Vehicle data will show only the formatting variant(s) present in vehicle records

**Key Benefits**:
- **Data Type Isolation**: Vehicle analysis isn't contaminated by driver data formatting issues, and vice versa
- **Quality Transparency**: All formatting variations within the selected data type remain visible
- **Complete Coverage**: Users can select all format variants to ensure comprehensive results
- **No Data Loss**: All imported data remains accessible and analyzable

**Best Practices**:
1. **Switch data types to see different perspectives**: Vehicle vs. driver data may have different geographic coverage and formatting
2. **Select all format variants** within your chosen data type to ensure complete results
3. **Review filter options** when switching between vehicle and driver modes to identify data-specific formatting issues
4. **Monitor console output** during imports for data quality warnings

### Encoding and Character Handling

The application automatically handles French character encoding issues:
- Tries multiple encodings (UTF-8, ISO-Latin-1, Windows-1252)
- Fixes common corruption patterns (Ã, Â characters)
- Maintains data integrity across different source file encodings

### Field Availability and NULL Values

**Important**: Not all fields are available in all years of SAAQ data. The most notable example is **fuel type**, which was only added to vehicle records starting in 2017.

**How NULL values are handled**:

1. **Database Storage**:
   - Pre-2017 vehicle records: `fuel_type_id = NULL`
   - 2017+ vehicle records: `fuel_type_id` contains valid enumeration IDs

2. **Query Behavior**:
   - When filtering by fuel type, SQL automatically excludes NULL values
   - Pre-2017 years simply don't appear in results when fuel type filter is applied
   - This is standard SQL behavior: `WHERE field_id IN (...)` excludes NULL values

3. **Chart Display**:
   - Charts only plot years that appear in query results
   - Missing years create visual gaps in the timeline
   - **Cannot distinguish** between:
     - Field not available (NULL in database)
     - Field available but no matching records (true zero)

**Analyzing Field Availability with Coverage Metric**:

Use the **Coverage in Superset** metric to analyze field availability patterns:

1. **Select Coverage Metric**: Choose "Coverage in Superset" from Y-Axis Metric options
2. **Choose Field**: Select the field you want to analyze (e.g., Fuel Type)
3. **View Results**:
   - **Percentage Mode**: Shows data coverage rate (0% = all NULL, 100% = no NULLs)
   - **Raw Count Mode**: Shows absolute number of NULL values per year
4. **Interpret Gaps**: A sudden jump from 0% to 100% coverage indicates when a field was introduced

**Example Scenarios**:

- **Query**: Gasoline vehicles (2011-2022)
  - **Result**: Chart shows only 2017-2022 (fuel type field didn't exist before 2017)
  - **Appearance**: Visual gap from 2011-2016
  - **Verification**: Use Coverage metric on Fuel Type to confirm 0% coverage pre-2017

- **Query**: Electric vehicles in Montreal
  - **Result**: Some years may show zero data points
  - **Could mean**: Either no EVs in Montreal that year (true zero) OR field was NULL
  - **Verification**: Check Coverage metric to distinguish between NULL field vs. no matching records

**Best Practices**:
1. **Use Coverage Metric First**: Before analyzing a field, check its coverage across years
2. **Identify Field Introduction**: Look for coverage jumps indicating when fields were added
3. **Filter Appropriately**: Use year filters to focus on periods with complete data
4. **Track Data Quality**: Monitor coverage trends to identify incomplete data periods
5. **Understand Gaps**: Visual chart gaps may indicate NULL fields rather than zero counts

**Future fields**: If SAAQ adds new fields in future years, they will behave the same way (NULL for older years, actual values for newer years). The Coverage metric will help identify these changes.

## Troubleshooting

### Common Issues

**Import Fails with Encoding Errors**
- Try different CSV files from the same year
- Check file format matches expected schema
- Verify file isn't corrupted or truncated

**Performance Issues**
- Verify page size: Check Settings → Database Statistics for "32 KB" (optimal) vs "4 KB" (legacy)
- For 4KB databases: Import a new data package with 32KB pages for 2-4x performance improvement
- Check available disk space for database growth (32KB pages use ~15% more space but query much faster)
- Restart app to reset database connections
- Monitor console for query timing and index usage information

**Chart Not Updating**
- Verify filters are properly selected
- Check that selected years have data
- Try refreshing data with different filter combinations

**License Class Filtering Issues**
- License class filters now use proper display names (e.g., "1-2-3-4", "Learner 1-2-3")
- System handles multi-license holders correctly with OR logic

### Debug Information
- Console logs provide detailed import progress and query timing
- Database statistics available in Settings panel:
  - Total record counts for vehicles and licenses
  - Page size (4 KB legacy or 32 KB optimized)
  - Database file size
  - Available years, regions, municipalities
- Query performance metrics in console output

## License

This project is available under the MIT License. See the LICENSE file for more details.

## Acknowledgments

- Built with SwiftUI and the Charts framework
- Uses SQLite for efficient data storage
- Designed for SAAQ vehicle registration data analysis
- Developed with Claude Code assistance

## Support

For bug reports and feature requests, please use the GitHub Issues page.

---

**SAAQAnalyzer** - Making Quebec vehicle and driver data accessible and analyzable.