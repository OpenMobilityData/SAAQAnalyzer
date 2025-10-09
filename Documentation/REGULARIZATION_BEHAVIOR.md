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

### Regularization Status Badges (in RegularizationView)

When working in the Regularization Editor, each Make/Model pair shows a status badge:

- 🔴 **Unassigned** - No regularization mapping exists yet
- 🟠 **Needs Review** - Mapping exists but FuelType and/or VehicleType are NULL (needs user review)
- 🟢 **Complete** - Both FuelType AND VehicleType are assigned (including "Unknown" when disambiguation is impossible)

**Note:** The green "Complete" badge requires both FuelType AND VehicleType to be non-NULL. Setting a field to "Unknown" counts as assigned (user has made a decision), while "Not Specified" (NULL) means the field hasn't been reviewed yet.

**Terminology Note:** "VehicleType" refers to the physical type of vehicle (TYP_VEH_CATEG_USA field: AU, CA, MC, etc.), not the usage-based classification (CLAS field: PAU, CAU, TAX, etc.).

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

## Smart Auto-Assignment

When you open the RegularizationView, the system automatically performs **smart auto-assignment** for exact matches:

### What Gets Auto-Assigned

For Make/Model pairs that exist in both curated and uncurated years (e.g., `HONDA CIVIC`):

1. **Make and Model**: Always auto-assigned to matching canonical values
2. **FuelType**: Auto-assigned if **only one option exists** in the canonical data (excluding "Not Specified" placeholders)
3. **VehicleType**: Uses **Cardinal Type Matching** (see below) when multiple options exist, or auto-assigns if only one option exists

**Note:** The system only counts actual types found in curated years (Gasoline, Diesel for FuelType; AU, CA, MC, etc. for VehicleType). The "Unknown" enum value will never appear in the canonical hierarchy since it wasn't used in curated years (2011-2022).

### Cardinal Type Auto-Assignment

**Problem:** Many Make/Model pairs have multiple vehicle types in the canonical data, making automatic assignment impossible with simple logic.

**Example - GMC Sierra:**
```
GMC SIERRA in curated data has:
- VehicleTypes: ["AU - Automobile or Light Truck", "CA - Truck or Road Tractor", "VO - Tool Vehicle"]

Without cardinal types: VehicleType left NULL → 🟠 Orange "Needs Review" (manual review required)
With cardinal types:    VehicleType auto-assigned to AU → 🟢 Green "Complete" ✅
```

**Solution:** Cardinal types are designated "priority" vehicle types. When multiple types exist, the system automatically assigns the first matching cardinal type based on priority order.

**Default Cardinal Types:**
1. **AU** (Automobile or Light Truck) - Highest priority, covers ~90% of passenger vehicles
2. **MC** (Motorcycle) - Second priority, covers most two-wheeled vehicles

**How It Works:**
1. System finds all valid vehicle types for the Make/Model pair in canonical data
2. If multiple types exist, checks if any match a cardinal type
3. Assigns the **first matching** cardinal type based on priority order
4. If no cardinal type matches, leaves VehicleType NULL (requires manual review)

**Configuration:**
- Settings → Regularization tab → "Cardinal Type Auto-Assignment" section
- Toggle to enable/disable (enabled by default)
- View priority order and type descriptions
- Future: Add/remove/reorder cardinal types as needed

**Logging:**
Auto-assignment logs distinguish between cardinal and single-option assignments:
```
✅ Auto-regularized: HONDA CIVIC [M/M, FuelType, VehicleType]
✅ Auto-regularized: GMC SIERRA [M/M, VehicleType(Cardinal)]
```

### Examples

**Full Auto-Assignment (Single Options):**
```
HONDA CIVIC in curated data has:
- FuelTypes: ["Gasoline"] (only one option)
- VehicleTypes: ["AU - Automobile or Light Truck"] (only one option)

Result: ✅ Fully auto-assigned → 🟢 Green "Complete" badge
```

