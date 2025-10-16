# Axle-Based RWI Implementation - Summary

**Date**: October 16, 2025
**Status**: ✅ Core implementation complete

## What Was Implemented

### 1. Enhanced RWI Calculation ✅
Updated Road Wear Index to use **actual axle count data** (`max_axles`) when available, with intelligent fallback to vehicle type assumptions.

**Files Modified:**
- `DatabaseManager.swift` (lines ~1248-1270)
- `OptimizedQueryManager.swift` (lines ~631-655)

**RWI Coefficients:**
| Axles | Weight Distribution | Coefficient | Source |
|-------|---------------------|-------------|--------|
| 2     | 45/55               | 0.1325      | Actual data (BCA) or fallback |
| 3     | 30/35/35            | 0.0381      | Actual data (BCA) or fallback |
| 4     | 25/25/25/25         | 0.0156      | Actual data (BCA) |
| 5     | 20% each            | 0.0080      | Actual data (BCA) |
| 6+    | 16.67% each         | 0.0046      | Actual data (BCA) |

**SQL Logic:**
```sql
CASE
    -- Use actual axle data when available (BCA trucks)
    WHEN max_axles = 2 THEN 0.1325 * POWER(net_mass, 4)
    WHEN max_axles = 3 THEN 0.0381 * POWER(net_mass, 4)
    WHEN max_axles = 4 THEN 0.0156 * POWER(net_mass, 4)
    WHEN max_axles = 5 THEN 0.0080 * POWER(net_mass, 4)
    WHEN max_axles >= 6 THEN 0.0046 * POWER(net_mass, 4)
    -- Fallback for NULL max_axles: vehicle type assumptions
    WHEN vehicle_type_id = 'CA' OR 'VO' THEN 0.0381 * POWER(net_mass, 4)
    WHEN vehicle_type_id = 'AB' THEN 0.1325 * POWER(net_mass, 4)
    ELSE 0.1325 * POWER(net_mass, 4)  -- Cars and others
END
```

### 2. Axle Count as Numeric Metric ✅
Added axle count to available numeric metrics (Average, Min, Max, Sum).

**Files Modified:**
- `DataModels.swift`:
  - Added `.axleCount` to `ChartMetricField` enum (line 1372)
  - Configured `databaseColumn` as `"max_axles"` (line 1387)
  - Set `isApplicable` to vehicle-only (line 1425)

**Use Cases:**
- "What's the average axle count for Kenworth trucks over time?"
- "Show min/max axle configurations by year"
- "Total axle count across the fleet"

## What Was NOT Implemented

### Axle Count as Categorical Filter ⏸️
Deferred due to token constraints. Can be added later if needed.

**Would require:**
- Add `selectedAxleCounts: Set<Int>` to `FilterConfiguration`
- Add UI filter section in `FilterPanel.swift`
- Add `loadAxleCountOptions()` in `FilterCacheManager.swift`
- Add WHERE clause binding in database query methods

**Low priority** because:
- Axle filtering can be achieved through vehicle class (BCA = trucks with axle data)
- Numeric metrics provide sufficient analytical capability

## Key Benefits

1. **Accuracy**: Uses actual SAAQ axle data instead of assumptions
2. **Granularity**: Distinguishes 2-6+ axle configurations
3. **Backwards Compatible**: Graceful fallback when axle data unavailable
4. **Engineering Valid**: Weight distribution models based on 4th power law

## Testing

**Recommended test query** (run after data import):
```sql
-- Compare RWI by axle configuration
SELECT
    max_axles,
    COUNT(*) as vehicle_count,
    AVG(0.1325 * POWER(net_mass, 4)) as avg_rwi_2axle_coef,
    AVG(CASE
        WHEN max_axles = 2 THEN 0.1325 * POWER(net_mass, 4)
        WHEN max_axles = 3 THEN 0.0381 * POWER(net_mass, 4)
        WHEN max_axles = 4 THEN 0.0156 * POWER(net_mass, 4)
        WHEN max_axles = 5 THEN 0.0080 * POWER(net_mass, 4)
        WHEN max_axles >= 6 THEN 0.0046 * POWER(net_mass, 4)
    END) as avg_rwi_actual
FROM vehicles
WHERE max_axles IS NOT NULL
  AND net_mass IS NOT NULL
  AND vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'CA')
GROUP BY max_axles
ORDER BY max_axles;
```

## Documentation

**Design Document**: `Notes/2025-10-16-Axle-Based-RWI-Design.md`
- Full weight distribution derivations
- Comparison table showing 97% reduction in road wear from 2→6 axles
- Test queries and validation strategies

## Future Enhancements

1. **Categorical Filter** (if needed): Add axle count as multi-select filter
2. **Visualization**: Chart showing RWI reduction by axle configuration
3. **Policy Analysis**: Compare regulatory limits vs. actual fleet composition
