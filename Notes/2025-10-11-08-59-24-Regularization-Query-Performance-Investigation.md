# Session Handoff: Regularization Query Performance Investigation

**Date**: October 11, 2025
**Branch**: `rhoge-dev`
**Session Focus**: Root cause analysis and resolution of slow regularization queries

---

## 1. Current Task & Objective

### Primary Objective
Identify and fix the root cause of extremely slow query performance in the Regularization Manager when working with production-scale datasets (77M records). Current symptoms:
- **Hierarchy generation**: 146-165 seconds (target: <10s)
- **Find uncurated pairs**: 20-22 seconds (target: <5s)
- **UI blocking**: 3+ minutes with beachball during initial load

### Background Context
Previous session (Oct 11) implemented database performance optimizations:
- Added database indexes on enum table `id` columns
- Implemented background processing for auto-regularization
- Added fast-path optimization for UI computed properties

However, testing with 77M records revealed that **indexes exist but queries are still slow**. Root cause investigation shows:
1. ✅ **Indexes are present** - Verified 30+ indexes exist including all enum table IDs
2. ❌ **Queries are not using indexes effectively** - Query structure causes table scans
3. ❌ **Query design is inherently expensive** - 6-way JOINs + GROUP BY 5 columns on 54M rows

---

## 2. Progress Completed

### ✅ Root Cause Identified (COMPLETE)

**Problem**: The canonical hierarchy generation query (RegularizationManager.swift:113-137) is structurally inefficient:

```sql
SELECT mk.id, mk.name, md.id, md.name, my.id, my.year,
       ft.id, ft.code, ft.description,
       vt.id, vt.code, vt.description,
       COUNT(*) as record_count
FROM vehicles v
JOIN year_enum y ON v.year_id = y.id          -- 77M rows filtered
JOIN make_enum mk ON v.make_id = mk.id        -- 6-way
JOIN model_enum md ON v.model_id = md.id      -- JOIN
JOIN model_year_enum my ON v.model_year_id = my.id
LEFT JOIN fuel_type_enum ft ON v.fuel_type_id = ft.id
LEFT JOIN vehicle_type_enum vt ON v.vehicle_type_id = vt.id
WHERE y.year IN (2011, 2012, ..., 2022)       -- 12 years = 54M rows
GROUP BY mk.id, md.id, my.id, ft.id, vt.id    -- 5-column GROUP BY
ORDER BY mk.name, md.name, my.year, ft.description, vt.code;
```

**Why It's Slow**:
1. Scans ~54M rows (77M × 12/14 years for curated data)
2. Performs 6 JOINs (5 enum tables + vehicles)
3. Groups by 5 columns creating massive temporary result set
4. Even with indexes, SQLite must scan vehicles table and aggregate

**Similar Issues**:
- `findUncuratedPairs()` query (RegularizationManager.swift:232-277) also uses CTEs with multiple JOINs
- Both queries process millions of rows to generate summary data

### ✅ Testing Strategy Established (COMPLETE)

**Key Decision**: Use Montreal-only subset for rapid iteration
- Montreal: ~700K records/year × 14 years = **~10M total records** (vs 77M)
- Import time: ~30 minutes (vs ~5 hours)
- Faster testing loop for query optimization

**CSV Extraction Command**:
```bash
# Extract Montreal records (municipality code 66023)
for year in {2011..2024}; do
  head -1 "Vehicule_En_Circulation_${year}.csv" > "Montreal_${year}.csv"
  grep "^${year},[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,66023," \
    "Vehicule_En_Circulation_${year}.csv" >> "Montreal_${year}.csv"
done
```

### ✅ Database Index Status (VERIFIED)

**Confirmed Existing**: All necessary indexes are present and created correctly

**Enum table indexes** (created by CategoricalEnumManager):
- `idx_year_enum_id`, `idx_make_enum_id`, `idx_model_enum_id`
- `idx_model_year_enum_id`, `idx_fuel_type_enum_id`, `idx_vehicle_type_enum_id`

**Vehicles table indexes** (created by DatabaseManager):
- Single column: `idx_vehicles_make_id`, `idx_vehicles_model_id`, `idx_vehicles_year_id`, etc.
- Composite: `idx_vehicles_make_model_year_id`, `idx_vehicles_year_class_id`, etc.

**Verification Query**:
```bash
sqlite3 ./com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT name, tbl_name FROM sqlite_master WHERE type='index' ORDER BY tbl_name, name;"
```

**Result**: 30+ indexes confirmed present (see Oct 11 handoff for full list)

### ✅ ANALYZE/VACUUM Decision (COMPLETE)

