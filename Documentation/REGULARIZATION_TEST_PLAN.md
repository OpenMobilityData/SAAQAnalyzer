# Make/Model Regularization System - Test Plan
**Database:** Abbreviated dataset (1,000 records per year, 2011-2024)
**Generated:** October 8, 2025

---

## Database Analysis Summary

### Current State
- **Years:** 2011-2024 (1,000 records each = 14,000 total)
- **Curated years:** 2011-2022 (assumed clean data)
- **Uncurated years:** 2023-2024 (contains typos/truncations)
- **Existing mappings:** 2
  1. HONDA CRV → HONDA CR-V (14 records)
  2. JHOND 6330 → JOHND 6300 (1 record)

### Key Patterns Found

**Most Common Uncurated Make/Model Pairs (2023-2024):**
- CANA OUTLA: 27 records (only in 2023-2024)
- HONDA CRV: 14 records (already mapped)
- GMC SIE: 11 records
- CFMOT CFORC: 11 records
- MAZDA CX3: 7 records
- CANA DEFEN: 5 records
- HONDA HRV: 4 records
- CANA MAVER: 4 records

**Make Variants Detected:**
- **CANA vs CAN-A vs CANAM vs CANAN** (Can-Am ATVs)
  - CAN-A appears in 2011-2022 (64 records)
  - CANA appears in 2023-2024 (42 records)
  - CANAM appears in 2023-2024 (4 records)
  - CANAN appears in 2024 (1 record)

**Model Truncations:**
- OUTLA vs OUTLAN vs OUTLM (Outlander)
- CRV vs CR-V (already mapped)
- CX3 vs CX-3
- HRV vs HR-V
- SIE vs SIERRA
- COROL vs COROLLA

---

## Test Case Suite

### 🧪 Test Group 1: Existing Mappings (Verify Working Features)

#### TC1.1: HONDA CRV Badge Display
**Steps:**
1. Open app with regularization OFF
2. Open Filter Panel
3. Check Model dropdown

**Expected:**
- Badge: `"CRV (HONDA) [uncurated: 14 records]"`

**Steps (continued):**
4. Create mapping: HONDA CRV → HONDA CR-V (already exists)
5. Close RegularizationView
6. Check Model dropdown again

**Expected:**
- Badge: `"CRV (HONDA) → HONDA CR-V (14 records)"`

---

#### TC1.2: HONDA CRV Query Behavior (Regularization OFF)
**Steps:**
1. Set regularization to OFF
2. Filter: Years = 2023-2024, Model = "CRV (HONDA) [uncurated: 14 records]"
3. Check record count

**Expected:**
- 14 records (CRV only, not CR-V)

**Steps (continued):**
4. Filter: Years = 2011-2022, Model = "CR-V (HONDA)"
5. Check record count

**Expected:**
- 197 records (CR-V only, not CRV)

---

#### TC1.3: HONDA CRV Query Behavior (Regularization ON, Coupled)
**Steps:**
1. Set regularization to ON, coupling to ON
2. Filter: Years = 2011-2024, Model = "CRV (HONDA) → HONDA CR-V (14 records)"
3. Check console output for expansion messages
4. Check record count

**Expected Console:**
```
🔍 Model 'CRV (HONDA) → HONDA CR-V (14 records)' (cleaned: 'CRV') -> ID 1494
🔄 Uncurated Model (9,1494) → Canonical (9,218)
🔗 Regularized: CRV (HONDA) → HONDA CR-V
🔄 Model regularization expanded 1 → 2 IDs (with associated Makes)
```

**Expected Result:**
- 211 records (197 CR-V from 2011-2022 + 14 CRV from 2023-2024)
- Query includes both model IDs: 218 (CR-V) and 1494 (CRV)
- Make constraint applied (only HONDA id=9)

---

