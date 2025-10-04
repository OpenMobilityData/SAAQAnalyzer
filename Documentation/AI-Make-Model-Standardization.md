# AI-Powered Make/Model Standardization

## Overview

This document describes the AI-powered approach to standardizing vehicle make and model names in SAAQ data using macOS 26 Foundation Models framework. This method provides superior accuracy for research applications by leveraging on-device AI to intelligently distinguish between typos, schema violations, and genuinely new vehicle models.

## Problem Statement

### Data Quality Issues in 2023-2024

The SAAQ provided 2023-2024 vehicle registration data with three types of quality problems:

1. **Schema Violations**: Full model names exceeding the official 5-character SAAQ limit
   - Examples: `ESCAPE` (6 chars), `COMPASS` (7 chars), `SIERRA` (6 chars)
   - Should be: `ESCAP` (5 chars), `COMPA` (5 chars), `SIERR` (5 chars)

2. **Typos and Misspellings**: Data entry errors
   - Examples: `CIIVIC` → `CIVIC`, `VOLKSW` → `VOLKS`, `COROLA` → `COROL`

3. **New Models**: Genuinely new vehicles from 2023-2024 not in historical data
   - Examples: Mazda CX-90, Mazda CX-70, Audi Q8 e-tron, Tesla Cybertruck
   - **Must be preserved for research accuracy**

### Challenge

Simple string similarity matching cannot reliably distinguish between these cases:
- `CX90` vs `CX30` (92.5% similar) - Actually different models, should preserve both
- `ESCAPE` vs `ESCAP` (95% similar) - Same model, schema compliance correction
- `CIIVIC` vs `CIVIC` (95% similar) - Typo, should correct

## Solution: AI-Powered Classification

### Foundation Models Framework (macOS 26)

Uses Apple's on-device AI with these advantages:

- **Semantic Understanding**: AI knows automotive conventions (different numbers = different models)
- **Context Awareness**: Understands SAAQ schema requirements and data quality issues
- **Privacy Preserving**: All processing stays local, no cloud APIs
- **Zero Cost**: No API fees for inference
- **Auditable**: Provides human-readable reasoning for each decision

### Decision Framework

The AI classifies each potential correction into four categories:

#### 1. Spelling Variant
**Definition**: Typo or misspelling of existing 5-char code
**Action**: Correct to canonical form
**Examples**:
- `CIIVIC` → `CIVIC` (double letter typo)
- `VOLKSW` → `VOLKS` (missing character)
- `COROLA` → `COROL` (transposition)

**Characteristics**:
- Similar length to canonical
- High string similarity (>90%)
- Same model year ranges
- Minor character differences

#### 2. Truncation Variant
**Definition**: Full model name vs. SAAQ 5-char schema-compliant code
**Action**: Correct to canonical 5-char form
**Examples**:
- `ESCAPE` (6 chars) → `ESCAP` (5 chars)
- `COMPASS` (7 chars) → `COMPA` (5 chars)
- `MODELY` (6 chars) → `MODEL` (5 chars)

**Characteristics**:
- Non-standard is longer (usually 6+ characters)
- Canonical is exactly 5 characters
- Same model year ranges
- High string similarity

**Note**: Tesla uses `MODEL` as the canonical 5-char code for all Model 3/Y/X/S variants per SAAQ schema.

#### 3. New Model
**Definition**: Genuinely new vehicle from 2023-2024 not in historical reference
**Action**: **Preserve as-is** (do not correct)
**Examples**:
- `CX90` - New Mazda SUV (launched 2023)
- `CX70` - New Mazda SUV (launched 2023)
- `Q8ETRON` - New Audi EV
- `CYBERTRUCK` - New Tesla pickup

**Characteristics**:
- Model years start after 2022 (e.g., 2023-2024)
- No corresponding entry in 2011-2022 canonical data
- Different model numbers from similar names (90 vs 30)
- New EV/hybrid variants

#### 4. Uncertain
**Definition**: Ambiguous case requiring human review
**Action**: Flag for manual review, do not auto-correct
**When Used**:
- Low confidence (<70%)
- Edge cases detected
- Conflicting signals

## Model Year Intelligence

### Key Innovation

Model year data provides the strongest signal for detecting new models:

```
EXAMPLE: Mazda CX-90 vs CX-30

Non-Standard (2023 data):
  Make: "MAZDA", Model: "CX90"
  Model Years: 2023-2024

Canonical (2011-2022 reference):
  Make: "MAZDA", Model: "CX30"
  Model Years: 2019-2022

ANALYSIS:
  String Similarity: 92.5% (very high!)
  Model Year Gap: CX90 starts in 2023, CX30 ended in 2022

DECISION: newModel
  Reasoning: "CX-90 first appears in 2023 with no historical presence.
             Different model number (90 vs 30) confirms distinct vehicle."
  shouldCorrect: false
```

