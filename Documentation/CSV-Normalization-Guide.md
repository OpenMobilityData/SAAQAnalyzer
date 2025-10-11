# CSV Normalization Guide

## Overview

The SAAQ provided vehicle registration data for 2023-2024 in a **non-standard format** that differs from the 2011-2022 open data portal files. The `NormalizeCSV.swift` script transforms these files into the standard format expected by SAAQAnalyzer.

## Format Differences: 2023-2024 vs Standard

### Standard Format (2011-2022)
- **Delimiter**: Comma (`,`)
- **Encoding**: UTF-8
- **Column Names**: English (e.g., `MARQ_VEH`, `MODEL_VEH`, `REG_ADM`)
- **Year Format**: `YYYY` (e.g., `2023`)
- **Geographic Data**: Region codes in standard "Name (##)" format
- **Field Count**: 16 fields (for 2017+)

### Non-Standard Format (2023-2024)
- **Delimiter**: Semicolon (`;`)
- **Encoding**: ISO-8859-1 with UTF-8 corruption (e.g., `Montréal` → `MontrÃ©al`)
- **Column Names**: French with encoding issues (e.g., `Marque du vÈhicule (fabricant)`)
- **Year Format**: `YYYYMM` (e.g., `202312` for December 2023)
- **Geographic Data**: Municipality names (text) and numeric region codes
- **Field Count**: 7 fields (many standard fields missing)

### Missing Fields in 2023-2024 Data

The following fields are not present in the 2023-2024 files and will be left empty after normalization:

- `CLAS` - Vehicle classification
- `TYP_VEH_CATEG_USA` - US vehicle category type
- `MASSE_NETTE` - Net vehicle mass
- `NB_CYL` - Number of cylinders
- `CYL_VEH` - Engine displacement
- `NB_ESIEU_MAX` - Maximum number of axles
- `COUL_ORIG` - Original color
- `TYP_CARBU` - Fuel type
- `MRC` - MRC (Regional County Municipality) code

## Script Usage

### Basic Syntax

```bash
swift NormalizeCSV.swift <input.csv> <output.csv> [year] [d001_path]
```

### Parameters

1. **input.csv** (required): Path to the non-standard SAAQ CSV file
2. **output.csv** (required): Path where normalized file will be written
3. **year** (optional): Explicit year (e.g., `2023`). If omitted, extracted from data
4. **d001_path** (optional): Path to d001 geographic reference file. Required for municipality code lookups

### Example Usage

#### With d001 file (recommended)
```bash
swift /Users/rhoge/Desktop/SAAQAnalyzer/Scripts/NormalizeCSV.swift \
  ~/SAAQ_Data/Vehicule_En_Circulation_2023_original.csv \
  ~/SAAQ_Data/Vehicule_En_Circulation_2023.csv \
  2023 \
  ~/SAAQAnalyzer/SAAQAnalyzer/Resources/d001_min.txt
```

#### Without d001 file
```bash
swift /Users/rhoge/Desktop/SAAQAnalyzer/Scripts/NormalizeCSV.swift \
  ~/SAAQ_Data/Vehicule_En_Circulation_2024_original.csv \
  ~/SAAQ_Data/Vehicule_En_Circulation_2024.csv \
  2024
```

**Note**: Without the d001 file, municipality codes (`CG_FIXE`) will not be populated, and municipalities will not appear in the SAAQAnalyzer UI filters.

## Normalization Process

The script performs the following transformations:

### 1. Encoding Detection and Fixes

- Tries multiple encodings: UTF-8 → ISO-8859-1 → Windows CP1252
- Fixes UTF-8 corruption when read as ISO-8859-1:
  - `Ã©` → `é`
  - `Ã¨` → `è`
  - `Ã` → `à`
  - And other common French character corruptions

### 2. Delimiter Detection

Automatically detects whether the file uses semicolon (`;`) or comma (`,`) delimiters by analyzing the header line.

### 3. Year Extraction

Extracts 4-digit year from `YYYYMM` format:
- `202312` → `2023`
- `202406` → `2024`

### 4. Geographic Lookups

When d001 file is provided:

1. **Loads 1,227 municipalities** from d001 with their numeric codes
2. **Normalizes municipality names** to pure ASCII (strips accents) for robust matching
3. **Maps municipality names to codes**:
   - Source: `"Montréal"` (text)
   - Normalized: `"montreal"` (lowercase, no accents)
   - Result: `66023` (numeric code)

**Example mappings:**
- Montréal → 66023
- Québec → 23027
- Gatineau → 81017
- Laval → 65005

### 5. Region Normalization

Converts numeric region codes to standard "Name (##)" format:
- `6` → `Montréal (06)`
- `7` → `Outaouais (07)`
- `3` → `Capitale-Nationale (03)`

### 6. Unique Sequence Generation

Generates unique `NOSEQ_VEH` identifiers:
- Format: `YYYY_##########`
- Example: `2023_0000000001`, `2023_0000000002`, etc.
- **Critical**: Prevents duplicate key violations in database