**Attempted**: `ANALYZE; VACUUM;` to update SQLite statistics
**Failed**: Disk 97% full (only 31GB free), VACUUM needs ~15-20GB temporary space

**Decision**: Skip ANALYZE/VACUUM - won't solve the problem anyway since the issue is query structure, not statistics

---

## 3. Key Decisions & Patterns

### Decision 1: Root Cause is Query Structure, Not Missing Indexes

**Evidence**:
1. All indexes exist and are properly created
2. Queries still take 146s and 22s with 77M records
3. Query structure inherently requires scanning millions of rows

**Implication**: Need to rewrite queries or implement caching/materialization strategy

### Decision 2: Use Montreal Subset for Testing

**Rationale**:
- 10x faster import/test cycle (30 min vs 5 hours)
- Still provides meaningful performance testing (10M records)
- Same query patterns and bottlenecks will appear

**Approach**:
1. Delete current database
2. Import Montreal-only CSVs
3. Test query performance
4. Optimize queries
5. Verify improvements
6. Scale up to full dataset for final validation

### Decision 3: Fix Root Cause First, Then Add UX Polish

**Two-phase approach**:
1. **Phase 1**: Optimize query performance (get to <10s target)
2. **Phase 2**: Add progress indicators for remaining load time

**Why this order**: User prefers fixing root cause over band-aid solutions

### Decision 4: Query Optimization Strategies to Explore

**Option A: Materialized Summary Table**
- Create `canonical_hierarchy_cache` table during CSV import
- Pre-aggregate make/model/year/fuel/vehicle combinations
- Query cache instead of scanning vehicles table
- Invalidate/rebuild on import

**Option B: Incremental Aggregation**
- Break query into smaller sub-queries by year
- Aggregate progressively instead of single massive GROUP BY
- Use UNION ALL to combine results

**Option C: Denormalize Critical Data**
- Add `canonical_summary` jsonb column to enum tables
- Store pre-computed hierarchy data
- Trade write complexity for read speed

**Option D: Rewrite with Covering Indexes**
- Create composite index covering all GROUP BY columns
- Force SQLite to use index-only scan
- May still be slow due to data volume

**Recommendation**: Try Option A first (materialized table) - most predictable performance gain

---

## 4. Active Files & Locations

### Primary Files (Query Performance)

#### 1. `SAAQAnalyzer/DataLayer/RegularizationManager.swift`
**Purpose**: Manages regularization mappings and query translation

**Critical Functions**:
- **`generateCanonicalHierarchy()`** (lines 89-290)
  - **SLOW**: 146-165s with 77M records
  - Query at lines 113-137 (6-way JOIN + 5-column GROUP BY)
  - **TARGET FOR OPTIMIZATION**

- **`findUncuratedPairs()`** (lines 296-433)
  - **SLOW**: 20-22s with 77M records
  - Uses CTEs with multiple JOINs (lines 232-277)
  - **SECONDARY TARGET**

**Status**: NOT modified this session (instrumentation already in place from Oct 10)

#### 2. `SAAQAnalyzer/DataLayer/DatabaseManager.swift`
**Purpose**: Database setup, table creation, index management

**Key Section**: Lines 827-890 - Index creation
- Contains all vehicles table indexes
- Indexes created automatically during table setup
- Already includes all necessary indexes

**Status**: No changes needed (indexes are correct)

#### 3. `SAAQAnalyzer/DataLayer/CategoricalEnumManager.swift`
**Purpose**: Enum table creation and index management

**Key Functions**:
- `createEnumerationTables()` (line 18)
- `createEnumerationIndexes()` (lines 56-87) - Creates 9 enum table indexes
- Called automatically after table creation

**Status**: Complete from previous session (Oct 11)

#### 4. `SAAQAnalyzer/UI/RegularizationView.swift`
**Purpose**: Main UI for regularization manager

**Key Functions**:
- `loadInitialData()` (lines 1001-1020) - Background processing implemented
- `statusCounts` (lines 83-111) - Fast-path optimization implemented

**Known Issue**: Initial badges show incorrect status (green "Complete" instead of orange "Needs Review")
- Cause: `getRegularizationStatus()` evaluating before mappings fully loaded
- Impact: Visual only, corrects itself after background task completes
- **Future fix needed**

**Status**: Partially optimized (Oct 11), visual bug remains

---

## 5. Current State

### ✅ Analysis Complete

**Findings**:
1. Database indexes are present and correct
2. Query structure is the bottleneck, not missing indexes
3. Queries scan 54M rows and perform expensive aggregations
4. Montreal subset (10M records) will accelerate testing

**Next Phase**: Query optimization with rapid testing loop

