# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SAAQAnalyzer is a macOS SwiftUI application designed to import, analyze, and visualize vehicle registration data from SAAQ (Société de l'assurance automobile du Québec). The application provides a three-panel interface for filtering data, displaying charts, and inspecting details.

## Build and Development Commands

```bash
# Build the project (use Xcode)
xcodebuild -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -configuration Debug build

# Run tests
xcodebuild test -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer -destination 'platform=macOS'

# Clean build folder
xcodebuild clean -project SAAQAnalyzer.xcodeproj -scheme SAAQAnalyzer
```

**Primary development environment**: Xcode IDE is required for iOS/macOS Swift development. Open `SAAQAnalyzer.xcodeproj` in Xcode to build and run the application.

## Architecture Overview

### Core Components

1. **Data Layer** (`DataLayer/`)
   - `DatabaseManager.swift`: SQLite database operations with async/await patterns
   - `CSVImporter.swift`: Handles importing SAAQ CSV files with encoding fixes for French characters
   - `GeographicDataImporter.swift`: Imports d001 geographic reference files

2. **Models** (`Models/`)
   - `DataModels.swift`: Core data structures including VehicleRegistration, GeographicEntity, FilterConfiguration, and enums for classifications

3. **UI Layer** (`UI/`)
   - `FilterPanel.swift`: Left panel with hierarchical filtering (years, geography, vehicle types, fuel types, age ranges)
   - `ChartView.swift`: Center panel with Charts framework integration (line, bar, area charts)
   - `DataInspector.swift`: Right panel for detailed data inspection

4. **Main App**
   - `SAAQAnalyzerApp.swift`: App entry point with three-panel NavigationSplitView layout

### Database Schema

- **vehicles**: Main table storing vehicle registration data (16 fields for 2017+, 15 for earlier years)
- **geographic_entities**: Hierarchical geographic data (regions, MRCs, municipalities)
- **import_log**: Tracks import operations and success/failure status

### Key Design Patterns

- **MVVM Architecture**: ObservableObject pattern with @StateObject and @EnvironmentObject
- **Async/await**: Database operations use structured concurrency
- **Three-panel layout**: NavigationSplitView with filters, charts, and details
- **Batch processing**: CSV imports processed in 1000-record batches for performance

## Data Import Process

### File Types
- **Vehicle CSV files**: Named pattern `Vehicule_En_Circulation_YYYY.csv`
- **Geographic d001 files**: `d001_min.txt` format for municipality/region mapping

### Character Encoding
The CSV importer handles French characters by trying multiple encodings (UTF-8, ISO-Latin-1, Windows-1252) and includes fixes for common encoding corruption patterns like "Montréal" → "MontrÃ©al".

### Data Validation
- Schema validation based on year (fuel type field available 2017+)
- Duplicate detection using UNIQUE constraint on (year, vehicle_sequence)
- Import logging tracks success/failure rates

## UI Framework and Components

- **SwiftUI**: Modern declarative UI framework
- **Charts framework**: Native charting with line, bar, and area chart types
- **AppKit integration**: Uses NSOpenPanel, NSSavePanel, NSAlert for file operations
- **NavigationSplitView**: Three-column responsive layout

## Development Notes

### Performance Considerations
- SQLite WAL mode enabled for concurrent reads
- Indexes on year, classification, geographic fields, and fuel_type
- 64MB cache size for database operations
- Batch processing for large imports

### Testing Framework
- XCTest framework with basic test structure in place
- Tests located in `SAAQAnalyzerTests/`

### Platform Requirements
- **Target**: macOS (no iOS support)
- **Minimum macOS version**: Requires NavigationSplitView (macOS 13.0+)
- **Dependencies**: SQLite3, Charts framework, UniformTypeIdentifiers

## File Organization

```
SAAQAnalyzer/
├── DataLayer/          # Database and import logic
├── Models/             # Data structures and enums
├── UI/                # SwiftUI views and components
├── Assets.xcassets/   # App icons and colors
└── SAAQAnalyzerApp.swift   # Main app entry point
```

## Common Tasks

### Adding New Filter Types
1. Update `FilterConfiguration` struct in `DataModels.swift`
2. Add UI components in `FilterPanel.swift`
3. Update query building in `DatabaseManager.queryVehicleData()`

### Adding New Chart Types
1. Extend `ChartType` enum in `ChartView.swift`
2. Add new case in the chart content switch statement
3. Update toolbar picker to include new option

### Database Schema Changes
1. Update table creation SQL in `DatabaseManager.createTablesIfNeeded()`
2. Add migration logic if needed for existing databases
3. Update import binding in `CSVImporter` and `DatabaseManager.importVehicleBatch()`