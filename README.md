# SAAQAnalyzer

A macOS SwiftUI application for importing, analyzing, and visualizing vehicle and driver data from SAAQ (Société de l'assurance automobile du Québec).

## Table of Contents

- [Features](#features)
  - [Data Import & Storage](#data-import--storage)
  - [Filtering & Analysis](#filtering--analysis)
  - [Chart Metrics & Visualization](#chart-metrics--visualization)
  - [Advanced Analytics](#advanced-analytics)
  - [Data Quality Tools](#data-quality-tools)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
  - [Data Import](#data-import)
  - [Analysis Workflow](#analysis-workflow)
  - [Advanced Features](#advanced-features)
- [Architecture](#architecture)
- [Performance](#performance)
- [Data Sources](#data-sources)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

### Data Import & Storage

- **Dual Data Types**: Unified workflow for vehicle registration and driver license data
- **Intelligent CSV Import**: Automatic encoding detection for French characters (UTF-8, ISO-Latin-1, Windows-1252)
- **High-Performance Database**: SQLite with 32KB page size, WAL mode, and 48 composite indexes for 2-4x faster queries
- **Integer-Based Optimization**: Categorical data stored as enumeration foreign keys for 50-70% storage reduction
- **Massive Scale Support**: Handles 77M+ vehicle records and 66M+ driver records (143M+ total, 58GB+ databases)
- **Batch Processing**: Parallel workers with intelligent progress tracking for multi-file imports
- **Data Package System**: Export/import complete databases (39GB+) with all indexes and enumerations preserved

### Filtering & Analysis

- **Temporal Filtering**: Years and model years with smart age range handling
- **Geographic Filtering**: Administrative regions, MRCs, and municipalities (vehicle data)
- **Vehicle Characteristics**: Class, type, make, model, color, fuel type, and age ranges
- **Driver Demographics**: Age groups, gender, license types, classes, and experience levels
- **Data Type Aware**: Dynamic filter panels that adapt to selected data type
- **Query Performance Transparency**: Real-time index analysis and performance predictions using `EXPLAIN QUERY PLAN`
- **Smart Progress Indicators**: Shows query patterns and expected performance before execution

### Chart Metrics & Visualization

- **Multiple Chart Types**: Line, bar, and area charts using native Charts framework
- **Aggregate Metrics**:
  - **Count**: Record counts (default)
  - **Sum/Average/Min/Max**: Numeric field aggregations (mass, displacement, cylinders, age)
  - **Percentage**: Sophisticated baseline comparisons with automatic label generation
  - **Coverage**: Data completeness analysis showing NULL value patterns
- **Interactive Features**: Hover tooltips, multi-series management, hide/show toggles
- **Export**: PNG export with proper UI appearance matching

### Advanced Analytics

#### Road Wear Index (RWI)
Engineering metric based on the 4th power law for infrastructure impact analysis:

- **Vehicle-Type-Aware Weight Distribution**:
  - Cars (AU): 2 axles, 50/50 split
  - Trucks (CA) & Tool vehicles (VO): 3 axles, 30/35/35 split
  - Buses (AB): 2 axles, 35/65 split
- **Calculation Modes**: Average (per-vehicle) or Total (cumulative fleet impact)
- **Normalization Toggle**: Normalized mode (first year = 1.0) or raw values for cross-type comparison
- **Key Insight**: A vehicle 2× heavier causes 2⁴ = 16× more road wear

#### Cumulative Sum Transform
Global toggle for all metrics that transforms time series to show accumulated totals:

- **Applies To**: All metric types (Count, Average, Sum, RWI, Coverage, Percentage)
- **Use Cases**: Cumulative road damage, fleet growth, data quality improvement trends
- **Legend Display**: Automatic "Cumulative" prefix distinguishes from year-by-year values

#### Make/Model Regularization System
Correct typos and variants in uncurated data (2023-2024) using canonical values from curated data (2011-2022):

- **Smart Auto-Assignment**: Automatically assigns Make/Model pairs when only one valid option exists
- **Bidirectional Mapping**: Query expansion works both ways (canonical ↔ uncurated)
- **Status Tracking**: Visual badges show regularization completeness (Unassigned, Partial, Complete)
- **FuelType/VehicleType Disambiguation**: Handles cases where Make/Model match but fuel/vehicle type varies
- **Query-Time Translation**: Original data preserved; expansion happens during queries only

See [Regularization User Guide](Documentation/REGULARIZATION_BEHAVIOR.md) for details.

### Data Quality Tools

- **Coverage Analysis**: Analyze NULL vs non-NULL values for any field (percentage or raw count modes)
- **Field Availability Tracking**: Identify when fields were introduced (e.g., fuel_type added in 2017)
- **Encoding Fixes**: Automatic correction of common corruption patterns (Montréal vs MontrÃ©al)
- **Data Type Isolation**: Separate filter options for vehicle vs driver data prevent cross-contamination
- **Format Variant Detection**: Identifies inconsistent formatting (e.g., "Montréal(06)" vs "Montréal (06)")

## System Requirements

### Minimum Requirements
- **Platform**: macOS 26.0+ (Tahoe) - *Required for modern Swift concurrency and SwiftUI features*
- **Architecture**: Universal (Intel and Apple Silicon)
- **RAM**: 16GB - *Essential for large dataset processing*
- **Storage**: 100GB+ free space - *Database files can grow very large*
- **CPU**: 4+ cores - *For parallel CSV processing*

### Recommended Specifications
- **Platform**: macOS 26.0+ (Tahoe) or later
- **RAM**: 32GB+ - *Optimal for 77M+ record datasets*
- **Storage**: 500GB+ SSD - *Fast I/O critical for SQLite performance*
- **CPU**: Apple Silicon (M2/M3/M4) or Intel i7/i9 with 8+ cores

### Development Requirements
- **Xcode**: 26.0+ (for macOS 26.0 SDK)
- **Swift**: 6.0+
- **Dependencies**: SQLite3, Charts framework, UniformTypeIdentifiers, OSLog

### Performance Notes

**Memory Usage**:
- CSV import: 2-4GB peak during batch processing
- Database operations: 1-2GB for query processing
- UI rendering: 200-500MB for chart visualization

**Storage Requirements**:
- Raw CSV files: 15-25GB per complete vehicle dataset
- SQLite database: 12-27GB with integer optimization and 32KB page size
- Data packages: 20GB+ for complete export (143M+ records)
- Temporary files: 5-10GB during large imports

**Hardware Performance**:
- **Apple Silicon (M1/M2/M3/M4)**: Excellent performance due to unified memory and fast SSD
- **Intel Macs**: Require more RAM; benefit significantly from SSD storage

## Installation

### Prerequisites
1. macOS 26.0 (Tahoe) or later
2. Xcode 26.0+ (free from the Mac App Store)

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

### Test Dataset

A minimal test dataset is included for quick functionality testing:

- **Location**: `TestData/Vehicle_Registration_Test_1K/`
- **Contents**: 14 CSV files (2011-2024) with 1,000 records per year (~2MB total)
- **Import Time**: Seconds (14,000 records total)
- **Purpose**: Feature exploration without downloading full SAAQ datasets

See `TestData/README.md` for details.

**Note**: For production analysis and statistical significance, download full SAAQ datasets (6M+ records per year) from the [SAAQ Open Data Portal](https://www.donneesquebec.ca/recherche/dataset/vehicules-en-circulation).

### Testing

Comprehensive XCTest-based test suite covering:

- **FilterCacheTests**: Cache separation validation (vehicle/driver mode isolation)
- **DatabaseManagerTests**: Database operations and performance benchmarks
- **CSVImporterTests**: Import validation with French character encoding
- **WorkflowIntegrationTests**: End-to-end testing from import through analysis

## Quick Start

### First Launch

1. Launch SAAQAnalyzer
2. The app automatically creates:
   - SQLite database with 32KB page size
   - 16 enumeration tables for integer-based queries
   - Geographic reference data (bundled)
3. Select data type: **Vehicle** or **Driver** (toolbar selector)
4. Import your first dataset: **File → Import Vehicle CSV** or **File → Import Driver CSV**

### 5-Minute Tutorial

1. **Import test data**: File → Import Vehicle CSV → Select files from `TestData/Vehicle_Registration_Test_1K/`
2. **Set filters**: Left panel → Select years (e.g., 2020-2024)
3. **Choose metric**: Y-Axis Metric → Count (default) or explore others
4. **View results**: Chart automatically updates with data visualization
5. **Compare series**: Add multiple filter combinations to compare trends

## Usage Guide

### Data Import

#### Vehicle Data
- **File Format**: `Vehicule_En_Circulation_YYYY.csv`
- **Schema**: 16 fields (2017+) or 15 fields (pre-2017) - fuel_type added in 2017
- **Encoding**: Automatic detection (UTF-8, ISO-Latin-1, Windows-1252)
- **Size**: Handles 20GB+ files with 77M+ records

#### Driver Data
- **File Format**: CSV files with driver demographics
- **Schema**: 20 fields (age groups, gender, license types/classes/experience)
- **Geographic Data**: Human-readable region/MRC names (no d001 mapping needed)
- **Years Available**: 2011-2022 with consistent schema

#### Geographic Reference Data (Vehicle Only)
- **File Format**: `d001_min.txt`
- **Content**: Municipality codes, names, and hierarchical relationships
- **Purpose**: Maps numeric codes to human-readable names in vehicle filters

### Analysis Workflow

1. **Select Data Type**: Toolbar selector (Vehicle or Driver)
2. **Set Filters**: Left panel
   - **Vehicle**: Years, regions, vehicle class/type, make, model, color, fuel type, age ranges
   - **Driver**: Years, regions, age groups, gender, license types/classes, experience
3. **Choose Metric**: Count, Sum, Average, Min, Max, Percentage, Coverage, or Road Wear Index
4. **Generate Charts**: Data automatically updates with visualizations
5. **Compare Series**: Add multiple filter combinations as separate series
6. **Export**: Save charts as PNG images

### Advanced Features

#### Percentage Analysis
- Select **Percentage** metric type
- Choose category to use as numerator (dropdown)
- App calculates percentages against broader baseline
- Example: "% [Red] in [All Toyota Vehicles]"

#### Data Coverage Analysis
- Select **Coverage in Superset** metric
- Choose field to analyze (Fuel Type, Make, Model Year, etc.)
- Toggle modes:
  - **Percentage Mode**: % of records with non-NULL values
  - **Raw Count Mode**: Absolute number of NULL values
- Use cases: Field availability verification, data quality tracking, gap identification

#### Road Wear Index Analysis
- Select **Road Wear Index** metric
- Choose mode: Average (per-vehicle) or Sum (total fleet impact)
- Toggle normalization: Normalized (first year = 1.0) or Raw (absolute values)
- Use cases: Infrastructure planning, policy evaluation, fleet management

#### Cumulative Sum Visualization
- Enable **Show cumulative sum** toggle in Y-Axis Metric section
- Works with all metrics (Count, Average, RWI, Coverage, etc.)
- Chart legend shows "Cumulative" prefix when enabled
- Use cases: Cumulative road damage, fleet growth, data quality trends

#### Multi-Series Analysis
- Create multiple series with different filter combinations
- Toggle visibility with eye icons
- Compare trends across vehicle segments or demographics
- Automatic color coding and legend management

### Data Package Management

#### Exporting Packages
Transfer complete databases between machines:

1. Click **Export** toolbar button → "Export Data Package"
2. Save `.saaqpackage` file (20-27GB for full datasets)
3. Package includes:
   - Complete database with all records
   - 16 enumeration tables
   - 48 composite indexes
   - 32KB page size configuration

#### Importing Packages
Instant access to data without CSV processing:

1. Click **Import** toolbar button → "Import Data Package..."
2. Select `.saaqpackage` file
3. Database restored immediately with all indexes and optimizations
4. Verify: Settings → Database Statistics (check page size, record counts)

**Note**: If page size shows "4 KB", database predates 32KB optimization. Consider re-importing for 2-4x query performance improvement.

#### Test Mode
Test imports without affecting production data:

1. Xcode: Product → Scheme → Edit Scheme → Run → Environment Variables
2. Add: `SAAQ_TEST_MODE` = `1`
3. Uses `saaq_data_test.sqlite` instead of production database
4. Startup prompt: Keep existing or delete and start fresh
5. Disable variable to return to normal operation

## Architecture

### Core Components

```
SAAQAnalyzer/
├── DataLayer/          # Database and import logic
│   ├── DatabaseManager.swift          # SQLite operations with async/await
│   ├── CSVImporter.swift              # CSV parsing with encoding fixes
│   ├── GeographicDataImporter.swift   # d001 file processing
│   ├── CategoricalEnumManager.swift   # Enumeration table management
│   ├── OptimizedQueryManager.swift    # Integer-based queries (5.6x faster)
│   ├── FilterCacheManager.swift       # Enumeration-based filter cache
│   └── RegularizationManager.swift    # Make/Model/FuelType/VehicleType regularization
├── Models/             # Data structures and business logic
│   └── DataModels.swift               # Core entities and enums
├── UI/                 # SwiftUI views and components
│   ├── FilterPanel.swift              # Left panel filtering interface
│   ├── ChartView.swift                # Center panel chart display
│   └── DataInspector.swift            # Right panel data details
├── Utilities/          # Shared infrastructure
│   └── AppLogger.swift                # Centralized logging (os.Logger)
└── SAAQAnalyzerApp.swift             # Main app entry point
```

### Database Schema

- **vehicles**: Vehicle data (15-16 fields, year-dependent schema)
- **licenses**: Driver data (20 fields with demographics and license details)
- **geographic_entities**: Hierarchical geographic reference (vehicle data only)
- **import_log**: Import operation tracking for both data types
- **canonical_hierarchy_cache**: Materialized cache for regularization (109x speedup)
- **16 enumeration tables**: year_enum, make_enum, model_enum, fuel_type_enum, vehicle_class_enum, vehicle_type_enum, color_enum, cylinder_count_enum, axle_count_enum, model_year_enum, admin_region_enum, mrc_enum, municipality_enum, age_group_enum, gender_enum, license_type_enum

### Key Design Patterns

- **MVVM Architecture**: ObservableObject with @StateObject and @EnvironmentObject
- **Structured Concurrency**: Async/await throughout data layer (Swift 6.0)
- **Generic Data Infrastructure**: Unified handling of vehicle and driver data with type routing
- **Protocol-Oriented Design**: Shared interfaces for common fields across data types
- **Enum-Driven UI**: Type-safe metric and filter selection

## Performance

### Query Performance Optimizations

**Municipality-Based Queries**: Achieved **7.7x performance improvement**:

| Optimization Stage | Query Time | Improvement | Cumulative Gain |
|-------------------|------------|-------------|-----------------|
| Baseline (no optimization) | 160.3s | - | - |
| Strategic composite indexes | 77.7s | 2.1x faster | 2.1x |
| SQLite ANALYZE statistics | **20.8s** | 3.7x faster | **7.7x total** |

**Example**: Montreal electric passenger car analysis: 160s → 20s

### Apple Silicon Optimizations

**Aggressive database configuration** for Mac Studio M3 Ultra and similar systems:

- **32KB Page Size**: Automatically set on new databases for 2-4x query performance
- **8GB SQLite Cache**: Leverages unified memory architecture
- **32GB Memory Mapping**: Maps majority of database into RAM
- **16-Thread Processing**: Utilizes all efficiency and performance cores
- **48 Composite Indexes**: Optimized for common query patterns
- **Integer-Based Queries**: Enumeration joins replace string comparisons (5-6x speedup)

### Database Optimization Strategy

- **Strategic Indexing**: Composite indexes for typical patterns:
  - Municipality queries: `(geo_code, classification, year)`
  - Fuel type analysis: `(year, fuel_type, classification)`
  - Regional analysis: `(year, admin_region, classification)`
- **Query Planner Intelligence**: `ANALYZE` command updates statistics for optimal index selection
- **Parallel Processing**: Concurrent execution for percentage calculations (numerator + baseline)

### Performance by System Tier

#### High Performance (Recommended)
- **Mac Studio M3 Ultra** or equivalent (24-core CPU, 96GB+ RAM)
- **Expected Performance**: 20s for complex municipality queries
- **Memory Usage**: ~40GB active (8GB cache + 32GB mmap)

#### Standard Performance
- **Apple Silicon Macs** (M1/M2/M3/M4 with 32GB+ RAM)
- **Expected Performance**: 30-60s for complex queries
- **Memory Usage**: Scaled to available RAM

#### Minimum Performance
- **Intel Macs** or **Apple Silicon with 16GB RAM**
- **Expected Performance**: 60-120s for complex queries
- **Limitations**: Reduced cache sizes, no memory mapping

### Performance Monitoring

Real-time query timing in console:
```
🚀 Vehicle query completed in 20.785s - 6 data points
📊 Raw vehicle query completed in 8.442s - 12 data points
⚡ Parallel percentage queries completed in 26.757s
```

## Data Sources

SAAQAnalyzer works with public data from SAAQ (Société de l'assurance automobile du Québec):

- **Vehicle Data**: Annual CSV exports of registered vehicles (2009-2024)
- **Driver Data**: Annual CSV exports of driver demographics (2011-2022)
- **Geographic Reference**: Municipality and region mapping files (vehicle data)
- **Data Portal**: [SAAQ Open Data Portal](https://www.donneesquebec.ca/recherche/dataset/vehicules-en-circulation)
- **Update Frequency**: Annual releases

**Data Schema Documentation**:
- [Vehicle Schema](Documentation/Vehicle-Registration-Schema.md): Field definitions, classification codes, color codes, fuel types
- [Driver Schema](Documentation/Driver-License-Schema.md): Demographics, license types, classes, experience variables

*Note: Data files are not included in this repository. Obtain from official SAAQ sources.*

## Troubleshooting

### Common Issues

**Import Fails with Encoding Errors**
- Try different CSV files from the same year
- Verify file format matches expected schema
- Check file isn't corrupted or truncated

**Performance Issues**
- Verify page size: Settings → Database Statistics → should show "32 KB"
- If showing "4 KB": Import new data package with 32KB pages for 2-4x improvement
- Check available disk space (32KB pages use ~15% more space but query much faster)
- Restart app to reset database connections
- Monitor console for query timing and index usage

**Chart Not Updating**
- Verify filters are properly selected
- Check selected years have data
- Use Coverage metric to verify field availability (e.g., fuel_type NULL pre-2017)

**NULL Values and Missing Years**
- Not all fields available in all years (e.g., fuel_type added in 2017)
- SQL automatically excludes NULL values in filters
- Use **Coverage metric** to analyze field availability patterns
- Visual chart gaps may indicate NULL fields rather than zero counts

### Debug Information

- **Console Logs**: Detailed import progress and query timing
- **Database Statistics**: Settings panel shows:
  - Record counts (vehicles and licenses)
  - Page size (4 KB legacy or 32 KB optimized)
  - Database file size
  - Available years, regions, municipalities
- **Query Performance**: Console output with execution plans and timing

## Contributing

### Development Setup
1. Fork the repository
2. Create feature branch: `git checkout -b feature/new-feature`
3. Follow existing code style and patterns
4. Add tests for new functionality
5. Ensure builds pass: `xcodebuild build`
6. Submit pull request

### Code Style
- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add documentation for public APIs
- Maintain existing architectural patterns

### Adding New Features

#### New Filter Types
1. Update `FilterConfiguration` in `DataModels.swift`
2. Add UI components in `FilterPanel.swift`
3. Update query building in `DatabaseManager` (`queryVehicleData` or `queryLicenseData`)
4. Add enumeration table if categorical data

#### New Chart Types
1. Extend `ChartType` enum in `ChartView.swift`
2. Add case in chart content switch statement
3. Update toolbar picker

#### New Metrics
Follow Road Wear Index pattern (see CLAUDE.md for detailed implementation guide)

## License

This project is available under the MIT License. See the LICENSE file for details.

## Acknowledgments

- Built with SwiftUI and the Charts framework
- Uses SQLite for efficient data storage
- Designed for SAAQ vehicle registration and driver license data analysis
- Developed with Claude Code assistance

## Support

For bug reports and feature requests, please use the GitHub Issues page.

---

**SAAQAnalyzer** - Making Quebec vehicle and driver data accessible and analyzable.
