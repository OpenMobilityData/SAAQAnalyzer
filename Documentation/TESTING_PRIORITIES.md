# SAAQAnalyzer - Testing Priorities & Coverage Map

## Quick Overview

**Document**: [TESTING_SURVEY.md](TESTING_SURVEY.md) - Full comprehensive testing survey
**Audience**: QA engineers, developers implementing test coverage
**Purpose**: Identify what to test, why it matters, and risk assessment

---

## Critical Testing Priorities (Must Test First)

### Tier 1: Foundation Components (HIGHEST RISK)

These components have complex logic critical to application correctness and performance.

| Component | Size | Risk Level | Why Critical | Existing Tests |
|-----------|------|-----------|-------------|-----------------|
| **QueryManager** | 1.3K | CRITICAL | Integer query execution, filter conversion, performance | ❌ NONE |
| **CategoricalEnumManager** | 787 | CRITICAL | Index creation (16x performance impact), schema setup | ❌ NONE |
| **FilterCacheManager** | 892 | CRITICAL | Cache initialization guards, data type awareness, regularization info | ❌ NONE |
| **RegularizationManager** | 1.9K | CRITICAL | Make/Model query translation, coupling logic, hierarchy generation | ❌ NONE |
| **DatabaseManager** | 7.8K | HIGH | Core DB abstraction, cache invalidation pattern, schema creation | ⚠️ BASIC |
| **CSVImporter** | 958 | HIGH | Character encoding, batch processing, year detection | ⚠️ PARTIAL |

### Tier 2: Functional Components (MEDIUM RISK)

These components implement important features but have less complex logic.

| Component | Size | Risk Level | Why Important | Existing Tests |
|-----------|------|-----------|-------------|-----------------|
| **DataModels** | 2.1K | MEDIUM | Data structure validation, statistics calculations | ❌ NONE |
| **ImportProgressManager** | 258 | MEDIUM | Progress tracking, stage progression | ❌ NONE |
| **FilterPanel** | 2.7K | MEDIUM | State management, hierarchical filtering UI | ❌ NONE |
| **ChartView** | 879 | MEDIUM | Metric formatting, normalization display | ❌ NONE |

### Tier 3: Supporting Components (LOW RISK)

Infrastructure and utilities with straightforward responsibilities.

| Component | Size | Risk Level | Why Safe | Existing Tests |
|-----------|------|-----------|----------|-----------------|
| **GeographicDataImporter** | 378 | LOW | Limited scope, simple parsing | ❌ NONE |
| **AppLogger** | ~200 | LOW | Infrastructure, logging only | ❌ NONE |
| **DataPackageManager** | 1.3K | LOW | Export functionality, separate concern | ❌ NONE |

---

## Critical Test Scenarios by Category

### 1. INTEGER ENUMERATION QUERY SYSTEM (Top Priority)

**Tests Needed** (QueryManager, CategoricalEnumManager):

- [ ] Filter string → ID conversion (extract parenthesized codes)
- [ ] Vehicle query with all filter combinations
- [ ] License query with all filter combinations
- [ ] RWI calculation with various axle counts
- [ ] Percentage metric with baseline subquery
- [ ] Coverage analysis (NULL vs non-NULL counting)
- [ ] Query plan analysis and performance detection
- [ ] Regularization with Make/Model coupling enabled/disabled
- [ ] Handle empty/missing filter values gracefully
- [ ] Verify all enum table ID indexes exist

**Risk if Not Tested**:
- Queries produce incorrect results (silent data corruption)
- Missing indexes cause 165s → <10s performance penalty
- Regularization coupling logic breaks hierarchical filtering

---

### 2. CACHE MANAGEMENT (Critical for Stability)

**Tests Needed** (FilterCacheManager, DatabaseManager):

- [ ] Cache initialization succeeds (all enum tables loaded)
- [ ] Dual-initialization guard prevents concurrent access
- [ ] Cache invalidation pattern (invalidate → initialize)
- [ ] Data type selective loading (vehicle vs. license)
- [ ] Regularization info accuracy (canonical mappings)
- [ ] Uncurated pair detection (curated year boundaries)
- [ ] Hierarchical model filtering (modelId → makeId mapping)
- [ ] Cache re-initialization after data import
- [ ] Stale data not served after database updates

**Risk if Not Tested**:
- Cache initialization hangs due to concurrent access bug
- Stale regularization data causes incorrect filtering
- Vehicle caches loaded for license imports (performance regression)

---

### 3. NORMALIZATION & TRANSFORMATION PIPELINE

**Tests Needed** (DatabaseManager, QueryManager):

- [ ] `normalizeToFirstYear()` divides all values by first year
- [ ] Normalization handles zero/negative first year values
- [ ] `applyCumulativeSum()` transforms series into cumulative values
- [ ] Order matters: normalize BEFORE cumulative sum
- [ ] Edge cases: single data point, NaN values, empty series
- [ ] Automatic 2-decimal precision detection for normalized values
- [ ] Legend formatting includes "Cumulative" prefix when enabled
- [ ] Y-axis labels indicate normalization state

