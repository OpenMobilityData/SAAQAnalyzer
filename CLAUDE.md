# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SAAQAnalyzer is a macOS SwiftUI application designed to import, analyze, and visualize vehicle registration data from SAAQ (Société de l'assurance automobile du Québec). The application provides a three-panel interface for filtering data, displaying charts, and inspecting details.

## Development Principles

### Swift Concurrency
- **Swift version**: 6.2
- **Concurrency**: Use only modern Swift 6.2 concurrency constructs (async/await, actors, TaskGroups)
- **Avoid**: Legacy patterns (DispatchQueue, Operation, completion handlers)

### Framework Preferences
- **Avoid AppKit**: Stick to SwiftUI and Swift-native APIs whenever possible
- **NS prefix warning**: Always ask before using any AppKit/Foundation API with NS prefix (NSOpenPanel, NSSavePanel, NSAlert, etc.)
- **Prefer**: SwiftUI equivalents and modern Swift APIs

### Command Line Workflow
- **Manual execution preferred**: Generate robust command-line invocations for copy/paste into console
- **Don't auto-run**: User prefers to run scripts manually to monitor output and selectively copy results back
- **Output format**: Ensure scripts produce clear, copy-friendly output for integration into Claude Code sessions

#### Example Command Line Patterns
```bash
# Database inspection
sqlite3 ~/Library/Application\ Support/SAAQAnalyzer/saaq.db "SELECT COUNT(*) FROM vehicles;"

# CSV validation before import
head -n 5 ~/Downloads/Vehicule_En_Circulation_2023.csv

# Performance testing
time sqlite3 ~/Library/Application\ Support/SAAQAnalyzer/saaq.db "EXPLAIN QUERY PLAN SELECT..."

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

### Query Performance & Transparency System
- **Deterministic Index Analysis**: Uses `EXPLAIN QUERY PLAN` to analyze query performance before execution
- **Real-time Progress Indicators**: `SeriesQueryProgressView` shows query patterns and index usage status
- **Smart Performance Detection**: Detects table scans, temp B-trees, and other performance issues
- **Educational UI**: Progress views explain why queries are slow (limited indexing vs. optimized)
- **Console Transparency**: Detailed execution plan output for debugging and optimization
- **Query Pattern Generation**: `generateQueryPattern()` creates human-readable query descriptions
- **Performance Classification**: Automatic categorization from "Excellent" (sub-second) to "Slow" (25s+)

### Testing Framework
- XCTest framework with basic test structure in place
- Tests located in `SAAQAnalyzerTests/`

### Platform Requirements
- **Target**: macOS (no iOS support)
- **Minimum macOS version**: Requires NavigationSplitView (macOS 13.0+)
- **Dependencies**: SQLite3, Charts framework, UniformTypeIdentifiers

## Current Implementation Status

### Integer-Based Optimization (September 2024)
- **Pivoted from migration to clean implementation approach** - Building optimized schema from scratch
- **Building integer-based schema directly during CSV import** - No migration complexity
- **Using pre-assigned Quebec geographic codes** - No separate enumeration needed:
  - Municipality codes: Direct integers (e.g., 66023 for Montréal)
  - Admin Region codes: Extract from parentheses "Abitibi-Témiscamingue (08)" → 8
  - MRC codes: Extract from parentheses "Montréal (06)" → 6
- **Testing with abbreviated CSV files** (1000 rows) before scaling to full datasets
- **Database deleted for clean slate** - Starting fresh with optimized schema

### Key Architectural Components
1. **Optimized Query System**
   - `CategoricalEnumManager.swift`: Creates and manages enumeration tables
   - `OptimizedQueryManager.swift`: Integer-based queries (5.6x performance improvement)
   - `FilterCacheManager.swift`: Loads filter data from enumeration tables

2. **Geographic Code Handling**
   - Municipality codes are the only numeric codes requiring transformation to human-readable names
   - Admin regions and MRCs have embedded codes in parentheses that need extraction
   - License data only contains Admin Region and MRC (no municipalities)
   - Vehicle data contains all three levels of geographic hierarchy

3. **Special Cases**
   - **Municipalities**: Numeric codes need geographic entity name lookup for UI display
   - **License Classes**: Multiple boolean columns transformed to single multi-selectable filter
   - **Numeric Fields**: Vehicle mass and engine displacement remain as true integers (not enumerated)

### Performance Optimizations
- Integer foreign keys instead of string comparisons
- Covering indexes for common query patterns
- Direct use of Quebec's official numeric coding system
- Canonical geographic code set enables cross-mode filter persistence

## File Organization

```
SAAQAnalyzer/
├── DataLayer/          # Database and import logic
│   ├── DatabaseManager.swift
│   ├── CSVImporter.swift
│   ├── GeographicDataImporter.swift
│   ├── CategoricalEnumManager.swift    # NEW: Enumeration table management
│   ├── OptimizedQueryManager.swift     # NEW: Integer-based queries
│   └── FilterCacheManager.swift        # NEW: Enumeration-based filter cache
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
4. Add enumeration table if categorical data

### Adding New Chart Types
1. Extend `ChartType` enum in `ChartView.swift`
2. Add new case in the chart content switch statement
3. Update toolbar picker to include new option

### Database Schema Changes
1. Update table creation SQL in `DatabaseManager.createTablesIfNeeded()`
2. Update `CategoricalEnumManager` for new enumerations
3. Update import binding in `CSVImporter` to populate integer columns directly