## Output Format

The normalized file contains 16 comma-delimited fields with proper CSV quoting:

```
"AN","NOSEQ_VEH","CLAS","TYP_VEH_CATEG_USA","MARQ_VEH","MODEL_VEH","ANNEE_MOD","MASSE_NETTE","NB_CYL","CYL_VEH","NB_ESIEU_MAX","COUL_ORIG","TYP_CARBU","REG_ADM","MRC","CG_FIXE"
"2023","2023_0000000001","","","MAZDA","CX5","2016","","","","","","","Outaouais (07)","","81017"
"2023","2023_0000000002","","","HONDA","CIVIC","2018","","","","","","","Montréal (06)","","66023"
```

### Field Mapping

| Standard Field | Source Field (2023-2024) | Notes |
|----------------|--------------------------|-------|
| AN | `Année civile / mois` | Extracted 4-digit year |
| NOSEQ_VEH | (generated) | Unique sequence per record |
| CLAS | - | Empty (not in source) |
| TYP_VEH_CATEG_USA | - | Empty (not in source) |
| MARQ_VEH | `Marque du véhicule (fabricant)` | Vehicle make |
| MODEL_VEH | `Modèle du véhicule` | Vehicle model |
| ANNEE_MOD | `Année du modèle du véhicule` | Model year |
| MASSE_NETTE | - | Empty (not in source) |
| NB_CYL | - | Empty (not in source) |
| CYL_VEH | - | Empty (not in source) |
| NB_ESIEU_MAX | - | Empty (not in source) |
| COUL_ORIG | - | Empty (not in source) |
| TYP_CARBU | - | Empty (not in source) |
| REG_ADM | `Région admin (code)` | Mapped to "Name (##)" format |
| MRC | - | Empty (not in source) |
| CG_FIXE | `Municipalité (description)` | Looked up via d001 file |

## Performance

- **Test files** (1,000 records): ~1 second
- **Full files** (~6 million records): ~10-15 minutes
- Progress updates printed every 10,000 records

## Troubleshooting

### Issue: "Failed to read input file"
**Solution**: File may be using an unsupported encoding. The script tries UTF-8, ISO-8859-1, and Windows CP1252 automatically.

### Issue: Only 2 records importing (duplicate key error)
**Solution**: This indicates the normalization script generated duplicate `NOSEQ_VEH` values. Re-run the normalization script with the latest version that includes `recordNumber` parameter.

### Issue: Municipalities not showing in UI
**Solution**: Ensure you provided the d001 file path as the 4th parameter. Without it, municipality codes cannot be looked up.

### Issue: Montreal or other major cities missing codes
**Solution**: The script includes comprehensive encoding fixes and ASCII normalization. If you modified the script, ensure:
1. `fixEncoding()` is called on each data line
2. `stripAccents()` is applied during normalization
3. Lookup is case-insensitive (via `.lowercased()`)

### Issue: "Field count mismatch" warnings
**Solution**: The source file may have inconsistent formatting. Check for:
- Unquoted fields containing delimiters
- Line breaks within quoted fields
- Inconsistent number of columns

## Script Location

```
/Users/rhoge/Desktop/SAAQAnalyzer/Scripts/NormalizeCSV.swift
```

## Technical Details

### Character Encoding Strategy

The script handles multiple encoding scenarios:

1. **ISO-8859-1 reading**: Preferred for 2023-2024 files
2. **UTF-8 corruption detection**: Identifies and fixes `Ã©` patterns
3. **ASCII normalization**: Strips accents for lookups (`é` → `e`)

This three-layer approach ensures robust handling of French characters regardless of how the source file was encoded.

### Municipality Lookup Algorithm

```swift
1. Load d001 file (ISO-8859-1 encoding)
2. Parse fixed-width fields:
   - Code: positions 2-6 (e.g., "66023")
   - Name: positions 9-66 (e.g., "Montréal")
3. Normalize names:
   - Lowercase: "montréal"
   - Strip accents: "montreal"
4. Build dictionary: "montreal" → GeographicEntity(code: "66023", ...)
5. For each CSV record:
   - Extract municipality name
   - Normalize it
   - Look up in dictionary
   - Write code to CG_FIXE field
```

### Why ASCII Normalization Works

Quebec has ~1,200 municipalities with unique names. Stripping accents does not create ambiguities:
- Montréal → montreal (unique)
- Saint-Jérôme → saint-jerome (unique)
- Trois-Rivières → trois-rivieres (unique)

The normalization makes lookups resilient to encoding variations without sacrificing accuracy.

## Related Documentation

- **Database Schema**: `Vehicle-Registration-Schema.md`
- **Project Overview**: `CLAUDE.md`
- **Import Process**: See `CSVImporter.swift`

## Version History

- **2025-01-10**: Initial version supporting 2023-2024 non-standard format
- Added geographic lookup via d001 file
- Added encoding corruption fixes
- Added ASCII normalization for robust matching
