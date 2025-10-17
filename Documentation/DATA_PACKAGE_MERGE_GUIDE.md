# Data Package Merge Mode Guide

**Last Updated:** October 16, 2025
**Version:** 1.0

## Overview

SAAQAnalyzer's data package import system supports two modes:
1. **Replace Mode** - Fast file replacement (recommended for backups)
2. **Merge Mode** - Selective import of non-overlapping data types

This document explains how Merge Mode works, when to use it, and important safety restrictions.

---

## Import Modes

### Replace Mode (Fast Path)
**Use When:**
- Restoring a complete backup
- Importing a package that contains all the data you need
- Starting fresh with new data

**Behavior:**
- Replaces entire database with package contents
- Fast simple file copy operation
- All existing data is overwritten

**Example Scenarios:**
```
✓ Empty database → Import full backup (vehicles + licenses)
✓ Old data → Import fresh export from another machine
✓ Testing → Replace test data with production backup
```

---

### Merge Mode (Selective Import)
**Use When:**
- Importing ONE data type into a database that has ONLY the OTHER type
- Adding licenses to a vehicle-only database
- Adding vehicles to a license-only database

**Behavior:**
- Imports data from package
- Preserves data types NOT in package
- **Enforces non-overlap safety check**

**Example Scenarios:**
```
✓ SAFE: Vehicle-only database + License-only package = Combined database
✓ SAFE: License-only database + Vehicle-only package = Combined database
✗ BLOCKED: Vehicle database + Vehicle package (overlap!)
✗ BLOCKED: Mixed database + Mixed package (overlap!)
```

---

## Safety Restrictions

### ⚠️ Merge Mode Conflict Detection

Merge mode **automatically blocks** imports when data types overlap:

#### Blocked Scenarios

**1. Same data type in both places**
```
Current Database: 14,000 vehicles
Package: 12,000 vehicles
Result: ❌ BLOCKED - Cannot merge vehicles into database that already has vehicles
```

**2. Package contains both data types**
```
Current Database: 14,000 vehicles
Package: 12,000 vehicles + 10,000 licenses
Result: ❌ BLOCKED - Package has vehicles which conflicts with existing vehicles
```

**3. Both databases have both types**
```
Current Database: 14,000 vehicles + 10,000 licenses
Package: 12,000 vehicles + 8,000 licenses
Result: ❌ BLOCKED - Multiple conflicts detected
```

### Why These Restrictions?

**Problem Without Restrictions:**
- `INSERT OR REPLACE` would silently overwrite records
- Unclear which version (package vs current) should win
- Risk of losing data from partial overlap
- No clear semantics for merging year ranges

**Example of Dangerous Scenario:**
```
Current DB: Vehicles for years 2011-2020 (Montreal only)
Package: Vehicles for years 2015-2024 (Quebec City only)

Without restriction:
- Years 2015-2020 would have BOTH cities merged (maybe OK?)
- But what if years 2015-2020 in package also had Montreal data?
- Which Montreal data wins? Package or current? (UNCLEAR!)
```

---

## Workarounds for Blocked Merges

If you need to merge overlapping data, use one of these approaches:

### Option 1: Use Replace Mode Instead
**Best for:** When package represents the complete desired state

```
1. Export your current data first (as backup)
2. Import the new package in REPLACE mode
3. If needed, manually re-import the backup as separate package
```

### Option 2: Export Data Separately
**Best for:** Combining data from multiple sources

```
1. Export current vehicles to vehicle-only package
2. Export current licenses to license-only package
3. Delete current database
4. Import vehicle package in REPLACE mode
5. Import license package in MERGE mode
```

### Option 3: Manual SQLite Merge (Advanced)
**Best for:** Complex partial overlaps

```
1. Use SQLite command line tools
2. Attach both databases
3. Write custom SQL to merge with your desired logic
4. Export result as new package
```

---

## Technical Implementation Details

### Merge Algorithm (When Allowed)