**Cardinal Type Auto-Assignment (Multiple Vehicle Types):**
```
GMC SIERRA in curated data has:
- FuelTypes: ["Gasoline", "Diesel"] (multiple options)
- VehicleTypes: ["AU", "CA", "VO"] (multiple options)
- Cardinal types: ["AU", "MC"]

Result: ✅ VehicleType auto-assigned to AU (cardinal match)
        ⚠️  FuelType left NULL (no cardinal fuel types yet)
        → 🟠 Orange "Needs Review" badge
User must manually select FuelType (or "Unknown") to complete the mapping
```

**Partial Auto-Assignment (Multiple Fuel Types):**
```
HONDA ACCORD in curated data has:
- FuelTypes: ["Gasoline", "Hybrid", "Electric"] (multiple options)
- VehicleTypes: ["AU - Automobile or Light Truck"] (only one option)

Result: ✅ VehicleType auto-assigned, FuelType left NULL → 🟠 Orange "Needs Review" badge
User must manually select FuelType (or "Unknown") to complete the mapping
```

**No Cardinal Match:**
```
SCHOOL BUS in curated data has:
- VehicleTypes: ["AB - Bus", "TAS - School Bus"] (multiple options)
- Cardinal types: ["AU", "MC"] (no match)

Result: ⚠️  VehicleType left NULL → 🟠 Orange "Needs Review" badge
User must manually select VehicleType (consider adding "AB" as cardinal type for buses)
```

### Picker Options: "Not Specified" vs "Unknown"

When you select a Make/Model pair for editing, the FuelType and VehicleType dropdowns show three types of options:

1. **"Not Specified"** - UI label for database NULL (field hasn't been reviewed yet)
2. **"Unknown"** - Explicit value when disambiguation is impossible (user has reviewed and determined it's unknowable)
3. **Actual values** - E.g., "Gasoline (1234)", "PAU - Passenger (5678)"

**Key Distinctions:**

| Option | Database Value | Badge Color | Meaning |
|--------|---------------|-------------|---------|
| "Not Specified" | NULL | 🟠 Orange "Needs Review" | Field hasn't been reviewed by user |
| "Unknown" | "Unknown" enum value | 🟢 Green "Complete" | User reviewed and determined field cannot be disambiguated |
| Actual type (e.g., "Gasoline", "AU") | Real enum value | 🟢 Green "Complete" | User successfully identified the type |

**Why this matters:**
- **Orange badges** signal "needs attention" - user hasn't looked at this pair yet
- **Green badges** signal "work complete" - user has reviewed and made a decision (even if that decision is "Unknown")
- You can "undo" an Unknown assignment by setting back to "Not Specified" to flag it for future review

## Status Filters in RegularizationView

The RegularizationView now provides granular filtering by regularization status using three independent filter buttons:

**Filter Buttons:**
- 🔴 **Unassigned** - Show/hide pairs with no regularization mapping
- 🟠 **Needs Review** - Show/hide pairs with mappings but NULL FuelType/VehicleType
- 🟢 **Complete** - Show/hide pairs with both FuelType AND VehicleType assigned

**Default:** All three filters are enabled (all pairs visible)

### Filter Combinations

You can enable/disable any combination of filters to focus on specific workflows:

**Common Workflows:**

1. **Only show work needed** (🔴 + 🟠):
   - Uncheck "Complete" filter
   - Shows only pairs requiring attention
   - Hides successfully completed mappings

2. **Review completed work** (🟢 only):
   - Uncheck "Unassigned" and "Needs Review"
   - Shows only fully regularized pairs
   - Useful for quality assurance

3. **Focus on partial assignments** (🟠 only):
   - Uncheck "Unassigned" and "Complete"
   - Shows pairs where Make/Model are mapped but FuelType/VehicleType need review
   - Prioritize finishing started work

4. **Start fresh work** (🔴 only):
   - Uncheck "Needs Review" and "Complete"
   - Shows only unmapped pairs
   - Good for bulk regularization sessions

### Important Notes

- All filters are independent - you can select any combination
- Filters apply to **all pairs** including exact matches (pairs that exist in both curated and uncurated years)
- Smart auto-assignment still runs in the background regardless of filter settings
- The list dynamically updates as you toggle filters

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