**Risk if Not Tested**:
- Incorrect trend analysis (wrong normalization math)
- Cumulative sum applied before normalization (wrong order)
- UI displays wrong precision (confusing analysis)

---

### 4. CHARACTER ENCODING RESILIENCE

**Tests Needed** (CSVImporter):

- [ ] UTF-8 encoded CSV files parse correctly
- [ ] ISO-Latin-1 fallback for encoding issues
- [ ] Windows-1252 fallback for edge cases
- [ ] French diacritics preserved ("Montréal" not "MontrÃ©al")
- [ ] Common corruption patterns fixed
- [ ] Encoding detection doesn't crash on binary files
- [ ] Mixed encoding within same file handled gracefully

**Risk if Not Tested**:
- Imports fail silently with encoding errors
- French place names corrupted in database
- Users cannot import certain CSV file sources

---

### 5. REGULARIZATION MAKE/MODEL LOGIC

**Tests Needed** (RegularizationManager, QueryManager):

- [ ] Canonical hierarchy generation from curated years
- [ ] Year configuration changes trigger cache invalidation
- [ ] Query translation with coupling enabled
- [ ] Query translation with coupling disabled
- [ ] Make filter constrains Model filter options
- [ ] Model filter excludes makes not selected
- [ ] Uncurated year boundaries correctly defined
- [ ] Regularization mappings persisted correctly
- [ ] Performance: hierarchy generation <1 second (with cache)

**Risk if Not Tested**:
- Regularization disabled despite user enabling it
- Coupling logic inverted (Models not constrained by Makes)
- Massive performance regression (13.4s → 0.12s cache difference)

---

### 6. SCHEMA CREATION

**Tests Needed** (CategoricalEnumManager):

- [ ] All enumeration tables created with correct integer types
- [ ] All required indexes created on ID columns
- [ ] Foreign key relationships enforced
- [ ] NULL handling for optional fields (fuel_type, mrc)
- [ ] Validation detects orphaned records (missing enum values)

**Risk if Not Tested**:
- Missing indexes cause catastrophic performance issues
- NULL values in geographic fields cause filtering failures (2023-2024 MRC issue)
- Schema corruption prevents queries from executing

---

### 7. DATA TYPE AWARE CACHING

**Tests Needed** (CSVImporter, FilterCacheManager, DatabaseManager):

- [ ] Vehicle imports load vehicle-specific caches
- [ ] License imports load license-specific caches
- [ ] License imports don't load expensive vehicle caches
- [ ] Selective cache refresh by data type
- [ ] "Limit to Curated Years Only" filter updated correctly
- [ ] Geographic hierarchy loads for both vehicle and license

**Risk if Not Tested**:
- License imports hang 30+ seconds (unnecessary vehicle cache loading)
- Curated/uncurated filtering unavailable after import
- Performance regression on every import

---

### 8. CONCURRENT OPERATIONS & LOCKING

**Tests Needed** (All async components):

- [ ] Database path passed to concurrent tasks (not shared OpaquePointer)
- [ ] Cache refresh locking prevents concurrent attempts
- [ ] Progress tracking thread-safe with actor-based synchronization
- [ ] No segfaults from shared database connections
- [ ] CSV parsing parallelization doesn't corrupt data
- [ ] UI updates happen on MainActor

**Risk if Not Tested**:
- Segmentation faults from SQLite thread safety violations
- Data corruption from concurrent write attempts
- UI freezes from blocking operations

---

## Test Data & Fixtures

### Recommended Test Data Sets

```
SAAQAnalyzer/
├── SAAQAnalyzerTests/
│   ├── Fixtures/
│   │   ├── CSV_Files/
│   │   │   ├── Vehicule_2017_Sample_1000.csv      # Basic vehicle data
│   │   │   ├── Vehicule_2023_Encoding_Test.csv    # With diacritics anomalies
│   │   │   ├── Permis_2020_Sample_1000.csv        # License data
│   │   │   └── Vehicule_2015_Fuel_Null.csv        # Pre-2017 (no fuel_type)
│   │   ├── Geographic/
│   │   │   ├── d001_sample.txt                     # Minimal geographic data
│   │   │   └── d001_hierarchy_test.txt             # Hierarchy validation
│   │   └── Regularization/
│   │       └── sample_mappings.csv                 # Make/Model corrections
│   ├── DatabaseFixture.swift                       # Ephemeral test database
│   └── SampleDataGenerator.swift                   # Synthetic test data
```

### CSV File Considerations

- **Minimal (1-10 records)**: Basic CRUD testing, quick turnaround
- **Small (100-1K records)**: Comprehensive functional testing
- **Medium (10K records)**: Real-world pattern testing
- **Large (100K+ records)**: Performance benchmark suite (separate from unit tests)

**Real SAAQ Data Issues to Test**:
- 2023-2024: MRC field is NULL (geographic filtering limitation)
- Pre-2017: fuel_type field NULL
- Encoding: French diacritics in place names (Montréal, Trois-Rivières)