#### TC1.4: HONDA CRV Query Behavior (Regularization ON, Decoupled)
**Steps:**
1. Set regularization to ON, coupling to OFF
2. Filter: Years = 2011-2024, Model = "CRV (HONDA) → HONDA CR-V (14 records)" (NO Make selected)
3. Check record count

**Expected Result:**
- 211 records (same as coupled mode because only HONDA makes CR-V/CRV)
- Query includes model IDs: 218, 1494
- NO Make constraint (decoupled mode)

---

#### TC1.5: JHOND Make Badge Display
**Steps:**
1. Open Filter Panel
2. Check Make dropdown

**Expected:**
- Badge: `"JHOND → JOHND (1 records)"` (derived from Make/Model mapping)

---

#### TC1.6: JHOND Query Behavior (Regularization ON)
**Steps:**
1. Set regularization to ON
2. Filter: Years = 2011-2024, Make = "JHOND → JOHND (1 records)"
3. Check console output
4. Check record count

**Expected Console:**
```
🔍 Make 'JHOND → JOHND (1 records)' (cleaned: 'JHOND') -> ID 194
🔄 Uncurated Make 194 → Canonical 27
🔗 Make regularized: JHOND → JOHND
🔄 Make regularization expanded 1 → 2 IDs
```

**Expected Result:**
- 3 records (2 from JOHND + 1 from JHOND)
- Query includes make IDs: 27 (JOHND) and 194 (JHOND)

---

### 🧪 Test Group 2: Can-Am Make Variants (Complex Test)

#### TC2.1: Identify Can-Am Variants
**Steps:**
1. Open RegularizationView
2. Enable "Show Exact Matches" toggle
3. Search uncurated pairs for CANA

**Expected:**
- CANA OUTLA: 27 records
- CANA DEFEN: 5 records
- CANA MAVER: 4 records
- CANAM OUTLM: 2 records
- CANAM DEFEN: 2 records
- CANAM MAVER: 1 record
- CANAN MAVER: 1 record

---

#### TC2.2: Create CANA → CAN-A Mapping
**Steps:**
1. Select "CANA OUTLA" from list
2. In canonical hierarchy, select Make = "CAN-A", Model = "OUTLA"
3. Assign FuelType = Essence, VehicleType = VTT
4. Save mapping
5. Check status indicator

**Expected:**
- Status: 🟢 Complete (has FuelType)
- Badge in Model dropdown: `"OUTLA (CANA) → CAN-A OUTLA (27 records)"`
- Badge in Make dropdown: `"CANA → CAN-A (42 records)"` (derived, aggregates all CANA models)

---

#### TC2.3: Verify Make Consistency Validation
**Steps:**
1. Create mapping: CANA DEFEN → CAN-A DEFEN (save successfully)
2. Attempt to create: CANA MAVER → CANAM MAVER (different canonical Make)

**Expected:**
- Error message: Validation prevents conflicting Make mappings
- Cannot map CANA to both CAN-A and CANAM

---

#### TC2.4: Query CANA with Regularization ON (Coupled)
**Steps:**
1. Set regularization ON, coupling ON
2. Filter: Years = 2011-2024, Model = "OUTLA (CANA) → CAN-A OUTLA (27 records)"
3. Check record count

**Expected:**
- Query includes:
  - Make IDs: CAN-A and CANA (from mapping)
  - Model IDs: OUTLA (both variants if they have different IDs)
- Record count: 59 (CAN-A OUTLA from 2011-2022) + 27 (CANA OUTLA from 2023-2024) = 86 total

---

#### TC2.5: Query by Make Only (CANA)
**Steps:**
1. Set regularization ON, coupling ON
2. Filter: Years = 2011-2024, Make = "CANA → CAN-A (42 records)" (NO Model selected)
3. Check result count

**Expected:**
- Query expands to both Make IDs: CAN-A and CANA
- Returns ALL models from both Makes
- Record count: 42 (CANA all models) + 64 (CAN-A all models) = 106 total

---

