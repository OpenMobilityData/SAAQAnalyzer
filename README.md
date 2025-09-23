# SAAQAnalyzer

A macOS SwiftUI application for importing, analyzing, and visualizing vehicle registration data from SAAQ (Société de l'assurance automobile du Québec).

## Features

### Data Import & Management
- **CSV Import**: Import vehicle registration CSV files with automatic encoding detection for French characters
- **Geographic Data**: Import d001 geographic reference files for municipality/region mapping
- **SQLite Database**: Efficient storage with WAL mode, indexing, and 64MB cache for optimal performance
- **Batch Processing**: Handle large datasets (77M+ records) with 1000-record batch processing
- **Import Logging**: Track import operations with success/failure status and detailed progress

### Advanced Filtering System
- **Temporal Filters**: Filter by registration years and model years
- **Geographic Filters**: Filter by administrative regions, MRCs, and municipalities
- **Vehicle Characteristics**: Filter by classification, make, model, color, fuel type, and age ranges
- **Cached Performance**: Smart caching system for instant filter option loading

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
- **Intelligent Naming**: Automatic generation of clear percentage labels like "% [Red Cars] in [All Toyota Vehicles]"

### Data Visualization
- **Interactive Charts**: Hover tooltips, zoom, and pan capabilities
- **Series Management**: Multiple data series with hide/show toggles and color coding
- **Export Options**: PNG export with proper UI appearance matching
- **Responsive Layout**: Three-panel NavigationSplitView optimized for different screen sizes

## System Requirements

- **Platform**: macOS 13.0+ (requires NavigationSplitView)
- **Architecture**: Universal (Intel and Apple Silicon)
- **Development**: Xcode 15.0+, Swift 5.9+
- **Dependencies**: SQLite3, Charts framework, UniformTypeIdentifiers

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

# Run tests
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -destination 'platform=macOS'

# Clean build folder
xcodebuild clean -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer
```

## Usage

### First Launch
1. Launch SAAQAnalyzer
2. The app will create a default SQLite database in your Documents folder
3. Import your first dataset using File → Import Vehicle CSV

### Importing Data

#### Vehicle Registration Data
1. **File Format**: CSV files named `Vehicule_En_Circulation_YYYY.csv`
2. **Data Schema**:
   - 2017+: 16 fields including fuel type
   - Pre-2017: 15 fields without fuel type
3. **Encoding**: Automatic detection (UTF-8, ISO-Latin-1, Windows-1252)
4. **Size**: Handles large files (20GB+, 77M+ records)

#### Geographic Reference Data
1. **File Format**: `d001_min.txt` format
2. **Content**: Municipality codes, names, and hierarchical relationships
3. **Purpose**: Enables proper municipality name display in filters

### Data Analysis Workflow

1. **Set Filters**: Use the left panel to select years, regions, and vehicle characteristics
2. **Choose Metrics**: Select count, sum, average, or percentage calculations
3. **Generate Charts**: Data automatically updates with interactive visualizations
4. **Compare Series**: Add multiple filter combinations as separate data series
5. **Export Results**: Save charts as PNG images for presentations

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

- **vehicles**: Main table with vehicle registration data
- **geographic_entities**: Hierarchical geographic reference data
- **import_log**: Import operation tracking and status

### Key Design Patterns

- **MVVM Architecture**: ObservableObject with @StateObject and @EnvironmentObject
- **Structured Concurrency**: Async/await throughout data layer
- **Protocol-Oriented Design**: Extensible for future data types
- **Enum-Driven UI**: Type-safe metric and filter selection

## Data Sources

SAAQAnalyzer works with public data from SAAQ (Société de l'assurance automobile du Québec):

- **Vehicle Registration Data**: Annual CSV exports of registered vehicles
- **Geographic Reference**: Municipality and region mapping files
- **Data Availability**: Multiple years of historical data
- **Update Frequency**: Annual releases

*Note: Data files are not included in this repository. Obtain them from official SAAQ sources.*

## Data Schema Documentation

Detailed documentation for SAAQ data formats is available in the `Documentation/` folder:

- **[Vehicle Registration Schema](Documentation/Vehicle-Registration-Schema.md)**: Complete field definitions, classification codes, color codes, fuel types, and geographic variables for vehicle data
- **[Driver's License Schema](Documentation/Driver-License-Schema.md)**: Comprehensive documentation for license holder demographics, license types, classes, and experience variables

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
2. Add UI components in `FilterPanel.swift`
3. Update query building in `DatabaseManager.queryVehicleData()`
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

## Troubleshooting

### Common Issues

**Import Fails with Encoding Errors**
- Try different CSV files from the same year
- Check file format matches expected schema
- Verify file isn't corrupted or truncated

**Performance Issues**
- Clear filter cache: Preferences → Clear Cache
- Restart app to reset database connections
- Check available disk space for database growth

**Chart Not Updating**
- Verify filters are properly selected
- Check that selected years have data
- Try refreshing data with different filter combinations

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

**SAAQAnalyzer** - Making Quebec vehicle registration data accessible and analyzable.