---

## Coverage Assessment: Existing Tests vs. Needed Tests

### Existing Test Coverage

```
✅ DatabaseManagerTests (80 lines)
   - Database connection
   - Table existence checks
   - Basic query functionality
   
✅ CSVImporterTests (200 lines)
   - Vehicle CSV import
   - License CSV import
   - Character encoding tests
   
✅ FilterCacheTests (150 lines)
   - Cache separation (vehicle vs. license)
   - Cache persistence
   - Data retrieval
   
⚠️ WorkflowIntegrationTests (100 lines)
   - End-to-end workflows
   
❌ No UI Tests
   - FilterPanel state management
   - ChartView rendering
   - Data export functionality
```

### Coverage Gaps (Priority Order)

**Tier 1 - MUST HAVE** (estimated 500+ tests):
1. QueryManager - Filter conversion, RWI calc, regularization (150 tests)
2. CategoricalEnumManager - Schema creation, index validation (80 tests)
3. FilterCacheManager - Initialization guards, data type awareness (100 tests)
4. RegularizationManager - Query translation, coupling logic (120 tests)
5. Normalization pipeline - Edge cases, transformation order (50 tests)

**Tier 2 - SHOULD HAVE** (estimated 200+ tests):
1. SchemaManager - Migration pipeline steps, validation (60 tests)
2. DataModels - Statistics calculations, age computation (40 tests)
3. ImportProgressManager - Stage progression, batch tracking (40 tests)
4. GeographicDataImporter - Hierarchy parsing, relationships (30 tests)
5. Basic UI tests - FilterPanel loading, ChartView rendering (30 tests)

**Tier 3 - NICE TO HAVE** (estimated 100+ tests):
1. Performance benchmarks - Query execution time, index effectiveness
2. UI state synchronization - Cross-component state consistency
3. Error recovery - Partial import handling, graceful failures
4. Memory management - Large dataset handling, leak detection

---

## Test Execution Strategy

### Phase 1: Foundation (Week 1-2)
Build test infrastructure and test Tier 1 critical components.

```bash
# Setup
1. Create test database fixtures
2. Create sample CSV files
3. Create synthetic data generators

# Tests
4. CategoricalEnumManager tests (schema, indexes)
5. FilterCacheManager tests (initialization, guards)
6. QueryManager tests (filter conversion, queries)
7. RegularizationManager tests (translation, coupling)
8. Normalization pipeline tests (math correctness)
```

### Phase 2: Functional (Week 2-3)
Test Tier 2 components and integration points.

```bash
1. DatabaseManager tests (cache invalidation pattern)
2. CSVImporter tests (character encoding edge cases)
3. SchemaManager tests (migration safety)
4. Data model tests (statistics calculations)
5. ImportProgressManager tests (stage tracking)
```

### Phase 3: UI & Integration (Week 3-4)
Add UI tests and end-to-end validation.

```bash
1. FilterPanel tests (state management, hierarchical filtering)
2. ChartView tests (metric formatting, normalization display)
3. DataInspectorView tests (export functionality)
4. Workflow integration tests (import → query → display)
5. Performance benchmarks (index effectiveness)
```

---

## Quick Reference: Known Pitfalls

From CLAUDE.md - Architectural Rules:

| Rule | Violation Risk | Test Strategy |
|------|---------------|----------------|
| Integer enumeration IDs only | Silent data corruption | Verify all queries use `_id` columns |
| Enum table ID indexes required | 165s performance penalty | Query plan analysis + execution timing |
| Invalidate BEFORE initialize | Stale data served | Test cache refresh cycle |
| No `.onChange` for filters | AttributeGraph crashes | Manual button triggers only |
| >100ms ops in background | UI freeze (beachball) | Background task execution tests |
| Pass DB path, not connection | Segmentation faults | Concurrent task isolation tests |
| Parent-scope expensive ViewModels | 60+ second reopen delay | ViewModel lifecycle tests |

---

## Success Criteria

### Test Coverage Targets
- **Tier 1 Components**: 80%+ branch coverage
- **Tier 2 Components**: 60%+ branch coverage
- **Tier 3 Components**: 40%+ coverage (infrastructure, lower risk)
- **Overall**: 70% codebase coverage minimum

### Performance Validation
- Query execution: All queries <10s (with indexes)
- Cache initialization: <500ms
- Hierarchy generation: <1s (with cache)
- RWI calculation: <100ms

### Reliability Standards
- Zero segmentation faults from concurrency
- Zero silent data corruption
- Character encoding: 100% diacritics preserved
- Cache consistency: No stale data served

---

## Resources

- **Full Survey**: [TESTING_SURVEY.md](TESTING_SURVEY.md)
- **Architecture Guide**: [ARCHITECTURAL_GUIDE.md](ARCHITECTURAL_GUIDE.md)
- **Quick Reference**: [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
- **Critical Rules**: See CLAUDE.md in repository root