### 🧪 Test Group 3: Mazda CX-3 Truncation

#### TC3.1: Identify CX3 vs CX-3
**Steps:**
1. Check if CX-3 exists in 2011-2022 data
2. Run query:
   ```sql
   SELECT m.name, MIN(year), MAX(year), COUNT(*)
   FROM vehicles v JOIN model_enum m ON v.model_id = m.id
   WHERE m.name LIKE 'CX%3%' GROUP BY m.name;
   ```

**Expected:**
- CX-3 appears in curated years
- CX3 appears only in 2023-2024

---

#### TC3.2: Create MAZDA CX3 → MAZDA CX-3 Mapping
**Steps:**
1. Open RegularizationView
2. Select "MAZDA CX3" (7 records)
3. Map to canonical: MAZDA CX-3
4. Assign FuelType = Essence
5. Save

**Expected:**
- Model badge: `"CX3 (MAZDA) → MAZDA CX-3 (7 records)"`
- Make badge unchanged: `"MAZDA"` (no badge, same canonical Make)

---

#### TC3.3: Query CX3 with Regularization ON
**Steps:**
1. Set regularization ON, coupling ON
2. Filter: Years = 2011-2024, Model = "CX3 (MAZDA) → MAZDA CX-3 (7 records)"
3. Check record count

**Expected:**
- Query includes both model IDs (CX3 and CX-3)
- Make constraint: MAZDA only (coupling mode)
- Record count: Historical CX-3 records + 7 CX3 records

---

### 🧪 Test Group 4: Coupling Toggle Behavior

#### TC4.1: Model Filter with Coupling ON
**Steps:**
1. Create mapping: GMC SIE → GMC SIERRA
2. Set regularization ON, coupling ON
3. Filter: Model = "SIE (GMC) → GMC SIERRA (11 records)" (NO Make selected)
4. Check query construction

**Expected:**
- Query includes Model IDs: SIE and SIERRA
- Query includes Make ID: GMC (from mapping, coupling enabled)
- Returns only GMC vehicles

---

#### TC4.2: Model Filter with Coupling OFF
**Steps:**
1. Keep mapping: GMC SIE → GMC SIERRA
2. Set regularization ON, coupling OFF
3. Filter: Model = "SIE (GMC) → GMC SIERRA (11 records)" (NO Make selected)
4. Check query construction

**Expected:**
- Query includes Model IDs: SIE and SIERRA
- Query does NOT include Make constraint (coupling disabled)
- Returns SIE/SIERRA from ANY Make (if other Makes used same model name)

---

### 🧪 Test Group 5: Show Exact Matches Toggle

#### TC5.1: Default View (Exact Matches Hidden)
**Steps:**
1. Open RegularizationView
2. Ensure "Show Exact Matches" is OFF
3. Check uncurated pairs list

**Expected:**
- Shows only typos/variants (pairs NOT in 2011-2022)
- Examples: CANA OUTLA, HONDA CRV, GMC SIE
- Does NOT show: HONDA CIVIC, TOYOTA COROLLA (exact matches)

---

#### TC5.2: Show All Pairs (Exact Matches Visible)
**Steps:**
1. Toggle "Show Exact Matches" ON
2. Check uncurated pairs list

**Expected:**
- Shows ALL pairs from 2023-2024, including exact matches
- Use case: Add FuelType/VehicleType to HONDA CIVIC for disambiguation

---

### 🧪 Test Group 6: Badge Hiding

#### TC6.1: Uncurated Make == Canonical Make
**Steps:**
1. Create mapping: HONDA CIVIC → HONDA CIVIC (exact match)
2. Assign FuelType = Essence
3. Close RegularizationView
4. Check Make dropdown

**Expected:**
- Make badge: `"HONDA"` (no badge, uncurated == canonical)
- Model badge: `"CIVIC (HONDA)"` (no arrow, but may show record count)

**Note:** Badge hiding logic should detect when uncurated name equals canonical name

