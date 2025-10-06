# SAAQAnalyzer Scripts Documentation

**Last Updated:** 2025-10-06
**Project:** SAAQAnalyzer - SAAQ Vehicle Registration Data Analysis

---

## Overview

This directory contains Swift scripts for processing and cleaning SAAQ (Société de l'assurance automobile du Québec) vehicle registration data. Scripts are divided into two categories:

1. **Production Scripts** - Fully functional and validated
2. **Experimental Scripts** - Works in progress exploring different approaches

**Important:** These scripts are **standalone command-line utilities**, not part of the SAAQAnalyzer Xcode project. They are:
- Compiled independently using `swiftc`
- Run as preprocessing tools before app launch
- Versioned separately from the main application
- Designed for terminal/script execution workflows

---

## Production Scripts

### NormalizeCSV.swift ✅

**Status:** Production-ready
**Purpose:** Fix structural inconsistencies in SAAQ CSV files
**Problem Solved:** 2017+ files have 16 fields (added fuel_type), earlier files have 15 fields

**Compilation:**
```bash
swiftc NormalizeCSV.swift -o NormalizeCSV -O
```

**Usage:**
```bash
./NormalizeCSV <input_csv> <output_csv> <year>
```

**Key Features:**
- Validates header structure based on year
- Adds NULL fuel_type column for pre-2017 files
- Handles French character encoding (UTF-8, ISO-Latin-1, Windows-1252)
- Preserves data integrity while standardizing structure

**Performance:** Processes ~1M records in seconds

**Status:** ✅ **WORKING** - This script is fully functional and required for database import

---

## Experimental Scripts (Work in Progress)

### Make/Model Regularization Scripts

**Status:** 🚧 Work in Progress
**Common Problem:** SAAQ changed data entry conventions between 2011-2022 (cleaned) and 2023-2024 (raw):
- Typos and spelling variations (HONDA vs HOND, VOLV0 vs VOLVO)
- Truncation differences (CX-3 vs CX3, HR-V vs HRV)
- Missing critical fields (vehicle_type, mass, fuel_type all NULL in 2023-2024)

**Challenge:** Distinguish genuine typos from genuinely new models without corrupting research database

---

#### 1. StandardizeMakeModel.swift

**Approach:** Levenshtein distance baseline (no AI)
**Size:** 15K
**Algorithm:** Pure string similarity matching

**Key Characteristics:**
- Simple Levenshtein distance calculation
- Fixed similarity threshold (0.70)
- No external validation
- Fast but cannot distinguish typos from new models

**Limitations:**
- False positives (BMW X4 → X3)
- False negatives (VOLV0 not recognized as VOLVO typo)
- No vehicle type awareness

**Status:** ⚠️ Baseline reference only - superseded by enhanced approaches

---

#### 2. AIStandardizeMake.swift

**Approach:** Two-pass architecture (Make first, then Model)
**Size:** 21K
**Algorithm:** Standardize makes, then models within corrected makes

**Key Characteristics:**
- Pass 1: Correct make names (HOND → HONDA)
- Pass 2: Correct models within standardized makes
- Foundation Models API integration
- Thread-safe concurrent processing with TaskGroups

**Why Abandoned:**
- **Make ambiguity problem**: Many makes produce multiple vehicle types
  - HONDA: 11 classifications (PAU cars, PMC motorcycles, HVT ATVs, etc.)
  - FORD: 11 classifications (PAU cars, BCA trucks, etc.)
  - YAMAHA: 6 classifications (motorcycles, ATVs, snowmobiles - NO PAU/CAU!)
- Impossible to disambiguate without model information
- Would cause cross-type contamination

**Status:** ⚠️ Architecturally flawed - abandoned

---

#### 3. AIStandardizeMakeModel.swift

**Approach:** Single-pass with AI validation
**Size:** 24K
**Algorithm:** Make/Model pair matching with Foundation Models API

**Key Characteristics:**
- Processes Make/Model pairs together
- AI classifies as: spellingVariant, truncationVariant, newModel, uncertain
- No CVS validation
- No temporal validation
- Simple AI-only decision making

**Limitations:**
- No external validation sources
- AI prompt not optimized for pipeline
- Inconsistent AI responses (contradictions)

**Status:** ⚠️ Superseded by enhanced versions

---

#### 4. AIStandardizeMakeModel-Enhanced.swift

**Approach:** CVS-enhanced validation pipeline
**Size:** 29K
**Algorithm:** Three-layer validation (CVS + Temporal + AI)

**Key Characteristics:**
- **CVS Database Integration** (Transport Canada vehicle type authority)
  - Location: `~/Desktop/cvs_complete.sqlite`
  - 725 unique Make/Model pairs
  - Coverage: PAU 63.5%, CAU 82.1%, specialty 0%
- **Temporal Validation** (year range compatibility checking)
- **AI Analysis** (Foundation Models classification)
- **Priority Filtering** (4 levels: canonical PAU/CAU, CVS new PAU/CAU, specialty, unknown)

**CVS Validation Logic:**
```
CASE 1: Both in CVS, same vehicle_type → SUPPORT (0.9)
CASE 2: Both in CVS, different vehicle_type → PREVENT (0.9)
CASE 3: Only canonical in CVS → SUPPORT (0.8)
CASE 4: Neither in CVS → NEUTRAL (0.5)
```

**Override Logic:**
- CVS confidence ≥0.9 AND says PREVENT → Override AI
- Temporal confidence ≥0.8 AND says PREVENT → Override AI
- Else → Use AI decision

**Issues Discovered:**
- Priority filtering caused vehicle type inflation risk
- PAU/CAU-only matching could incorrectly match specialty vehicles
- AI prompt needed optimization

**Status:** ⚠️ Architecture evolved → AIRegularizeMakeModel.swift

---

#### 5. AIRegularizeMakeModel.swift (Current)

**Approach:** All-types matching with optimized validation
**Size:** 25K
**Algorithm:** Simplified architecture, enhanced AI prompt

**Architectural Changes from Enhanced Version:**
- ✅ **Removed priority filtering** - Matches all 2023-2024 pairs against ALL 1,477 canonical pairs
- ✅ **Natural disambiguation** - String similarity prefers exact matches (HONDA CBR → HONDA CBR, not HONDA CR-V)
- ✅ **Eliminated redundant DB queries** - Uses pre-loaded year ranges from MakeModelPair structs
- ✅ **Added year context to AI prompt** - Registration year ranges visible to AI
- ✅ **Improved console output** - Shows year ranges and clear decision semantics
- ✅ **Terminology change** - "Standardize" → "Regularize" throughout

**Key Technical Features:**
- **Thread-safe concurrency**: Fresh LanguageModelSession per task, separate DB connections
- **Hyphenation-aware matching**: CX3 ↔ CX-3 gets 0.99 similarity boost
- **Three-layer validation**: CVS + Temporal + AI with override logic
- **Year context**: Registration and model year ranges in prompts and output

**AI Prompt Structure:**
```
Record A: MAZDA / CX3 [registered: 2023-2024]
Record B: MAZDA / CX-3 [registered: 2011-2022]

Classification categories:
1. spellingVariant (VOLV0→VOLVO)
2. truncationVariant (CX3→CX-3)
3. newModel (X4≠X3, CARNI≠CADEN)
4. uncertain
```

**Known Issues:**
- AI prompt still produces some contradictory responses
- Temporal validation using registration years instead of model years
- Confusion about when registration year gaps indicate new models vs late registrations
- Some false positives (MERLO 3712 → 45.21, KUBOT K0083 → F3080)

**Compilation:**
```bash
swiftc AIRegularizeMakeModel.swift -o AIRegularizeMakeModel -O
```

**Usage:**
```bash
./AIRegularizeMakeModel <saaq_db_path> <cvs_db_path> <output_report_path>
```

**Performance:** ~0.7-0.8 pairs/sec (Foundation Models API throughput)

**Status:** 🚧 Most advanced version, but validation logic needs refinement

---

#### 6. RegularizeMakeModel.swift

**Approach:** Different architectural approach (details TBD)
**Size:** 37K (largest script)
**Algorithm:** TBD

**Special Compilation Requirements:**
```bash
swiftc -parse-as-library -o RegularizeMakeModel RegularizeMakeModel.swift
```

**Key Characteristics:**
- Uses `-parse-as-library` flag (suggests modular architecture)
- Significantly larger than other scripts
- Configuration-driven approach with Config enum
- Known make variants dictionary
- Multiple similarity thresholds for different vehicle types
- Vehicle type categorization (passenger, motorcycle, specialized)

**Status:** 🚧 Created outside session - needs documentation

---

## Supporting/Analysis Scripts

### BuildCVSDatabase.swift

**Purpose:** Create CVS validation database from Transport Canada data
**Output:** `~/Desktop/cvs_complete.sqlite`
**Key Feature:** Converts CSVs to queryable database for validation

---

### AnalyzeVehicleFingerprints.swift

**Purpose:** Analyze canonical 2011-2022 data patterns
**Output:** Statistics on Make/Model distributions, year ranges, vehicle types

---

### AnalyzeYearPatterns.swift

**Purpose:** Temporal pattern analysis
**Output:** Year range distributions for Make/Model pairs

---

### ApplyMakeModelCorrections.swift

**Purpose:** Apply pre-approved correction mappings to database
**Input:** Correction mapping file
**Status:** Downstream tool for validated corrections

---

### DiagnoseCVSEnhanced.swift

**Purpose:** CVS database coverage analysis
**Output:** Statistics on CVS vs SAAQ data overlap

---

## Key Architectural Patterns

### 1. Swift Concurrency (Swift 6.2)

**Pattern:**
```swift
@MainActor
func main() async throws {
    // Main logic
}
try await main()
```

**Critical for Foundation Models API** - Must use this pattern, NOT:
```swift
Task { @MainAactor in ... } + RunLoop.main.run()  // ❌ Causes hangs
```

### 2. Thread-Safe Database Access

**Pattern:**
```swift
// ✅ Pass paths, open per-task
group.addTask {
    let db = try DatabaseHelper(path: dbPath)
    // Use db
}

// ❌ Shared instance causes segfaults
let db = DatabaseHelper(...)
group.addTask {
    db.query(...)  // NOT THREAD-SAFE
}
```

### 3. Fresh AI Session Per Task

**Pattern:**
```swift
group.addTask {
    let session = LanguageModelSession(instructions: "...")
    let response = try await session.respond(to: prompt)
}
```

---

## Database Schemas

### SAAQ Database (Enumeration Schema)
```sql
-- Foreign key references to enumeration tables
SELECT make_enum.name, model_enum.name, classification_enum.code
FROM vehicles
JOIN make_enum ON vehicles.make_id = make_enum.id
JOIN model_enum ON vehicles.model_id = model_enum.id
JOIN classification_enum ON vehicles.classification_id = classification_enum.id;
```

### CVS Database (String Schema)
```sql
-- Direct string columns
SELECT saaq_make, saaq_model, vehicle_type, myr
FROM cvs_data  -- NOT vehicles!
WHERE saaq_make = ? AND saaq_model = ?;
```

---

## Current Research Questions

1. **Registration vs Model Years**: Should temporal validation use model years instead of registration years?
2. **New Model Detection**: How to distinguish late registrations from genuinely new 2023+ models?
3. **AI Prompt Optimization**: Can we eliminate contradictory responses?
4. **Validation Weights**: What should CVS/Temporal/AI confidence thresholds be?
5. **Approach Selection**: Is AI-based validation the right approach, or should we explore deterministic rules?

---

## Recommendations

### For Production Use
- ✅ Use **NormalizeCSV.swift** for structural fixes (fully validated)
- ⚠️ Make/Model regularization scripts are **experimental** - do not apply to production database
- 📊 Generate reports and manually review before applying any corrections

### For Development
- Start with **AIRegularizeMakeModel.swift** as baseline
- Review **RegularizeMakeModel.swift** alternative approach
- Consider hybrid: deterministic rules for obvious cases, AI for ambiguous cases
- Focus on high-confidence, low-risk corrections first (spelling variants only)

---

## Version History

- **v1 (StandardizeMakeModel)**: Levenshtein baseline
- **v2 (AIStandardizeMake)**: Two-pass approach (abandoned - make ambiguity)
- **v3 (AIStandardizeMakeModel)**: Single-pass AI
- **v4 (AIStandardizeMakeModel-Enhanced)**: CVS + Temporal + AI with priority filtering
- **v5 (AIRegularizeMakeModel)**: All-types matching, optimized prompt, year context
- **v6 (RegularizeMakeModel)**: Alternative approach (details TBD)

---

## Contact & Support

See main project documentation: `/Users/rhoge/Desktop/SAAQAnalyzer/CLAUDE.md`
