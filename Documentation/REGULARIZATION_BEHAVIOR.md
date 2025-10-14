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

### Fuel Type Filtering with Regularization

**How It Works:**
- **Fuel type filtering is TRIPLET-BASED**: Matches Make ID + Model ID + **Model Year ID**
- Unlike vehicle type (wildcard mapping), fuel types are assigned per model year
- Example: 2008 Honda Civic → Gasoline, 2022 Honda Civic → Hybrid

**With Regularization ON:**
- Curated records: Direct fuel_type_id match
- Uncurated records: Uses triplet mapping (Make/Model/ModelYear → FuelType)
- Pre-2017 records: Controlled by "Apply Fuel Type Regularization to Pre-2017 Records" toggle

**Pre-2017 Toggle Behavior:**
- **ON** (default): Pre-2017 records with regularization mappings included in fuel type filtering
- **OFF**: Pre-2017 records excluded from fuel type filtering (even with mappings)
- **Why:** Pre-2017 records have NULL fuel_type because the field didn't exist in source CSV

**Example Query:**
```
Filter: Fuel Type = "Gasoline", Years = 2011-2024, Regularization = ON
Pre-2017 Toggle = ON:  Includes 2011-2016 records with Gasoline mappings
Pre-2017 Toggle = OFF: Excludes 2011-2016 records (only 2017+ with mappings)
```

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
- The "Apply Fuel Type Regularization to Pre-2017 Records" toggle persists across app restarts (default: ON)
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

The regularization system provides two levels of automatic field population to streamline your workflow:

### 1. Background Auto-Regularization (Exact Matches)

When you open the RegularizationView, the system automatically performs **smart auto-assignment** for exact matches:

For Make/Model pairs that exist in both curated and uncurated years (e.g., `HONDA CIVIC`):

1. **Make and Model**: Always auto-assigned to matching canonical values
2. **FuelType**: Auto-assigned if **only one option exists** in the canonical data (excluding "Not Specified" placeholders)
3. **VehicleType**: Uses **Cardinal Type Matching** (see below) when multiple options exist, or auto-assigns if only one option exists

**Note:** The system only counts actual types found in curated years (Gasoline, Diesel for FuelType; AU, CA, MC, etc. for VehicleType). The "Unknown" enum value will never appear in the canonical hierarchy since it wasn't used in curated years (2011-2022).

### 2. Interactive Auto-Population (Unassigned Pairs)

When you manually assign a canonical Make/Model to an **Unassigned** pair (red status badge), the system automatically populates:

**Triggers:**
- User selects Make in Step 1
- User selects Model in Step 2
- System detects no existing mappings for this pair

**Auto-Population Logic:**

1. **VehicleType (Step 3)**:
   - Single valid option → Auto-assigned
   - Multiple options + cardinal match → Auto-assigned using cardinal type
   - Multiple options, no cardinal match → Left unassigned (user review needed)

2. **FuelType by Model Year (Step 4)**:
   - Model year has single valid fuel type → Auto-assigned
   - Model year has multiple fuel types → Left unassigned (user review needed)
   - Model year has NULL fuel type (pre-2017) → Left unassigned (user selects "Unknown")

**Benefits:**
- Reduces clicks for straightforward assignments
- Preserves user control for ambiguous cases
- Speeds up workflow for typo corrections (e.g., VOLV0 → VOLVO)

**Important:** Auto-population only occurs for **new assignments**. If a pair already has mappings, the system loads existing values instead of auto-populating (preserves your work).

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

## Model Year vs Registration Year: The 2017 Fuel Type Cutoff

### Important Distinction

The SAAQ data contains two year values:
- **AN (Registration Year)**: The year the vehicle was authorized to circulate (year of the data snapshot, December 31st)
- **ANNEE_MOD (Model Year)**: The year the manufacturer designated as the model year

**Critical Detail**: The fuel type field (`TYP_CARBU`) was **added to the SAAQ schema in 2017**. This means:
- **Pre-2017 registration files** (2011-2016): NULL fuel_type for ALL vehicles
- **2017+ registration files**: fuel_type populated for vehicles

### The Edge Case: Model Year 2017 in 2016 Data

You may encounter model year 2017 vehicles with NULL fuel_type. This occurs because:
1. Vehicle with model year 2017 was registered in 2016 (early registration)
2. The 2016 registration file doesn't have the fuel_type field (added in 2017)
3. Result: Model year 2017 appears in canonical hierarchy with NULL fuel_type

**Example**: VOLKS/TOUAR (Volkswagen Touareg) from curated years 2012, 2016:
- Model Year 2010: NULL fuel_type (expected - pre-2017 schema)
- Model Year 2011: NULL fuel_type (expected - pre-2017 schema)
- Model Year 2017: NULL fuel_type (edge case - 2017 model registered in 2016 file)

### How the System Handles This

1. **Canonical Hierarchy Generation**: Model years with NULL fuel_type now appear in Step 4 of the Regularization Editor
2. **User Options**: For these years, you'll see:
   - **Not Assigned** (default) - Year hasn't been reviewed
   - **Unknown** - Recommended choice when fuel type cannot be determined from source data