---

### 🧪 Test Group 7: Cache Invalidation

#### TC7.1: Badge Updates After Mapping
**Steps:**
1. Note initial badges in dropdowns
2. Open RegularizationView
3. Create new mapping (e.g., CFMOT CFORC → CF MOTO C-FORCE)
4. Close RegularizationView
5. Check dropdowns immediately

**Expected:**
- Cache invalidates automatically on RegularizationView close
- New badge appears: `"CFORC (CFMOT) → CF MOTO C-FORCE (11 records)"`
- No need to restart app

---

#### TC7.2: Badge Stripping Works
**Steps:**
1. Select a regularized model from dropdown: `"CRV (HONDA) → HONDA CR-V (14 records)"`
2. Apply filter
3. Check console output

**Expected:**
- Console shows: `🔍 Model 'CRV (HONDA) → HONDA CR-V (14 records)' (cleaned: 'CRV') -> ID 1494`
- Query succeeds (badge stripped before ID lookup)

---

### 🧪 Test Group 8: Edge Cases

#### TC8.1: Empty Results (No Records)
**Steps:**
1. Filter: Years = 2011-2022, Model = "CRV (HONDA) → HONDA CR-V (14 records)"
2. Check result

**Expected:**
- 0 records from CRV (doesn't exist in 2011-2022)
- 197 records from CR-V (canonical exists)
- Total: 197 records

---

#### TC8.2: Bidirectional Expansion (Canonical to Uncurated)
**Steps:**
1. Create mapping: HONDA CRV → HONDA CR-V
2. Filter: Years = 2023-2024, Model = "CR-V (HONDA)" (canonical name)
3. Check record count

**Expected:**
- Bidirectional expansion: CR-V (218) ↔ CRV (1494)
- Query includes both IDs
- Result: 14 CRV records + any CR-V from 2023-2024 (if present)

---

#### TC8.3: Multiple Mappings for Same Canonical
**Steps:**
1. Create: CANA OUTLA → CAN-A OUTLA
2. Create: CANAM OUTLM → CAN-A OUTLA (same canonical)
3. Filter: Model = "OUTLA (CAN-A)"

**Expected:**
- Query expands to: OUTLA (CAN-A), OUTLA (CANA), OUTLM (CANAM)
- Returns all three variants

---

### 🧪 Test Group 9: Performance & Console Logging

#### TC9.1: Verify Console Messages
**Steps:**
1. Launch app
2. Check console for initialization messages

**Expected:**
```
✅ Loaded regularization info for X Make/Model pairs
✅ Loaded derived Make regularization info for X Makes
✅ Loaded XXX uncurated Make/Model pairs
✅ Loaded X uncurated Makes (only in uncurated years)
✅ Regularization ENABLED in queries (coupled mode)
✅ Filter cache invalidated on launch - will reload with latest regularization data
```

---

#### TC9.2: Query Performance
**Steps:**
1. Enable regularization
2. Run query with 3-4 filters (Year + Make + Model + FuelType)
3. Measure query time

**Expected:**
- Query completes in <1 second (abbreviated dataset)
- Console shows expansion steps
- Results accurate

---

### 🧪 Test Group 10: Settings Persistence

#### TC10.1: Settings Survive App Restart
**Steps:**
1. Set regularization ON, coupling OFF
2. Quit app
3. Relaunch app
4. Check settings

**Expected:**
- Both settings restored: Regularization ON, Coupling OFF
- Console confirms: `✅ Regularization ENABLED in queries (decoupled mode)`

---

#### TC10.2: Mappings Survive App Restart
**Steps:**
1. Create 3-4 mappings
2. Quit app
3. Relaunch app
4. Open RegularizationView

**Expected:**
- All mappings persisted in database
- Badges appear correctly in dropdowns
- Status indicators accurate (🔴🟠🟢)

---

## Testing Checklist

### Pre-Testing Setup
- [ ] Verify database has 14,000 records (1,000 per year × 14 years)
- [ ] Delete existing mappings to start fresh (optional)
- [ ] Verify CLAUDE.md curation years setting: 2011-2022

### Core Features
- [ ] TC1.1: Badge display (uncurated and regularized)
- [ ] TC1.2: Query with regularization OFF
- [ ] TC1.3: Query with regularization ON (coupled)
- [ ] TC1.4: Query with regularization ON (decoupled)
- [ ] TC1.5: Derived Make badges
- [ ] TC1.6: Make-level query expansion

### Complex Scenarios
- [ ] TC2.1-2.5: Can-Am Make variants (4 different spellings)
- [ ] TC2.3: Make consistency validation
- [ ] TC3.1-3.3: Mazda CX-3 truncation
- [ ] TC4.1-4.2: Coupling toggle behavior

### UI/UX Features
- [ ] TC5.1-5.2: Show exact matches toggle
- [ ] TC6.1: Badge hiding for exact matches
- [ ] TC7.1-7.2: Cache invalidation and badge stripping

### Edge Cases
- [ ] TC8.1: Empty results handling
- [ ] TC8.2: Bidirectional expansion
- [ ] TC8.3: Multiple mappings to same canonical

### System Quality
- [ ] TC9.1: Console logging accuracy
- [ ] TC9.2: Query performance
- [ ] TC10.1-10.2: Settings and mapping persistence

---

## Known Issues to Watch For

1. **Badge format:** Ensure full canonical pair shown: `"CRV (HONDA) → HONDA CR-V (14 records)"`
2. **Make expansion bug:** Verify bidirectional (was one-way in early version)
3. **Model-only filter bug:** Ensure no unwanted Make IDs added when no Make selected
4. **Redundant badges:** Verify hidden when uncurated == canonical

---

## Test Data Queries (For Manual Verification)

```sql
-- Count records for specific Make/Model
SELECT COUNT(*) FROM vehicles v
JOIN make_enum m1 ON v.make_id = m1.id
JOIN model_enum m2 ON v.model_id = m2.id
WHERE m1.name = 'HONDA' AND m2.name = 'CRV';

-- Check if model exists in curated years
SELECT MIN(year), MAX(year), COUNT(*) FROM vehicles v
JOIN model_enum m ON v.model_id = m.id
WHERE m.name = 'CRV';

-- Verify mapping in database
SELECT
  m1.name as uncurated_make, m2.name as uncurated_model,
  m3.name as canonical_make, m4.name as canonical_model,
  r.record_count, r.fuel_type_id, r.vehicle_type_id
FROM make_model_regularization r
JOIN make_enum m1 ON r.uncurated_make_id = m1.id
JOIN model_enum m2 ON r.uncurated_model_id = m2.id
JOIN make_enum m3 ON r.canonical_make_id = m3.id
JOIN model_enum m4 ON r.canonical_model_id = m4.id;

-- Check enum IDs for debugging
SELECT id, name FROM make_enum WHERE name IN ('HONDA', 'JHOND', 'JOHND', 'CANA', 'CAN-A');
SELECT id, name FROM model_enum WHERE name IN ('CRV', 'CR-V', 'OUTLA', 'CX3', 'CX-3');
```

---

## Success Criteria

✅ All 30+ test cases pass
✅ No crashes or errors during testing
✅ Console messages accurate and helpful
✅ Query results match expected counts
✅ Badges display correctly with proper formatting
✅ Settings persist across app restarts
✅ Cache invalidation works automatically
✅ Performance acceptable (<1 second per query on abbreviated dataset)

---

## Notes for Full Dataset Testing

Once abbreviated dataset testing is complete, repeat key tests with full dataset:
- Verify performance with millions of records
- Check query execution time with regularization enabled
- Verify badge system scales to hundreds of uncurated pairs
- Test cache loading time on app launch