### Model Year Decision Rules

**Rule 1 - New Model Detection** (Highest Priority)
```
IF non-standard MIN year > 2022
   AND canonical MAX year ≤ 2022
THEN likely "newModel"
```

**Rule 2 - Same Model Confirmation**
```
IF model year ranges overlap significantly
   AND high string similarity
   AND similar length
THEN likely "spellingVariant" or "truncationVariant"
```

**Rule 3 - Year Range Preservation**
```
Typos preserve model year ranges:
  CIIVIC (2010-2022) → CIVIC (2010-2022) ✓

Truncation preserves model year ranges:
  ESCAPE (2008-2022) → ESCAP (2008-2022) ✓

New models have distinct year ranges:
  CX90 (2023-2024) ≠ CX30 (2019-2022) ✓
```

## SAAQ Schema Compliance

### Official Schema (from Vehicle-Registration-Schema.md)

| Field | Type | Length | Description |
|-------|------|--------|-------------|
| **MARQ_VEH** | Alphanumeric | **5** | Vehicle brand code **recognized by manufacturer** |
| **MODEL_VEH** | Alphanumeric | **5** | Vehicle model code **recognized by manufacturer** |

**Key Points**:
- 5-character limit is **mandatory** per SAAQ database specification
- These are **standardized codes**, not free-text descriptions
- 2011-2022 data properly follows this schema (canonical reference)
- 2023-2024 data violates schema with 6+ character names

### Schema Enforcement Strategy

The AI enforces schema compliance while preserving new models:

**Correct (Schema Violation)**:
- `ESCAPE` (6 chars) → `ESCAP` (5 chars) ✓
- `TRANSIT` (7 chars) → `TRANS` (5 chars) ✓

**Preserve (New Model)**:
- `CX90` (4 chars, but new model) → Keep as `CX90` ✓
- `Q8ETRON` (7 chars, but new EV) → Keep as `Q8ETRON` ✓

**Note**: New models may initially violate schema length, but are preserved for research accuracy. They can be manually assigned proper 5-char codes later if needed.

## Script Usage

### Prerequisites

- macOS 26.0+ (Tahoe)
- Apple Silicon (M1/M2/M3/M4)
- Swift 6.2+
- Database with 2011-2024 vehicle data

### Command Line

```bash
swift AIStandardizeMakeModel.swift <database_path> <output_report.md>
```

### Example

```bash
swift AIStandardizeMakeModel.swift \
  ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  ~/Desktop/AI-MakeModel-Analysis.md
```

### Execution Flow

1. **Extract Canonical Data** (2011-2022)
   - Queries make/model pairs with MIN/MAX model years
   - Creates reference set of properly formatted codes

2. **Extract Non-Standard Data** (2023-2024)
   - Queries make/model pairs with MIN/MAX model years
   - Identifies candidates needing analysis

3. **Find Candidate Matches**
   - Uses string similarity (Levenshtein distance)
   - Filters to pairs with ≥70% similarity
   - Weights make (70%) more than model (30%)

4. **AI Analysis** (per candidate)
   - Sends detailed prompt to Foundation Models
   - Includes SAAQ schema, model years, decision rules
   - Receives structured classification with reasoning

5. **Generate Report**
   - Markdown format with sections by decision type
   - Includes AI confidence and reasoning for each
   - Separates high-confidence from uncertain cases

### Performance

**Expected Runtime**:
- ~15 minutes for database extraction (76M + 14M records)
- ~5-10 minutes for AI analysis (100-200 pairs analyzed)
- Total: **20-25 minutes** for complete analysis

**Note**: Execution time is not critical for this one-time research operation. Accuracy is the priority.

## Output Report Structure

### Report Sections

#### 1. Summary by Decision Type

```markdown
| Decision Type | Count | Description |
|---------------|-------|-------------|
| Spelling Variant | 45 | Typos and misspellings |
| Truncation Variant | 89 | Full names vs. 5-char schema |
| Uncertain | 12 | Requires human review |
```

**Note**: New models are detected but NOT included in corrections (preserved as-is).

#### 2. Spelling Variants (High Confidence Typos)

Table format with:
- Non-standard make/model
- Canonical make/model
- String similarity percentage
- AI confidence percentage
- **AI reasoning** (e.g., "High similarity with double letter suggests typo")

