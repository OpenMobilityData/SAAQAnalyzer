# Make/Model Standardization Workflow

## Problem

The 2023-2024 SAAQ data contains massive spelling variation in vehicle make and model fields:
- **2011-2022 data**: ~11,586 unique make/model pairs (clean)
- **2023-2024 data**: ~102,372 unique make/model pairs (polluted with variants)

Example: "Volkswagen" appears as VOLK, VOLKAWAGEN, VOLKIWAGEN, VOLKS, VOLKSAWAGEN, VOLKSQWAGEN, VOLKSVAGEN, VOLKSWAGE, VOLKSWAGEB, VOLKSWAGEN, VOLKSWAGENN, VOLKSWAGGEN, VOLKSWAGON, VOLKW, VOLKWAGEN, VOLKWAGON, VOLKWASGEN, VVOLKSWAGEN, and more.

This makes filtering by make/model nearly impossible in the UI.

## Solution

Use string similarity matching to map 2023/2024 variants onto canonical 2011-2022 values, then correct the CSV files **before** importing into the database.

## Scripts

### 1. StandardizeMakeModel.swift

**Purpose**: Analyzes database to generate mapping report

**Usage**:
```bash
swift StandardizeMakeModel.swift <database_path> --analyze-only
```

**What it does**:
1. Extracts all unique make/model pairs from 2011-2022 (canonical set)
2. Extracts all unique make/model pairs from 2023-2024 (needs standardization)
3. Uses Levenshtein distance to find best matches
4. Generates markdown report with confidence scores

**Output**:
- `MakeModelStandardization-Report.md` - Detailed mapping report grouped by confidence level

**Performance**:
- ~15 minutes on 76M records (2011-2022) + 14M records (2023-2024)
- Compiled version recommended: `swiftc -O StandardizeMakeModel.swift -o StandardizeMakeModel`

### 2. ApplyMakeModelCorrections.swift

**Purpose**: Applies corrections to CSV files

**Usage**:
```bash
swift ApplyMakeModelCorrections.swift <report.md> <input.csv> <output.csv> [min_confidence]
```

**Arguments**:
- `report.md` - Mapping report from StandardizeMakeModel
- `input.csv` - Normalized CSV file (output from NormalizeCSV.swift)
- `output.csv` - Path for corrected CSV
- `min_confidence` - Optional, defaults to 0.90 (90%)

**What it does**:
1. Parses mapping report to extract corrections above confidence threshold
2. Reads CSV file and identifies MARQ_VEH and MODEL_VEH columns
3. Applies corrections to matching rows
4. Writes corrected CSV file

## Complete Workflow

### Step 1: Generate Mapping Report

Run analysis on existing database with 2011-2024 data:

```bash
cd /Users/rhoge/Desktop/SAAQAnalyzer/Scripts
swiftc -O StandardizeMakeModel.swift -o StandardizeMakeModel

./StandardizeMakeModel ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite --analyze-only
```

**Output**: Report saved to same directory as database

### Step 2: Review Report

Open the generated report and review mappings, especially:
- **Low confidence (70-74%)**: May need manual review
- **Medium confidence (75-89%)**: Generally safe, but spot check
- **High confidence (90%+)**: Very safe

Example from report:
```markdown
| VOLKSW | GOLF | → | VOLKS | GOLF | 93.0% |
| VOLKAW | JETTA | → | VOLKS | JETTA | 92.0% |
```

### Step 3: Apply Corrections to CSV Files

Apply corrections to normalized 2023 and 2024 CSV files:

```bash
# Correct 2023 data (high confidence only: 90%+)
swift ApplyMakeModelCorrections.swift \
  ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/MakeModelStandardization-Report.md \
  ~/SAAQ_Data/Vehicule_En_Circulation_2023.csv \
  ~/SAAQ_Data/Vehicule_En_Circulation_2023_corrected.csv \
  0.90

# Correct 2024 data
swift ApplyMakeModelCorrections.swift \
  ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/MakeModelStandardization-Report.md \
  ~/SAAQ_Data/Vehicule_En_Circulation_2024.csv \
  ~/SAAQ_Data/Vehicule_En_Circulation_2024_corrected.csv \
  0.90
```

### Step 4: Clean Database and Re-import

1. **Quit SAAQAnalyzer app** (important!)

2. **Delete polluted database**:
```bash
rm ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
```

3. **Restore clean 2011-2022 database** from backup:
```bash
# From .saaqpackage backup
cp ~/Downloads/SAAQData_Oct\ 2,\ 2025.saaqpackage/Contents/Database/saaq_data.sqlite \
   ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/
```

4. **Launch SAAQAnalyzer**

5. **Import corrected CSV files**:
   - Import `Vehicule_En_Circulation_2023_corrected.csv`
   - Import `Vehicule_En_Circulation_2024_corrected.csv`

6. **Verify**: Check that vehicle make filter now shows clean values (e.g., single "VOLKSWAGEN" entry instead of 17 variants)

## Confidence Levels Explained

The algorithm uses Levenshtein distance with weighted scoring:
- **Make similarity**: 70% weight (more reliable)
- **Model similarity**: 30% weight (more variable)

### Score Interpretation

- **100%**: Exact match (case-insensitive)
- **90-99%**: Very high confidence - single character differences, truncation
  - Example: "VOLKSW" → "VOLKS" (95%)
- **75-89%**: Medium confidence - minor spelling variations
  - Example: "VOLKSWAGON" → "VOLKSWAGEN" (88%)
- **70-74%**: Low confidence - requires manual review
  - May include false positives

### Adjusting Confidence Threshold

You can lower the threshold to capture more corrections:

```bash
# Include medium confidence (75%+)
swift ApplyMakeModelCorrections.swift report.md input.csv output.csv 0.75
```

**Trade-off**: Lower threshold = more corrections but higher risk of false positives

## Analysis Results

From the October 3, 2025 run:

| Metric | Value |
|--------|-------|
| Canonical pairs (2011-2022) | 11,586 |
| Non-standard pairs (2023-2024) | 102,372 |
| Total mappings generated | 67,377 |
| Exact matches | 10,843 |
| High confidence (90%+) | 15,896 |
| Medium confidence (75-89%) | 35,453 |
| Low confidence (70-74%) | 5,185 |

This represents an **88% reduction** in unique make/model pairs when high-confidence corrections are applied.

## Troubleshooting

### Issue: Script timeout
**Solution**: Use compiled version (`swiftc -O`) which is ~5-10x faster than interpreted Swift

### Issue: "Could not find MARQ_VEH column"
**Solution**: CSV file may have different column names. Check that you're using the normalized CSV output from `NormalizeCSV.swift`, which uses standard column names.

### Issue: Too many false positives
**Solution**: Increase confidence threshold:
```bash
swift ApplyMakeModelCorrections.swift report.md input.csv output.csv 0.95
```

### Issue: Missing valid corrections
**Solution**: Lower confidence threshold to 0.85 or 0.80, but review low-confidence matches manually

## Related Documentation

- `CSV-Normalization-Guide.md` - Normalizing 2023/2024 CSV structure
- `NormalizeCSV.swift` - Script for fixing column structure and encoding
- `CLAUDE.md` - Project architecture overview

## Version History

- **2025-10-03**: Initial implementation
  - Levenshtein distance algorithm
  - Weighted make/model scoring
  - Markdown report generation
  - CSV correction application