3. **Completion**: Assigning "Unknown" to all NULL fuel_type years marks the pair as complete

### Recommendation

For model years with NULL fuel_type (whether pre-2017 or the edge case):
- ✅ **Select "Unknown"** - Acknowledges you've reviewed it and fuel type is unavailable in source data
- ❌ **Don't leave "Not Assigned"** - This keeps the pair in "Needs Review" status indefinitely

## Model Year Fuel Type Assignment UI

When editing a Make/Model pair, Step 4 provides a radio button interface for assigning fuel types to each model year:

### Radio Button Options
Each model year shows three types of selections:
- **Not Assigned** (default) - Year hasn't been reviewed yet (database NULL)
- **Unknown** - User reviewed and determined fuel type cannot be disambiguated (stored as "U" in database)
- **Specific fuel types** - E.g., "Gasoline (1234)", "Diesel (567)" with record counts from curated data

**Key Rule**: Only ONE selection allowed per year (enforces unambiguous assignments)

### Step 4 Completion Indicator

A **green checkmark** (✓) appears in the "Step 4" header when ALL model years have been assigned:
- ✅ Appears when no years have "Not Assigned" status
- ✅ "Unknown" counts as assigned (user made a decision)
- ✅ Updates in real-time as selections are made

**Purpose**: Provides immediate visual feedback that fuel type assignment is complete for this Make/Model pair

### "Show Only Not Assigned" Filter

A **filter toggle** button allows focusing on years that still need review:

**Features:**
- Toggle icon: outline (OFF) → filled (ON)
- Shows count: "X of Y years"
- Default: OFF (shows all years)

**Use Cases:**
- **After auto-regularization**: Hide years with assigned fuel types to focus on remaining work
- **Large models**: Essential for models with 10+ years (e.g., Honda Civic with 14 years)
- **Progress tracking**: Counter shows how many years remain unassigned

**Example Workflow:**
1. Honda Civic loads with 13/14 years assigned (auto-regularization skipped year 2009 with multiple fuel types)
2. No checkmark in Step 4 header (incomplete)
3. Enable filter toggle → see only year 2009
4. Counter shows "1 of 14 years"
5. Assign "Unknown" to year 2009
6. Checkmark appears (all years assigned)
7. Save → Status badge updates to 🟢 "Complete"

## Status Filters in RegularizationView

The RegularizationView provides granular filtering by regularization status using three independent filter buttons with real-time counts:

**Filter Buttons:**
- 🔴 **Unassigned (XXX)** - Show/hide pairs with no regularization mapping
- 🟠 **Needs Review (XXX)** - Show/hide pairs with mappings but incomplete year coverage or NULL VehicleType
- 🟢 **Complete (XXX)** - Show/hide pairs with VehicleType assigned AND all model years have fuel types assigned

**Features:**
- **Real-time counts**: Each button displays the number of pairs in that status (e.g., "Unassigned (553)")
- **Tooltip details**: Hover over buttons to see full status information including clarification that counts refer to Make/Model pairs
- **Default:** All three filters are enabled (all pairs visible)

### Vehicle Type Filter

Additional filtering by vehicle type is available below the status filters:

**Filter Options:**
- **All Types** (default) - Show pairs with any vehicle type
- **Not Assigned** - Show pairs with no vehicle type mapping
- **Specific types** - Filter by vehicle type code (e.g., "AU - Automobile or Light Truck", "MC - Motorcycle")

**Toggle Mode:**
- **"In regularization list only"** switch allows filtering between:
  - **OFF**: Shows all vehicle types from schema (13 types: AB, AT, AU, CA, CY, HM, MC, MN, NV, SN, UK, VO, VT)
  - **ON**: Shows only vehicle types present in current regularization mappings
- Selection is preserved when toggling if the type exists in both lists
- **UK - Unknown** always appears at the end of the list

**Use Cases:**
- Focus on pairs mapped to specific vehicle types (e.g., only motorcycles)
- Find pairs that still need vehicle type assignment ("Not Assigned")
- Review coverage of specific vehicle categories

### Incomplete Fields Filter

Target pairs that have mappings but are missing specific field assignments:

**Filter Options:**
- **Filter by Incomplete Fields** toggle - Enable/disable this filter section
- **Vehicle Type not assigned** - Show pairs where the wildcard mapping has NULL vehicle_type
- **Fuel Type not assigned (any model year)** - Show pairs where ANY triplet mapping has NULL fuel_type

**Behavior:**
- Only applies to pairs with existing mappings (ignores completely unassigned pairs)
- Multiple checkboxes can be selected simultaneously (OR logic)
- Checkboxes are disabled when the main toggle is OFF
- Checkboxes automatically reset when toggling off

**Use Cases:**
1. **Vehicle Type cleanup** - Enable "Vehicle Type not assigned" to find pairs where Make/Model are mapped but vehicle type needs review
2. **Fuel Type cleanup** - Enable "Fuel Type not assigned" to find pairs where some model years still lack fuel type assignments
3. **Combined cleanup** - Enable both to find pairs incomplete in either dimension

