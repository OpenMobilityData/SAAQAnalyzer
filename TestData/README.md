# Test Data

This directory contains minimal test datasets for basic functionality testing and exploration of SAAQAnalyzer.

## Vehicle Registration Test Data (1K)

**Location**: `Vehicle_Registration_Test_1K/`

**Description**: Minimal vehicle registration dataset with 1,000 records per year for quick testing and demonstration purposes.

**Contents**:
- 14 CSV files covering years 2011-2024
- 1,000 vehicle registration records per file
- Total size: ~2MB
- Import time: Seconds (ideal for quick testing)

**Files**:
```
Vehicule_En_Circulation_2011.csv  (1,000 rows)
Vehicule_En_Circulation_2012.csv  (1,000 rows)
Vehicule_En_Circulation_2013.csv  (1,000 rows)
Vehicule_En_Circulation_2014.csv  (1,000 rows)
Vehicule_En_Circulation_2015.csv  (1,000 rows)
Vehicule_En_Circulation_2016.csv  (1,000 rows)
Vehicule_En_Circulation_2017.csv  (1,000 rows)
Vehicule_En_Circulation_2018.csv  (1,000 rows)
Vehicule_En_Circulation_2019.csv  (1,000 rows)
Vehicule_En_Circulation_2020.csv  (1,000 rows)
Vehicule_En_Circulation_2021.csv  (1,000 rows)
Vehicule_En_Circulation_2022.csv  (1,000 rows)
Vehicule_En_Circulation_2023.csv  (1,000 rows)
Vehicule_En_Circulation_2024.csv  (1,000 rows)
```

## Purpose

This test dataset allows developers and users to:

1. **Quick Functionality Testing**: Import and analyze data in seconds without waiting for full dataset processing
2. **Feature Exploration**: Test filters, charts, metrics, and data inspector with real SAAQ data structure
3. **Development Workflow**: Validate changes without large data imports
4. **Onboarding**: New users can quickly understand the application's capabilities
5. **CI/CD Testing**: Small enough for automated test scenarios

## Usage

### Importing Test Data

1. **Launch SAAQAnalyzer**
2. **Select Import Vehicle Data** from the menu or toolbar
3. **Navigate** to the `TestData/Vehicle_Registration_Test_1K/` directory
4. **Select one or more CSV files** to import
5. **Import completes in seconds** (14,000 records total if importing all years)

### What You Can Test

With this minimal dataset, you can explore:

- **Filtering**: Years, geographic regions, vehicle types, fuel types, age ranges
- **Chart Visualization**: Line charts, bar charts, area charts
- **Metrics**:
  - Count (vehicle registrations)
  - Sum/Average/Min/Max (mass, displacement, cylinders, age, model year)
  - Percentage (filtered subset vs. baseline)
  - Coverage (data completeness analysis)
  - Road Wear Index (RWI) with normalization and cumulative sum options
- **Data Inspector**: Detailed record examination and field coverage
- **Regularization System**: Make/Model/Fuel Type/Vehicle Type corrections (limited scope with 1K records)

## Limitations

This is a **minimal test dataset** with intentional limitations:

- **Sample Size**: Only 1,000 records per year (full SAAQ dataset has ~6M records per year)
- **Geographic Coverage**: May not include all municipalities/regions
- **Vehicle Diversity**: Limited representation of rare makes/models/types
- **Statistical Significance**: Not suitable for production analysis or policy decisions

**Use Case**: Development, testing, and exploration only. For production analysis, import the full SAAQ dataset.

## Data Source

These files are derived from the official SAAQ (Société de l'assurance automobile du Québec) vehicle registration open data, truncated to 1,000 rows per year for testing purposes.

**Full Dataset Available At**:
- [SAAQ Open Data Portal](https://www.donneesquebec.ca/recherche/dataset/vehicules-en-circulation)

## Schema Reference

For complete field definitions and data structure, see:
- `Documentation/Vehicle-Registration-Schema.md`

---

**Note**: This test data is included in the repository for convenience. The full SAAQ dataset must be downloaded separately from the official open data portal for production use.
