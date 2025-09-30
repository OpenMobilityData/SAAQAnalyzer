-- Check if integer columns are populated in vehicles table
SELECT
    COUNT(*) as total_rows,
    COUNT(year_id) as year_id_populated,
    COUNT(classification_id) as classification_id_populated,
    COUNT(fuel_type_id) as fuel_type_id_populated,
    COUNT(admin_region_id) as admin_region_id_populated,
    COUNT(make_id) as make_id_populated,

    -- Show sample data
    year_id,
    classification_id,
    fuel_type_id,
    admin_region_id,
    make_id,

    -- Compare with original string columns
    year,
    classification,
    fuel_type,
    admin_region,
    make

FROM vehicles
LIMIT 5;