# Make/Model Regularization - User Guide

## Overview

The regularization system allows you to map typos and variants in uncurated data (2023-2024) to canonical values from curated data (2011-2022). This document explains how the system behaves when filtering and querying.

## Badge System

### Model Filter Dropdown
- `"CR-V (HONDA)"` - Canonical model (exists in curated years 2011-2022, no badge)
- `"CRV (HONDA) [uncurated: 14 records]"` - Uncurated variant, not yet regularized
- `"CRV (HONDA) → HONDA CR-V (14 records)"` - Uncurated variant regularized to canonical HONDA CR-V

**Note:** The badge shows the full canonical Make Model pair, making it clear when either Make or Model (or both) have been corrected. For example:
- `"XC90 (VOLV0) → VOLVO XC90 (5 records)"` - Make typo corrected (VOLV0 → VOLVO), Model unchanged
- `"CRV (HONDA) → HONDA CR-V (14 records)"` - Make unchanged, Model typo corrected (CRV → CR-V)
- `"JHOND 6330 (JHOND) → JOHND 6300 (8 records)"` - Both Make and Model corrected

### Make Filter Dropdown
- `"VOLVO"` - Canonical Make (no badge)
- `"VOLV0 [uncurated: 123 records]"` - Uncurated Make, not yet regularized
- `"VOLV0 → VOLVO (123 records)"` - Uncurated Make regularized to canonical VOLVO

**Note:** Badges are hidden when the uncurated name matches the canonical name (e.g., "HONDA → HONDA" is shown as just "HONDA").

## Query Behavior

### With "Enable Regularization in Queries" = OFF (Default)

**Independent Queries:**
- Selecting `"CRV (HONDA) → CR-V (14 records)"` queries **only** the uncurated CRV variant
  - Returns: 14 records from 2023-2024
- Selecting `"CR-V (HONDA)"` queries **only** the canonical CR-V
  - Returns: 197 records from 2011-2022
- The two selections are completely independent

**Use Case:** When you want to see exactly what's in the original data for each variant separately.

### With "Enable Regularization in Queries" = ON

**Merged Queries:**
- Selecting `"CRV (HONDA) → CR-V (14 records)"` queries **both** CRV and CR-V
  - Returns: 211 records (14 from 2023-2024 + 197 from 2011-2022)
- Selecting `"CR-V (HONDA)"` also queries **both** CRV and CR-V
  - Returns: 211 records (same merged dataset)
- **Either selection returns the same combined results**

**Use Case:** When you want to analyze the full history including regularized variants as if they were always spelled correctly.

## Important Behaviors

### 1. Selecting Uncurated Variants WITH Regularization ON

When you select an uncurated variant like `"CRV (HONDA) → CR-V (14 records)"` with regularization enabled:
- You will see records from the uncurated years (2023-2024) in your results
- This is **expected behavior** - the system includes both the uncurated and canonical records
- The badge shows the mapping, but you're querying the merged dataset

**Example:**
- Filter: Years = 2023-2024, Model = `"CRV (HONDA) → CR-V (14 records)"`, Regularization = ON
- Result: 14 records (from uncurated CRV in 2023-2024)
- This is correct! The canonical CR-V doesn't exist in 2023-2024, so only the CRV records appear.

### 2. Automatic Cache Reload

The filter cache automatically reloads in these situations:
- When you close the RegularizationView after creating/editing mappings
- When you launch the app (if regularization mappings exist)
- When you manually click "Reload Filter Cache" in Settings

### 3. Make/Model Coupling Modes

The system supports two modes when regularization is enabled:

#### **Coupled Mode** (Default - Recommended)
Toggle: `"Couple Make/Model in Queries"` = **ON**

**Behavior:** Regularization respects Make/Model relationships from mappings
- Filter: Model = "CR-V" (no Make selected)
- Result: Returns CR-V AND CRV, but **only from HONDA** (the Make in the mapping)
- Why: Prevents false matches if other manufacturers have similar model names