```
1. Validate package structure
2. Detect current database content (vehicles? licenses?)
3. Detect package content (vehicles? licenses?)
4. Check for conflicts:
   - IF (current has vehicles AND package has vehicles) → BLOCK
   - IF (current has licenses AND package has licenses) → BLOCK
5. If no conflicts:
   - Copy package database to temp location
   - ATTACH current database
   - INSERT OR REPLACE data to preserve from current
   - DETACH current database
   - Replace current with merged temp
6. Rebuild filter cache from merged database
7. Trigger UI refresh
```

### Enumeration Table Handling

When merging, enumeration tables are intelligently combined:

**Shared Tables** (merged for both types):
- `year_enum`
- `admin_region_enum`
- `mrc_enum`
- `municipality_enum`

**Vehicle-Specific Tables** (merged only when preserving vehicles):
- `vehicle_class_enum`, `vehicle_type_enum`
- `make_enum`, `model_enum`, `fuel_type_enum`
- `color_enum`, `cylinder_count_enum`, `axle_count_enum`, `model_year_enum`

**License-Specific Tables** (merged only when preserving licenses):
- `license_type_enum`, `age_group_enum`
- `gender_enum`, `experience_level_enum`

**Merge Strategy:** `INSERT OR IGNORE` - Keeps target's existing IDs, adds new ones from source

---

## Error Messages

### Conflict Detection Error

```
Cannot merge: Data type conflict detected!

Current database: Vehicle and License data
Package contents: Vehicle data only

Merge mode only works when importing non-overlapping data types:
✓ Import licenses into vehicle-only database
✓ Import vehicles into license-only database
✗ Import vehicles when database already has vehicles
✗ Import licenses when database already has licenses

To import this package, please:
1. Use REPLACE mode instead (replaces entire database), OR
2. Export your current data first, then import both packages separately

This restriction prevents accidental data loss from overlapping records.
```

### UI Prevention

The conflict check happens BEFORE any database changes:
- Safe - no data is modified before validation
- Clear error message explains the conflict
- Suggests appropriate alternatives

---

## Best Practices

### ✅ DO:
1. **Use Replace mode for full backups** - Fast and straightforward
2. **Export data separately** - Create vehicle-only and license-only packages
3. **Test imports on copies** - Verify behavior before importing to production
4. **Read error messages** - They explain exactly what's wrong and how to fix it

### ❌ DON'T:
1. **Don't assume merge will "figure it out"** - Overlap is explicitly blocked
2. **Don't try to merge partial year ranges** - Not currently supported
3. **Don't ignore the conflict error** - It's protecting your data

---

## Future Enhancements (Potential)

These features are NOT currently implemented but could be added:

1. **Smart Merge with Conflict Resolution**
   - UI to choose which records win (package vs current)
   - Year-range based merging (keep 2011-2015 from current, 2016+ from package)
   - Field-level merge strategies

2. **Incremental Merge**
   - Add only NEW years from package
   - Update only CHANGED records
   - Preserve unchanged data

3. **Three-Way Merge**
   - Base state + Package A + Package B
   - Automatic conflict detection
   - Manual conflict resolution UI

**Note:** Current simple merge logic is intentionally conservative to prevent data loss.

---

## Summary

**Merge Mode Philosophy:**
- **Conservative:** Blocks ambiguous scenarios
- **Safe:** No data loss from unclear merge semantics
- **Clear:** Explicit error messages with workarounds
- **Simple:** Only handles non-overlapping data types

**When in doubt, use Replace mode** - It's faster and has clearer semantics.

---

## Related Documentation

- [Data Package Export Guide](DATA_PACKAGE_EXPORT_GUIDE.md) - How to create packages
- [Database Schema Guide](../CLAUDE.md#database-schema) - Understanding data structure
- [Import Workflow](DATA_IMPORT_WORKFLOW.md) - CSV and package import processes

---

**Questions or Issues?**
See: [GitHub Issues](https://github.com/OpenMobilityData/SAAQAnalyzer/issues)
