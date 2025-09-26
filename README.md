# SAAQAnalyzer

A macOS SwiftUI application for importing, analyzing, and visualizing vehicle and driver data from SAAQ (Société de l'assurance automobile du Québec).

## Features

### Data Import & Management
- **Dual Data Types**: Support for both vehicle and driver data with unified workflow
- **CSV Import**: Import CSV files with automatic encoding detection for French characters
- **Data Type Switching**: Seamless switching between vehicle and driver data analysis modes
- **SQLite Database**: Efficient storage with WAL mode, indexing, and 64MB cache for optimal performance
- **Batch Processing**: Handle large datasets (77M+ records) with 50K-record batch processing and parallel workers
- **Import Progress**: Real-time progress indication with detailed stage tracking and indexing updates
- **Data Package Export/Import**: Transfer complete databases (39GB+) between machines without re-processing
- **Cache Preservation**: Export and import filter caches to bypass lengthy rebuild times

### Advanced Filtering System
- **Temporal Filters**: Filter by years and model years (vehicle data)
- **Geographic Filters**: Filter by administrative regions, MRCs, and municipalities (vehicle-only)
- **Vehicle Characteristics**: Filter by classification, make, model, color, fuel type, and age ranges
- **Driver Demographics**: Filter by age groups, gender, license types, classes, and experience levels
- **Data Type Aware**: Dynamic filter panels that adapt based on selected data type
- **Separate Cache System**: Independent caches for vehicle and driver data prevent cross-contamination
- **Cached Performance**: Smart caching system for instant filter option loading with persistent versioning
- **Mode-Specific Options**: Filter lists show only values present in the currently selected data type

### Flexible Chart System
- **Multiple Chart Types**: Line charts, bar charts, and area charts using native Charts framework
- **Dynamic Y-Axis Metrics**:
  - **Count**: Number of vehicles (default)
  - **Sum**: Total values (mass, displacement, cylinders, etc.)
  - **Average**: Mean values with smart decimal formatting
  - **Percentage**: Sophisticated percentage calculations with baseline comparisons
- **Smart Formatting**: Automatic K/M abbreviations, unit handling, and mixed-metric support

### Percentage Analysis
- **Baseline Calculations**: Compare filtered data against broader baselines
- **Category Dropping**: Select which filter category to use as numerator vs. baseline
- **Percentage in Superset**: Clear terminology for percentage calculations showing proportion within larger dataset
- **Intelligent Naming**: Automatic generation of clear percentage labels like "% [Red Cars] in [All Toyota Vehicles]"

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
- SQLite database: 25-40GB with indexes for full datasets
- Data packages: 39GB+ for complete export (77M+ vehicle + 66M+ driver records)
- Cache files: 50-100MB (stored in UserDefaults)
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
   - Create a unified SQLite database with separate tables for vehicles and licenses
   - Import bundled geographic reference data (no manual setup required)
   - Build separate filter caches for vehicle and driver data to prevent cross-contamination
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
2. **Choose Location**: Select where to save the `.saaqpackage` file (39GB+ for full datasets)
3. **Package Contents**:
   - Complete SQLite database with all records
   - Vehicle and driver filter caches
   - Metadata and statistics
4. **Transfer**: Copy the package file to another machine via external drive or network

#### Importing Data Packages
Import a data package to instantly access all data without processing:

1. **Import Package**: Click Import toolbar button → "Import Data Package..."
2. **Select Package**: Choose the `.saaqpackage` file
3. **Automatic Setup**: Database and caches are restored immediately
4. **Ready to Use**: All data available without hours of processing

#### Quick Import Mode (Cache Bypass)
If cache loading is slow on startup, use either method to bypass:

**Method 1: Option Key (End Users)**
1. **Quit the Application** if running
2. **Hold Option Key** (⌥) while launching SAAQAnalyzer
3. **Bypass Confirmation**: You'll see "Cache loading bypassed via Option key" alert
4. **Import Immediately**: Import data package without waiting for cache rebuild

**Method 2: Environment Variable (Developers/Xcode)**
1. **In Xcode**: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
2. **Add Variable**: Name: `SAAQ_BYPASS_CACHE`, Value: `1`
3. **Run from Xcode**: Cache loading will be bypassed automatically
4. **Terminal Launch**: `SAAQ_BYPASS_CACHE=1 open -a SAAQAnalyzer`

**Use Cases**: Testing, development, corrupted cache recovery, quick package imports

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

### Cache Architecture

- **Separate Cache Storage**: Independent cache keys for vehicle and driver data (e.g., `vehicleYears` vs `licenseYears`)
- **Mode-Specific Validation**: Cache validation ensures data type isolation and prevents cross-contamination
- **Targeted Cache Management**: Clear vehicle or driver caches independently without affecting the other data type
- **Performance Optimization**: Parallel cache loading with instant filter option availability

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

- **Database**: SQLite with WAL mode, indexes, and 64MB cache
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

## Troubleshooting

### Common Issues

**Import Fails with Encoding Errors**
- Try different CSV files from the same year
- Check file format matches expected schema
- Verify file isn't corrupted or truncated

**Performance Issues**
- Clear specific cache: Use Settings to clear vehicle or driver cache independently
- Clear all caches: Preferences → Development → Clear Cache options
- Restart app to reset database connections and rebuild caches automatically
- Check available disk space for database growth
- Use cache bypass: Hold ⌥ while launching or set `SAAQ_BYPASS_CACHE=1` environment variable to skip cache loading

**Chart Not Updating**
- Verify filters are properly selected
- Check that selected years have data
- Try refreshing data with different filter combinations

**License Class Filtering Issues**
- License class filters now use proper display names (e.g., "1-2-3-4", "Learner 1-2-3")
- System handles multi-license holders correctly with OR logic
- Rebuild driver cache if experiencing filter inconsistencies

### Debug Information
- Console logs provide detailed import progress
- Database statistics available in app status
- Filter cache information shows loading performance

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