**Best for:** Normal analysis where you want semantically correct results

#### **Decoupled Mode** (Advanced)
Toggle: `"Couple Make/Model in Queries"` = **OFF**

**Behavior:** Make and Model filters remain completely independent
- Filter: Model = "CR-V" (no Make selected)
- Result: Returns CR-V AND CRV from **ANY manufacturer**
- Why: Preserves original filter independence, useful for exploring data

**Best for:** Research, data quality analysis, finding unexpected model name collisions

**Example Comparison:**
```
Filter: Years = 2023-2024, Model = "CR-V" (no Make filter)
Regularization = ON, Coupling = ON:  Returns 211 Honda CR-V + CRV records
Regularization = ON, Coupling = OFF: Returns 211 records from any Make with "CR-V" or "CRV"
```

### 4. Persistent Settings

- The "Enable Regularization in Queries" toggle persists across app restarts
- The "Couple Make/Model in Queries" toggle persists across app restarts (default: ON)
- Your year configuration (curated/uncurated) persists in the database

## Make-Level Regularization (Derived)

When you create a Make/Model mapping like `VOLV0 XC90 → VOLVO XC90`, the system automatically derives:
- Make-level regularization: `VOLV0 → VOLVO`
- No separate UI needed - it's automatic!

**Consistency Rule:** All Make/Model mappings with the same uncurated Make must map to the same canonical Make. For example:
- ✅ `VOLV0 XC90 → VOLVO XC90` and `VOLV0 S60 → VOLVO S60` (both VOLV0 → VOLVO)
- ❌ `VOLV0 XC90 → VOLVO XC90` and `VOLV0 S60 → TOYOTA CAMRY` (conflict!)

The system will prevent conflicting Make mappings.

## Show Exact Matches Toggle

By default, the RegularizationView only shows Make/Model pairs that exist in uncurated years (2023-2024) but NOT in curated years (2011-2022). These are typically typos or new variants that need correction.

However, you may want to work with **exact matches** - pairs that exist in both curated and uncurated years - to add FuelType or VehicleType disambiguation.

**Toggle:** `"Show Exact Matches"` in RegularizationView (default: OFF)

### Use Cases for Exact Matches

**Example:** `HONDA ACCORD` exists in both 2022 (curated) and 2023 (uncurated)

**Without "Show Exact Matches" (Default):**
- This pair is hidden (not shown in the list)
- Assumption: If Make/Model match exactly, no regularization needed

**With "Show Exact Matches" (Enabled):**
- This pair appears in the list
- You can create mapping: `HONDA ACCORD → HONDA ACCORD` + specify FuelType = "Hybrid"
- Useful when new fuel types or vehicle types appear in uncurated years

**When to enable:**
1. Adding FuelType/VehicleType disambiguation for existing Make/Model combinations
2. Reviewing all uncurated data, not just typos
3. Research or data quality analysis

## Tips

1. **To see original data quality:** Turn regularization OFF and filter by uncurated years (2023-2024)
2. **To analyze merged history:** Turn regularization ON and select any year range
3. **To correct typos:** Use RegularizationView to map uncurated variants to canonical values
4. **Badge interpretation:** The badge shows you what's in the database, not what will be queried (that depends on the regularization toggle)

## Console Messages to Watch

```
✅ Loaded derived Make regularization info for X Makes
✅ Loaded XXX uncurated Make/Model pairs
🔗 Make regularized: VOLV0 → VOLVO
🔗 Regularized: CRV (HONDA) → CR-V
🔍 Make 'VOLV0 → VOLVO (123 records)' (cleaned: 'VOLV0') -> ID X
🔄 Make regularization expanded 1 → 2 IDs
🔄 Regularization expanded IDs: Makes: 1 → 2, Models: 1 → 2
```

These messages help you understand when regularization is active and how IDs are being expanded.