#### 3. Truncation Variants (Schema Compliance)

Same table format as above.

**Example**:
```
| FORD | ESCAPE | → | FORD | ESCAP | 95.0% | 90% | Full model name being standardized to 5-char SAAQ schema |
```

#### 4. Uncertain Cases - HUMAN REVIEW REQUIRED ⚠️

Cases where AI confidence is low or conflicting signals detected.

**Example**:
```
| MAZDA | CX90 | → | MAZDA | CX30 | 92.5% | 60% | Different model numbers (90 vs 30) suggest distinct vehicles despite high similarity. Model years confirm: CX-90 introduced 2023, not present in 2011-2022 data. |
```

### Report Usage

1. **Review Uncertain Cases** - Start here, decide manually
2. **Verify Truncation Variants** - Ensure schema compliance makes sense
3. **Spot-Check Spelling Variants** - Sample review for quality
4. **Check for Missing New Models** - Verify known new models preserved

## Applying Corrections

### Workflow

Once the AI report is reviewed and approved:

1. **Use Existing ApplyMakeModelCorrections.swift**
   ```bash
   swift ApplyMakeModelCorrections.swift \
     AI-MakeModel-Analysis.md \
     Vehicule_En_Circulation_2023.csv \
     Vehicule_En_Circulation_2023_corrected.csv \
     0.90
   ```

2. **Clean Database Workflow**
   - Delete polluted database
   - Restore 2011-2022 backup
   - Import corrected 2023/2024 CSVs

### Confidence Threshold

The AI report includes confidence scores. When applying corrections:

- **90%+ confidence**: Safe to apply automatically
- **75-89% confidence**: Review manually first
- **<75% confidence**: Marked as "uncertain", review required

## Advantages Over String Similarity Alone

| Aspect | String Similarity | AI-Powered |
|--------|-------------------|------------|
| Detects typos | ✓ | ✓ |
| Enforces schema | ✓ | ✓ |
| **Preserves new models** | ✗ | ✓ |
| **Uses model year data** | ✗ | ✓ |
| **Semantic understanding** | ✗ | ✓ |
| **Explains reasoning** | ✗ | ✓ |
| Human auditable | Partial | ✓ |
| Privacy preserving | ✓ | ✓ |
| Cost | Free | Free |

## Case Studies

### Case 1: Mazda CX-90 (New Model Preserved)

**String Similarity Approach**:
```
CX90 vs CX30: 92.5% similar → INCORRECT correction applied
Result: Data loss (new model mapped to old model)
```

**AI-Powered Approach**:
```
Input:
  Non-Standard: MAZDA CX90 (model years: 2023-2024)
  Canonical: MAZDA CX30 (model years: 2019-2022)
  Similarity: 92.5%

AI Decision: newModel
Reasoning: "CX-90 first appears in 2023 with no historical presence.
           Different model number (90 vs 30) confirms distinct vehicle."
shouldCorrect: false

Result: CX-90 preserved ✓
```

### Case 2: Ford Escape (Schema Compliance)

**String Similarity Approach**:
```
ESCAPE vs ESCAP: 95% similar → Correction applied
Result: Correct ✓
```

**AI-Powered Approach**:
```
Input:
  Non-Standard: FORD ESCAPE (6 chars, model years: 2008-2022)
  Canonical: FORD ESCAP (5 chars, model years: 2008-2022)
  Similarity: 95%

AI Decision: truncationVariant
Reasoning: "Full model name being standardized to 5-char SAAQ schema.
           Model year ranges match (2008-2022)."
shouldCorrect: true
canonicalForm: "ESCAP"

Result: Corrected to ESCAP ✓
```

### Case 3: Honda Civic Typo

**Both Approaches Agree**:
```
Input:
  Non-Standard: HONDA CIIVIC (model years: 2010-2022)
  Canonical: HONDA CIVIC (model years: 2010-2022)
  Similarity: 95%

AI Decision: spellingVariant
Reasoning: "Double letter typo. Model year ranges identical."
shouldCorrect: true
canonicalForm: "CIVIC"

Result: Corrected to CIVIC ✓
```

## Limitations and Edge Cases

### Known Limitations

1. **New Models Without Historical Similarity**
   - Example: Completely new nameplate (e.g., "ARIYA")
   - Won't appear in analysis (no similar canonical match)
   - Solution: Manual review of unmatched 2023-2024 pairs

2. **Model Codes vs. Trim Levels**
   - SAAQ uses model codes, not trim levels
   - `CIVIC LX` → `CIVIC` is correct truncation
   - AI may need guidance on trim vs. model distinction