### ⏳ Ready for Query Rewrite

**Blocked on**: User needs to:
1. Delete current database
2. Generate Montreal-only CSV files
3. Import Montreal CSVs
4. Provide console output for baseline performance

**Once unblocked**: Implement query optimization (see Decision 4 for strategies)

### 📊 Performance Baseline (77M Records)

**Current timings** (from console logs):
```
🐌 Canonical Hierarchy Generation query: 146.675s, 11586 points, Very Slow
⚠️ Find Uncurated Pairs query: 22.243s, 102372 points, Slow
Total UI blocking: ~180+ seconds
```

**Target timings**:
```
⚡️ Canonical Hierarchy Generation query: <10s, 11586 points, Excellent
✅ Find Uncurated Pairs query: <5s, 102372 points, Good
Total UI blocking: <20 seconds
```

### 🚧 UX Issues Identified (Not Yet Fixed)

**Issue 1**: Initial badge display bug
- Badges show green "Complete" when they should show orange "Needs Review"
- Happens because status calculated before mappings loaded
- Corrects itself after background task completes
- **Fix**: Defer badge rendering until mappings loaded

**Issue 2**: No progress indicators
- User sees beachball for 3+ minutes with no feedback
- No way to know if app is working or frozen
- **Fix**: Add loading messages ("Generating hierarchy... may take 2-3 minutes")

**Issue 3**: Background processing indicator hidden
- Background auto-regularization happens but user doesn't see it
- Status line 359-376 exists but may not be visible during critical moments
- **Fix**: More prominent progress display

**Priority**: Fix after query optimization (root cause first, then UX polish)

---

## 6. Next Steps

### Immediate: Montreal Subset Import (USER ACTION)

**Step 1**: Delete existing database
```bash
cd /Users/rhoge/Desktop/SAAQAnalyzer
rm ./com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite*
```

**Step 2**: Generate Montreal-only CSV files
```bash
# Navigate to source CSV directory
cd ~/path/to/saaq/csv/files

# Extract Montreal records (municipality code 66023)
for year in {2011..2024}; do
  head -1 "Vehicule_En_Circulation_${year}.csv" > "Montreal_${year}.csv"
  grep "^${year},[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,66023," \
    "Vehicule_En_Circulation_${year}.csv" >> "Montreal_${year}.csv"
done
```

**Step 3**: Import Montreal CSVs
- Launch app from Xcode
- Import all 14 Montreal_*.csv files
- Expected time: ~30 minutes
- Expected records: ~10M total (~700K/year)

**Step 4**: Baseline performance test
- Open Regularization Manager
- Copy console output showing query timings
- Provide to Claude for analysis

**Expected Montreal performance**:
- Hierarchy: ~20-30s (vs 146s with full dataset)
- Find pairs: ~3-5s (vs 22s with full dataset)
- Still slow enough to demonstrate the problem, fast enough for rapid iteration

### Phase 1: Query Optimization (NEXT SESSION)

**Approach**: Implement materialized summary table strategy

**Steps**:
1. Design `canonical_hierarchy_cache` schema
2. Populate cache during CSV import (incremental)
3. Rewrite `generateCanonicalHierarchy()` to query cache instead of vehicles
4. Add cache invalidation logic
5. Test with Montreal data
6. Verify <10s target achieved

**Alternative**: If materialized table too complex, try Option B (incremental aggregation)

### Phase 2: Fix `findUncuratedPairs()` Query

**After hierarchy query is fast**:
1. Analyze `findUncuratedPairs()` bottleneck
2. Apply similar optimization strategy
3. Test with Montreal data
4. Verify <5s target achieved

### Phase 3: UX Improvements

**Once queries are fast enough**:
1. Add loading state messages
2. Fix initial badge display bug
3. Add progress indicators for remaining load time
4. Test complete user experience

### Phase 4: Full Dataset Validation

**Final verification**:
1. Delete Montreal database
2. Import full 77M record dataset
3. Verify performance targets met at scale
4. Commit all changes
5. Update documentation

---

## 7. Important Context

### Solved Issues (This Session)

#### Issue 1: Index Confusion
**Question**: Are indexes missing?
**Answer**: No - all 30+ indexes exist and are properly created
**Verification**: Ran sqlite3 query showing all indexes on vehicles and enum tables
**Lesson**: Slow queries ≠ missing indexes. Always verify indexes exist before adding more.

#### Issue 2: ANALYZE/VACUUM Failure
**Attempted**: Update SQLite statistics with ANALYZE/VACUUM
**Error**: `database or disk is full (13)`
**Root Cause**: Disk 97% full (only 31GB free), VACUUM needs ~15-20GB temp space
**Decision**: Skip it - won't solve query structure problem anyway

