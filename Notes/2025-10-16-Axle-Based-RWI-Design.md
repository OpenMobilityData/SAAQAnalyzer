# Axle-Based Road Wear Index (RWI) Implementation - Design Document

**Date**: October 16, 2025
**Status**: Design Phase
**Goal**: Use actual axle count data (`max_axles`) to improve RWI calculation accuracy

## Background

The `NB_ESIEU_MAX` field in SAAQ CSV data provides actual axle counts for BCA class trucks (values 2-6, where 6 = "6 or more"). Currently, RWI uses hardcoded assumptions based on vehicle type:
- Trucks (CA): Assume 3 axles
- Buses (AB): Assume 2 axles
- Cars (AU): Assume 2 axles

## Proposed Enhancement

Use actual `max_axles` data when available (BCA trucks only), fall back to vehicle-type assumptions for other classes.

## Weight Distribution Models

### Engineering Basis
- Road wear follows 4th power law: damage ∝ (axle_load)^4
- Weight distribution depends on cargo placement, axle spacing, and vehicle design
- General principle: More axles = better weight distribution = lower per-axle load = less road damage

### Proposed Models

#### 2-Axle Vehicles
- **Distribution**: 45% front, 55% rear
- **RWI Coefficient**: (0.45^4 + 0.55^4) = 0.0410 + 0.0915 = **0.1325**
- **Rationale**: Slightly rear-biased for loaded trucks
- **Used for**: 2-axle trucks, buses, cars (when no axle data available)

#### 3-Axle Vehicles (Current Implementation)
- **Distribution**: 30% front, 35% rear1, 35% rear2
- **RWI Coefficient**: (0.30^4 + 0.35^4 + 0.35^4) = 0.0081 + 0.0150 + 0.0150 = **0.0381**
- **Rationale**: Tandem rear axles spread weight
- **Used for**: 3-axle trucks

#### 4-Axle Vehicles
- **Distribution**: 25% front, 25% rear1, 25% rear2, 25% rear3
- **RWI Coefficient**: (0.25^4 + 0.25^4 + 0.25^4 + 0.25^4) = 4 × 0.0039 = **0.0156**
- **Rationale**: Even distribution across all axles
- **Used for**: 4-axle trucks (often tri-axle tractors or rigid trucks)

#### 5-Axle Vehicles
- **Distribution**: 20% front, 20% × 4 rear axles
- **RWI Coefficient**: 5 × (0.20^4) = 5 × 0.0016 = **0.0080**
- **Rationale**: Typical 5-axle semi-trailer configuration
- **Used for**: 5-axle trucks (standard tractor-trailer)

#### 6+ Axle Vehicles
- **Distribution**: Assume 6 axles, 16.67% each
- **RWI Coefficient**: 6 × (0.1667^4) = 6 × 0.0007716 = **0.0046**
- **Rationale**: Heavy multi-trailer configurations
- **Used for**: 6+ axle trucks (B-trains, multi-trailer combinations)

### Comparison Table

| Axles | Weight Distribution | RWI Coefficient | Relative Damage (vs 2-axle) |
|-------|---------------------|-----------------|----------------------------|
| 2     | 45/55              | 0.1325          | 100% (baseline)            |
| 3     | 30/35/35           | 0.0381          | 29% (-71%)                 |
| 4     | 25/25/25/25        | 0.0156          | 12% (-88%)                 |
| 5     | 20/20/20/20/20     | 0.0080          | 6% (-94%)                  |
| 6+    | 16.67 × 6          | 0.0046          | 3% (-97%)                  |

**Key Insight**: A 6-axle truck causes 97% less road damage per kg of mass compared to a 2-axle truck!

## Implementation Strategy

### 1. Enhanced RWI Calculation (SQL)

```sql
CASE
    -- Use actual axle data when available (BCA trucks with max_axles populated)
    WHEN max_axles = 2 THEN 0.1325 * POWER(net_mass, 4)
    WHEN max_axles = 3 THEN 0.0381 * POWER(net_mass, 4)
    WHEN max_axles = 4 THEN 0.0156 * POWER(net_mass, 4)
    WHEN max_axles = 5 THEN 0.0080 * POWER(net_mass, 4)
    WHEN max_axles >= 6 THEN 0.0046 * POWER(net_mass, 4)

    -- Fallback: Use vehicle type assumptions when max_axles is NULL
    WHEN vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code IN ('CA', 'VO'))
        THEN 0.0381 * POWER(net_mass, 4)  -- Assume 3 axles for trucks/tool vehicles
    WHEN vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'AB')
        THEN 0.1325 * POWER(net_mass, 4)  -- Assume 2 axles for buses
    ELSE 0.1325 * POWER(net_mass, 4)      -- Assume 2 axles for cars/others
END
```