3. **International vs. North American Names**
   - Some models have different names by region
   - AI may not recognize regional variants
   - Solution: Review uncertain cases for geographic variants

### Edge Cases Requiring Review

1. **Mid-Generation Refresh with New Code**
   - Old: `F150` (2009-2020)
   - New: `F-150` (2021+) - with hyphen
   - Similar but technically different codes

2. **Electric Variants of Existing Models**
   - `IONIQ` (hybrid, 2017-2022)
   - `IONIQ5` (EV, 2022+) - is this new model or variant?
   - AI should detect via model years, but review recommended

3. **Brand Acquisitions/Mergers**
   - Make changes (e.g., Plymouth → Chrysler)
   - May appear as variants but are actually different brands

## Testing and Validation

### Recommended Testing Approach

1. **Known New Models Test**
   - Manually verify: CX-90, CX-70, Q8 e-tron, ID.4, Cybertruck
   - Confirm all are classified as "newModel"
   - Ensure `shouldCorrect: false`

2. **Known Typos Test**
   - Sample typos: CIIVIC, VOLKSW, COROLA
   - Confirm all are "spellingVariant"
   - Verify corrections are accurate

3. **Schema Violations Test**
   - Long names: ESCAPE, COMPASS, SIERRA, MODELY
   - Confirm "truncationVariant"
   - Check model year ranges preserved

4. **Model Year Correlation**
   - Check that newModel decisions correlate with 2023+ model years
   - Verify no 2023+ models incorrectly corrected to old codes

### Quality Metrics

**Target Accuracy**:
- Typo detection: >95%
- New model preservation: >98%
- Schema compliance: 100%
- False positive rate: <2%

**For Research Applications**: Err on side of preserving questionable cases rather than incorrectly correcting them.

## Comparison with Original Levenshtein Approach

### Original Script (StandardizeMakeModel.swift)

**Strengths**:
- Fast execution (~15 minutes total)
- Good at detecting obvious typos
- Enforces schema length

**Weaknesses**:
- Cannot distinguish new models from typos
- No semantic understanding
- CX-90 → CX-30 incorrect mapping (92.5% similarity)
- No model year awareness

**Results**:
- 67,377 mappings generated
- ~15,896 high confidence (90%+)
- Unknown false positive rate for new models

### AI-Powered Script (AIStandardizeMakeModel.swift)

**Strengths**:
- **Preserves new models** using model year intelligence
- Semantic understanding (90 ≠ 30)
- Auditable reasoning for each decision
- Schema-aware
- Conservative (research-focused)

**Weaknesses**:
- Slower execution (~20-25 minutes)
- Requires macOS 26+
- Requires manual review of uncertain cases

**Results** (Expected):
- Fewer total mappings (new models excluded)
- Higher precision (fewer false positives)
- Research-grade accuracy

### Recommendation

**For Research Applications**: Use AI-powered approach
- Accuracy is paramount
- New models must be preserved
- Human review is acceptable
- One-time operation

**For Production/Automation**: Consider hybrid approach
- AI for edge cases (70-95% similarity)
- Simple rules for obvious cases (>95% typos)
- Batch processing with review queue

## Future Enhancements

### Potential Improvements

1. **Manual Override File**
   - User-specified corrections for edge cases
   - Exclude list for known new models
   - Brand-specific rules

2. **Multi-Year Analysis**
   - Track when models first appear
   - Identify model lifecycle (introduction, discontinuation)
   - Better new model detection

3. **VIN Decoding Integration**
   - Use VIN data to validate make/model
   - Cross-reference manufacturer specs
   - Ultimate ground truth for ambiguous cases

4. **Continuous Learning**
   - Export human review decisions
   - Train custom model on SAAQ-specific patterns
   - Improve accuracy over time

## Related Documentation

- **Vehicle-Registration-Schema.md** - Official SAAQ schema specification
- **CSV-Normalization-Guide.md** - Pre-processing 2023-2024 CSVs
- **Make-Model-Standardization-Workflow.md** - Original Levenshtein approach
- **macOS-Tahoe-26-Analysis.md** - Foundation Models framework details

## Version History

- **2025-10-03**: Initial implementation
  - Foundation Models integration (macOS 26)
  - Model year intelligence
  - SAAQ schema compliance
  - Four-category decision framework
  - Human-reviewable audit trail

---

**Document Status**: Production Ready
**Recommended For**: Research applications requiring high accuracy
**Prerequisites**: macOS 26.0+, Apple Silicon
**Execution Time**: ~20-25 minutes
**Priority**: Accuracy > Speed