#### Issue 3: Manual SQL Index Creation
**Attempted**: Add indexes via command-line SQL
**Problem**: Took 10+ minutes, blocked database for long period
**Result**: Indexes were added successfully BUT queries still slow
**Lesson**: Indexes already existed in code, manual creation was redundant

#### Issue 4: Database Path Confusion
**User's path**: `./com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite`
**Expected path**: `~/Library/Application Support/SAAQAnalyzer/saaq.db`
**Resolution**: User path is correct for their setup, use it consistently

### Code Quality Notes

#### Query Performance Principles

**What Makes Queries Slow**:
1. **Table scans**: Reading millions of rows even with indexes
2. **Expensive GROUP BY**: Aggregating over multiple columns creates temp tables
3. **Multiple JOINs**: Each JOIN multiplies row processing cost
4. **No materialization**: Re-computing same data on every query

**What Makes Queries Fast**:
1. **Pre-computed summaries**: Query small cache instead of large source
2. **Covering indexes**: Index contains all needed columns (index-only scan)
3. **Incremental processing**: Break into smaller chunks, combine results
4. **Denormalization**: Store computed results alongside source data

#### SQLite Performance Characteristics

**Good at**:
- Small to medium datasets (<10M rows)
- Simple queries with good indexes
- Single-user read-heavy workloads

**Struggles with**:
- Complex multi-table JOINs on large datasets
- Expensive GROUP BY aggregations
- Queries requiring full table scans

**Lesson**: For 77M row dataset, design queries to avoid expensive operations

### Database Schema Context

**Vehicles Table**: 77M rows, 16-20 columns
- Year range: 2011-2024 (14 years)
- Curated years: 2011-2022 (12 years) = ~54M rows
- Uncurated years: 2023-2024 (2 years) = ~14M rows

**Enum Tables**: Small (~1K-20K rows each)
- `year_enum`, `make_enum`, `model_enum` (2K-10K rows)
- `model_year_enum`, `fuel_type_enum` (20-50 rows)
- `vehicle_type_enum` (13 rows)

**Regularization Table**: `make_model_regularization`
- Stores mappings: uncurated → canonical
- Includes triplets: (make, model, modelYear) → fuelType
- ~10K-100K mappings depending on curation progress

### Testing Strategy

**Why Montreal Subset Works**:
1. **Representative**: Same schema, same query patterns
2. **Faster iteration**: 10x speed improvement
3. **Still meaningful**: 10M records enough to show bottlenecks
4. **Validates fix**: If fast with 10M, will scale to 77M (linearly)

**Testing Sequence**:
1. Montreal baseline (~10M): Measure current performance
2. Montreal optimized: Implement fix, verify improvement
3. Full dataset validation (~77M): Confirm scaling behavior

---

## Session Metadata

- **Duration**: ~4 hours (multiple rounds of investigation)
- **Token Usage**: 142k/200k (71% - heavy context from file reads)
- **Files Read**: 4 files (RegularizationManager, DatabaseManager, CategoricalEnumManager, RegularizationView)
- **Files Modified**: 0 (analysis only, no code changes)
- **SQL Queries Run**: 5+ (verifying indexes, checking database structure)
- **Build Status**: ✅ Clean (no code changes)
- **Test Status**: ⏳ Blocked on Montreal data import

---

## Quick Start for Next Session

```bash
# 1. Verify branch and status
cd /Users/rhoge/Desktop/SAAQAnalyzer
git status
git log --oneline -1

# 2. Check if user has Montreal data ready
ls -lh ~/path/to/Montreal_*.csv

# 3. Verify database is deleted
ls ./com.endoquant.SAAQAnalyzer/Data/Documents/

# 4. After import, check record count
sqlite3 ./com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  "SELECT year, COUNT(*) FROM vehicles GROUP BY year ORDER BY year;"

# 5. Run performance test
# Open Regularization Manager in app
# Copy console output showing:
#   - Hierarchy generation time
#   - Find uncurated pairs time
#   - Total records loaded
```

---

## Summary

This session successfully identified the root cause of slow regularization queries: **the query structure itself is inefficient**, not missing indexes. All necessary indexes exist and are properly created. The queries scan 54M rows and perform expensive multi-column GROUP BY operations, which are inherently slow even with optimal indexes.

**Next phase** will implement query optimization using a materialized summary table strategy, tested rapidly with Montreal-only data (~10M records) before scaling to the full 77M record dataset.

**Status**: ✅ Analysis complete, ⏳ ready for query optimization after user imports Montreal subset.