### 2. Axle Count as Numeric Metric

Add to `ChartMetricType` enum:
- `.axleCount` with aggregation modes: average, min, max, sum

Use cases:
- "What's the average axle count for Kenworth trucks over time?"
- "Show min/max axle configurations by year"

### 3. Axle Count as Categorical Filter

Add to filter UI similar to cylinder count:
- Multi-select checkboxes: "2 axles", "3 axles", "4 axles", "5 axles", "6+ axles"
- Uses existing `axle_count_enum` table and `axle_count_id` foreign key

Use cases:
- "Count 3-axle trucks by year"
- "Show fuel types for 5-axle trucks"

## Files to Modify

### 1. DataModels.swift
- Add `.axleCount` case to `ChartMetricType` enum
- Add `selectedAxleCounts: Set<Int>` to `FilterConfiguration`
- Add `selectedAxleCountIds: Set<Int>` to `IntegerFilterConfiguration`

### 2. DatabaseManager.swift
- Update RWI query in `queryVehicleData()` to use axle-based logic
- Add `.axleCount` metric case with AVG/MIN/MAX/SUM queries
- Add axle count filter binding to WHERE clause

### 3. OptimizedQueryManager.swift
- Mirror RWI changes for integer-based queries
- Add axle count metric support

### 4. FilterPanel.swift
- Add axle count metric option to metric type picker
- Add axle count filter section (similar to cylinder count)

### 5. FilterCacheManager.swift
- Add `loadAxleCountOptions()` method
- Populate axle count filter dropdown from `axle_count_enum`

## Testing Strategy

### Test Queries (Run after data import)

```sql
-- 1. Verify axle data coverage
SELECT
    COUNT(*) FILTER (WHERE max_axles IS NOT NULL) as with_axles,
    COUNT(*) FILTER (WHERE max_axles IS NULL) as without_axles,
    ROUND(100.0 * COUNT(*) FILTER (WHERE max_axles IS NOT NULL) / COUNT(*), 2) as coverage_pct
FROM vehicles;

-- 2. RWI comparison: old vs new method
SELECT
    year,
    -- Old method (hardcoded 3-axle assumption for all trucks)
    AVG(0.0381 * POWER(net_mass, 4)) as old_rwi,
    -- New method (actual axle data)
    AVG(CASE
        WHEN max_axles = 2 THEN 0.1325 * POWER(net_mass, 4)
        WHEN max_axles = 3 THEN 0.0381 * POWER(net_mass, 4)
        WHEN max_axles = 4 THEN 0.0156 * POWER(net_mass, 4)
        WHEN max_axles = 5 THEN 0.0080 * POWER(net_mass, 4)
        WHEN max_axles >= 6 THEN 0.0046 * POWER(net_mass, 4)
        ELSE 0.0381 * POWER(net_mass, 4)
    END) as new_rwi
FROM vehicles
WHERE vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'CA')
  AND net_mass IS NOT NULL
GROUP BY year
ORDER BY year;

-- 3. Axle count distribution by make
SELECT
    me.code as make,
    v.max_axles,
    COUNT(*) as count
FROM vehicles v
JOIN make_enum me ON v.make_id = me.id
WHERE v.max_axles IS NOT NULL
  AND v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'CA')
GROUP BY me.code, v.max_axles
ORDER BY count DESC
LIMIT 20;
```

## Benefits

1. **Accuracy**: Use actual axle data instead of assumptions
2. **Flexibility**: Analyze axle configurations as both metric and filter
3. **Insights**: Reveal how truck configurations change over time
4. **Backwards Compatible**: Graceful fallback when axle data unavailable

## Limitations

1. **Coverage**: Only BCA trucks have `max_axles` data
2. **Approximation**: Weight distributions are engineering estimates
3. **Trailer Ambiguity**: `max_axles` includes trailers, not just power unit

## Next Steps

1. ✅ Design weight distribution models (this document)
2. ⏳ Implement enhanced RWI calculation
3. ⏳ Add axle count as numeric metric
4. ⏳ Add axle count as categorical filter
5. ⏳ Test with real data
6. ⏳ Update documentation