**Example Workflow:**
1. Complete status shows 278 pairs, but some may have incomplete year coverage
2. Enable "Filter by Incomplete Fields" → check "Fuel Type not assigned"
3. List shows pairs marked as "Needs Review" with incomplete fuel type triplets
4. Work through list assigning "Unknown" or specific fuel types to complete years
5. As pairs complete, they disappear from the filtered view

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

## Filter Options Features

### "Limit to Curated Years Only" Toggle

This feature allows you to work exclusively with curated data by:
- **Filtering dropdowns**: Removes uncurated Make/Model pairs (those with `[uncurated: X records]` badges) from filter dropdowns
- **Restricting queries**: Prevents queries from executing against uncurated years (e.g., 2023-2024)
- **Visual feedback**: Uncurated year checkboxes are greyed out (40% opacity) and disabled when toggle is active

**Use Cases:**
- Clean analysis without uncurated data badges cluttering the UI
- Focus exclusively on years with curated Make/Model data (typically 2011-2022)
- Compare curated years without interference from typos or variants in recent data

**Location:** Filter Options section (second section from top in filter panel)

**Behavior:**
```
Toggle OFF (default): All Makes/Models visible, all years queryable
Toggle ON:           Only curated Makes/Models in dropdowns, only curated years in queries
```

### "Hierarchical Make/Model Filtering" Toggle

**Status:** UI toggle exists but feature not yet implemented (Phase 3)

**Planned Behavior:**
- When enabled, Model dropdown only shows models for currently selected Make(s)
- Reduces cognitive load when working with large Make/Model lists
- Works independently of curated years toggle

## Tips

1. **To see original data quality:** Turn regularization OFF and filter by uncurated years (2023-2024)
2. **To analyze merged history:** Turn regularization ON and select any year range
3. **To correct typos:** Use RegularizationView to map uncurated variants to canonical values
4. **Badge interpretation:** The badge shows you what's in the database, not what will be queried (that depends on the regularization toggle)
5. **To work with curated data only:** Enable "Limit to Curated Years Only" in Filter Options

## Regularization Statistics Display

### Field-Specific Coverage

The Regularization Settings tab displays detailed statistics about regularization coverage by field type:

**Statistics Section:**
- **Active Mappings**: Total number of Make/Model regularization mappings in the database
- **Field Coverage (Records)**: Shows how many vehicle records in uncurated years have regularization assignments
  - **Make/Model**: Records with canonical Make and Model assigned
  - **Fuel Type**: Records with fuel type assigned (via triplet mappings)
  - **Vehicle Type**: Records with vehicle type assigned (via wildcard mappings)

**Display Features:**
- Progress bars with color coding (green >50%, orange ≤50%)
- Record counts shown as "assigned / total" for each field
- Percentage coverage for each field type
- Overall coverage percentage

**Staleness Tracking:**
When statistics need refreshing, the "Refresh Statistics" button shows:
- Orange warning badge (⚠️ triangle icon)
- "Mappings changed" indicator text
- Helpful tooltip explaining when refresh is needed

**Statistics Become Stale When:**
- RegularizationView is closed (mappings may have been edited)
- Year configuration changes (curated/uncurated years modified)

**Refresh Behavior:**
- Click "Refresh Statistics" to reload latest coverage data
- Statistics automatically refresh when Settings tab first loads
- Warning badge disappears after successful refresh

### Understanding Coverage Metrics

**Important:** All statistics count **vehicle records**, not Make/Model pairs. For example:
- "Make/Model: 12,345 / 50,000 (24.7%)" means 12,345 vehicle records have canonical Make/Model assignments
- This represents coverage across all uncurated vehicle records, not the number of mapping pairs

**Why Coverage Varies by Field:**
- **Make/Model coverage** reflects canonical pair assignments
- **Fuel Type coverage** depends on triplet mappings (Make/Model/ModelYear)
- **Vehicle Type coverage** depends on wildcard mappings (one per Make/Model pair)
- Each field can have different coverage percentages based on mapping completeness

## Console Messages to Watch

**Regularization Loading:**
```
✅ Loaded derived Make regularization info for X Makes
✅ Loaded XXX uncurated Make/Model pairs
🔗 Make regularized: VOLV0 → VOLVO
🔗 Regularized: CRV (HONDA) → CR-V
```

**Query Expansion:**
```
🔍 Make 'VOLV0 → VOLVO (123 records)' (cleaned: 'VOLV0') -> ID X
🔄 Make regularization expanded 1 → 2 IDs
🔄 Regularization expanded IDs: Makes: 1 → 2, Models: 1 → 2
```

**Vehicle Type Filtering:**
```
🔄 Vehicle Type filter with regularization: Using EXISTS subquery to match regularization mappings
```

**Fuel Type Filtering (Triplet-Based):**
```
🔄 Fuel Type filter with regularization: Using EXISTS subquery with triplet matching (Make/Model/ModelYear, including pre-2017)
🔄 Fuel Type filter with regularization: Using EXISTS subquery with triplet matching (Make/Model/ModelYear, 2017+ only)
```

These messages help you understand when regularization is active, how IDs are being expanded, and which records are being included in fuel type filtering based on the pre-2017 toggle setting.
