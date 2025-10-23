# Priority-Filtered Make/Model Standardization - Session Summary

**Date:** 2025-10-05
**Session Duration:** ~4 hours
**Status:** Phase 1 Complete - AI Prompt Refinement Needed

---

## 1. Current Task & Objective

### Overall Goal
Standardize 2023-2024 SAAQ vehicle Make/Model pairs to match canonical 2011-2022 format, while preventing false positive mappings that would corrupt the research database.

### Primary Problem Being Solved
SAAQ changed data entry conventions between 2011-2022 (cleaned, QA'd) and 2023-2024 (raw, uncleaned):
- **Typos and spelling variations**: HONDA vs HOND, SUZUKI vs SUSUK
- **Truncation differences**: CX-3 (2011-2022) vs CX3 (2023-2024)
- **Missing critical fields**: vehicle_type, mass, fuel_type all NULL in 2023-2024
- **Business priority**: Cars/light trucks (PAU/CAU) are most important for short-term analysis

### Critical Constraint: Make Ambiguity
**Discovery**: Many makes produce multiple vehicle types:
- **HONDA**: 11 different classifications (PAU cars, PMC motorcycles, HVT ATVs, etc.)
- **FORD**: 11 different classifications (PAU cars, BCA trucks, etc.)
- **YAMAHA**: 6 classifications (motorcycles, ATVs, snowmobiles - NO PAU/CAU!)

**Implication**: Make-only standardization is impossible. Must use Make/Model pairs with vehicle type filtering to prevent cross-contamination (e.g., HONDA CIVIC car vs HONDA CBR motorcycle).

### Success Criteria
1. ✅ Prevent false positives (BMW X4 ≠ X3, KIA CARNI preserved as new model)
2. ✅ Correctly standardize typos/truncations (VOLV0 → VOLVO, CX3 → CX-3)
3. ✅ Prioritize PAU/CAU (business need for cars/light trucks)
4. ✅ Use vehicle type filtering to prevent cross-type contamination
5. ⚠️ **PENDING**: Improve AI prompt consistency (current issue)

---

## 2. Progress Completed

### ✅ Architecture Evolution

**Phase 0: Original Levenshtein-only approach** (before this session)
- Simple string similarity matching
- No AI, no CVS validation
- Could not distinguish typos from new models

**Phase 1: Two-pass architecture** (attempted, then abandoned)
- Pass 1: Standardize makes
- Pass 2: Standardize models within corrected makes
- **Abandoned reason**: Make ambiguity makes this impossible (HONDA = cars + motorcycles)

**Phase 2: Single-pass priority-filtered** (current implementation)
- ✅ Four priority levels based on canonical presence + CVS membership
- ✅ Vehicle type filtering (PAU/CAU separated from specialty)
- ✅ Make/Model pair matching (not Make-only)
- ✅ CVS + Temporal + AI validation pipeline

### ✅ Key Technical Achievements

**1. CVS Database Integration**
- Location: `~/Desktop/cvs_complete.sqlite`
- 725 unique Make/Model pairs from Transport Canada
- Coverage: PAU (63.5%), CAU (82.1%), specialty vehicles (0%)
- Table: `cvs_data` (NOT vehicles) with vehicle_type field

**2. Canonical Data Analysis**
- 1,477 canonical Make/Model pairs (2011-2022)
  - 533 PAU/CAU pairs (cars/light trucks)
  - 944 specialty pairs (motorcycles, ATVs, snowmobiles, tractors, etc.)
- Each pair has explicit vehicle_type from classification_enum table
- Key insight: 30 makes produce multiple vehicle types (discovered via SQL query)

**3. Priority Classification System**
```
Priority 1 (Canonical PAU/CAU):
  - 2023-2024 pair exists in 2011-2022 as PAU/CAU
  - Match against canonical PAU/CAU pairs only
  - Result: 0 pairs (all canonical pairs already spelled correctly!)

Priority 2 (CVS New PAU/CAU):
  - Not in canonical, but in CVS database
  - Likely new 2023+ passenger vehicle models
  - Match against canonical PAU/CAU pairs only
  - Result: 12 pairs (KIA CARNI, BMW X4, LEXUS UX, etc.)

Priority 3 (Canonical Specialty):
  - Exists in 2011-2022 as motorcycle/ATV/etc.
  - Match against canonical specialty pairs only
  - Result: 0 pairs (all canonical specialty already spelled correctly!)

Priority 4 (Unknown):
  - Not in canonical, not in CVS
  - Could be: new specialty vehicle, typo, data error
  - Match against ALL canonical pairs (conservative)
  - Result: 541 pairs
```

**4. Validation Pipeline (Three Layers)**
```
INPUT: 2023-2024 Make/Model Pair
    ↓
1. CVS Validation (Transport Canada Authority)
   - Query with hyphenation variants (CX3 → try CX3, then CX-3)
   - CASE 1: Both found in CVS as same vehicle_type → SUPPORT (0.9)
   - CASE 2: Both found but different vehicle_type → PREVENT (0.9)
   - CASE 3: Only canonical found → SUPPORT (0.8)
   - CASE 4: Neither found → NEUTRAL (0.5)
    ↓
2. Temporal Validation (Model Year Compatibility)
   - Year ranges overlap → SUPPORT (0.9)
   - No overlap → PREVENT (0.8)
   - Non-std appears after canonical ended → PREVENT (0.7)
    ↓
3. AI Analysis (Foundation Models API)
   - Fresh session per task (thread-safe)
   - Classification: spellingVariant, newModel, truncationVariant, uncertain
   - Confidence: 0.0-1.0
    ↓
4. Override Logic
   - IF CVS confidence ≥ 0.9 AND says PREVENT → Override AI to PRESERVE
   - IF Temporal confidence ≥ 0.8 AND says PREVENT → Override AI to PRESERVE
   - ELSE → Use AI decision
    ↓
OUTPUT: Standardization Decision + Reasoning
```

**5. Thread-Safe Concurrency**
- Each TaskGroup task opens its own database connection (prevents segfaults)
- Fresh LanguageModelSession created per AI call (prevents hanging)
- Pattern: Pass database paths (not instances) to parallel tasks

### ✅ Test Results

**v1 Report** (before AI parsing fix):
- 0 standardizations, 553 preservations
- Too conservative (AI parsing bug)

**v2 Report** (after AI parsing fix):
- 207 standardizations, 346 preservations
- ⚠️ Too aggressive (AI prompt inconsistency issue)

**CVS Protection Verified** ✅
- KIA CARNI preserved (CVS: MINIVAN, candidate was SEDAN)
- BMW X4 preserved (CVS: new model, not matched to X1)
- VOLVO V60 preserved (CVS: WAGON, candidate was S60 SEDAN)
- JEEP GLADIATOR preserved (CVS: PICKUP, candidate was GRAND SUV)

---

## 3. Key Decisions & Patterns

### Architecture: Single-Pass Priority-Filtered

**Why single-pass instead of two-pass?**
- Make-only filtering is impossible due to ambiguity (HONDA = cars + motorcycles)
- Make/Model pair provides disambiguation (HONDA CIVIC = PAU, HONDA CBR = PMC)
- Vehicle type filtering requires the full pair to query canonical data

**Why priority-based processing?**
- Business need: PAU/CAU (cars/light trucks) are highest priority
- CVS membership indicates new PAU/CAU models (need special handling)
- Specialty vehicles (motorcycles, etc.) have different validation needs

### Swift Concurrency Patterns

**1. Foundation Models API Execution (Critical)**
```swift
// ✅ CORRECT (working)
@MainActor
func main() async throws {
    // Main logic here
}
try await main()

// ❌ WRONG (causes hangs/segfaults)
Task { @MainActor in ... } + RunLoop.main.run()
```

**2. Thread-Safe Database Access**
```swift
// ✅ CORRECT - Pass paths, open per-task
func validateWithCVS(nonStdPair: MakePair, canonicalPair: MakePair, cvsDBPath: String) -> Result {
    guard let cvsDB = try? DatabaseHelper(path: cvsDBPath) else { return ... }
    // Use cvsDB
}

// ❌ WRONG - Shared database instance across tasks
func validateWithCVS(nonStdPair: MakePair, canonicalPair: MakePair, cvsDB: DatabaseHelper) -> Result {
    // SQLite not thread-safe!
}
```

**3. Fresh AI Session Per Task**
```swift
// ✅ CORRECT - Create fresh session inside each task
group.addTask {
    let freshSession = LanguageModelSession(instructions: "...")
    let response = try await freshSession.respond(to: prompt)
}

// ❌ WRONG - Shared session across tasks
let session = LanguageModelSession(...)
group.addTask {
    let response = try await session.respond(to: prompt)  // Not thread-safe!
}
```

### Database Schema Differences (Critical)

**SAAQ Database (Enumeration Schema)**:
```sql
-- Enumeration tables with foreign keys
SELECT make_enum.name, model_enum.name, classification_enum.code
FROM vehicles
JOIN make_enum ON vehicles.make_id = make_enum.id
JOIN model_enum ON vehicles.model_id = model_enum.id
JOIN classification_enum ON vehicles.classification_id = classification_enum.id
WHERE year BETWEEN 2011 AND 2022;
```

**CVS Database (String-Based Schema)**:
```sql
-- Direct string columns
SELECT saaq_make, saaq_model, vehicle_type, myr
FROM cvs_data  -- NOT vehicles!
WHERE saaq_make = ? AND saaq_model = ?;
```

### Hyphenation-Aware Matching

**SAAQ Format Change:**
- 2011-2022: Uses hyphens (CX-3, HR-V, CR-V)
- 2023-2024: No hyphens (CX3, HRV, CRV)

**Solution:**
```swift
// CVS query tries both variants
let variants = [model, generateHyphenatedVariant(model)]
for variant in variants {
    // Query CVS with variant
}

// String matching gets 0.99 boost if hyphenation variant
if model1.replacingOccurrences(of: "-", with: "") == model2.replacingOccurrences(of: "-", with: "")
   && model1 != model2 {
    similarity = 0.99  // CX3 vs CX-3
}
```

---

## 4. Active Files & Locations

### Production Scripts
```
/Users/rhoge/Desktop/SAAQAnalyzer/Scripts/
├── PriorityFilteredStandardization.swift  ← CURRENT PRODUCTION (v2)
├── PriorityFilteredStandardization        ← Compiled binary
├── AIStandardizeMakeModel-Enhanced.swift  ← Phase 1 (CVS-enhanced, pre-priority)
├── AIStandardizeMake.swift                ← Failed two-pass attempt (Pass 1)
└── StandardizeMakeModel.swift             ← Original Levenshtein-only baseline
```

### Databases
```
~/Desktop/cvs_complete.sqlite
  - Transport Canada CVS database
  - Table: cvs_data (NOT vehicles)
  - 725 unique pairs, 8,176 records
  - Coverage: PAU 63.5%, CAU 82.1%, specialty 0%

~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite
  - Test database (1,000 records/year, 14,000 total)
  - Enumeration schema (make_enum, model_enum, classification_enum)
  - 1,477 canonical pairs (2011-2022)
  - 553 non-standard pairs (2023-2024)
```

### Reports
```
~/Desktop/Priority-Filtered-Report-v1.md
  - First run: 0 standardizations (AI parsing bug)

~/Desktop/Priority-Filtered-Report-v2.md
  - Second run: 207 standardizations (AI inconsistency issue)
  - ⚠️ Contains bad recommendations (needs manual review)

~/Desktop/Make-Standardization-Report-v3.md
  - Make-only attempt (abandoned due to ambiguity)
```

### Documentation
```
/Users/rhoge/Desktop/SAAQAnalyzer/Documentation/
├── CVS-Validation-Analysis.md              ← Up to date (Oct 4)
│   - Coverage analysis (PAU/CAU)
│   - Hyphenation solution
│   - 850+ lines comprehensive
├── AI-Make-Model-Standardization.md        ← OUTDATED (needs update)
│   - Describes AI-only approach
│   - No CVS validation
│   - No priority filtering
└── Make-Model-Standardization-Workflow.md  ← OUTDATED (needs update)
    - Original Levenshtein-only approach
    - Completely superseded
```

### Configuration
```
.gitignore
  - Added: Notes/* (track directory, ignore contents)
  - Added: !Notes/.gitkeep

Notes/.gitkeep
  - Empty placeholder file
```

---

## 5. Current State

### ✅ What's Working
1. ✅ Priority classification (4 levels based on canonical + CVS)
2. ✅ Vehicle type filtering (PAU/CAU vs specialty)
3. ✅ CVS validation (prevents cross-type contamination)
4. ✅ Temporal validation (year compatibility)
5. ✅ Thread-safe concurrency (no hangs/segfaults)
6. ✅ Hyphenation-aware matching (CX3 ↔ CX-3)
7. ✅ AI response parsing (now accepts multiple formats)

### ⚠️ Current Issue: AI Prompt Inconsistency

**The Problem:**
AI gives contradictory responses:
```
classification: genuinely different models
should standardize: yes          ← CONTRADICTORY!
confidence: 1.0
reason: these are clearly different models
```

**Bad Recommendations in v2 Report:**
- LEXUS UX → GX (different SUV sizes)
- MERCE C300 → B200 (C-Class ≠ B-Class)
- MOFFE M8 → MERCE ML (Moffett forklift ≠ Mercedes!)
- POLAR 8730 → 800 (different snowmobile model numbers)

**Root Cause:**
Current AI prompt is ambiguous. The AI interprets "should standardize" inconsistently:
- Sometimes: "yes" = they're the same vehicle (correct)
- Sometimes: "yes" = they're different and I should classify them (incorrect)

### 🔄 Partially Completed
- AI prompt refinement (minimal effort invested so far)
- Need to make prompt more explicit about when to say "yes" vs "no"

---

## 6. Next Steps (Priority Order)

### IMMEDIATE (Next Session)

**1. Refine AI Prompt for Consistency**

Current prompt (line 443-450 in PriorityFilteredStandardization.swift):
```swift
let prompt = """
Vehicle data quality task: Compare two vehicle make/model codes from government database.

Record A (2023-2024 data): \(nonStdPair.make) / \(nonStdPair.model)
Record B (2011-2022 data): \(canonicalPair.make) / \(canonicalPair.model)

Are these the same vehicle with spelling variation (spellingVariant), truncated text (truncationVariant), genuinely different models (newModel), or uncertain?

Respond with: classification | should_standardize (yes/no) | confidence (0-1) | brief_reason
"""
```

**Improvement needed:**
- Explicitly define what "should_standardize: yes" means
- Add examples of yes vs no cases
- Clarify that "genuinely different models" → should_standardize: no
- Consider structured output format (@Generable struct)

**2. Test Improved Prompt**
- Run on test dataset
- Verify contradictions eliminated
- Check bad recommendations (LEXUS UX→GX, MERCE C300→B200, etc.)

**3. Manual Review of v2 Recommendations**
- 207 standardizations need human review
- Focus on PAU/CAU pairs first (business priority)
- Create whitelist of approved standardizations

### MEDIUM PRIORITY

**4. Add Deterministic Rules for Obvious Cases**
- VOLV0 → VOLVO (typo: zero vs O) - no AI needed
- Exact hyphenation variants (CX3 ↔ CX-3) - no AI needed
- Reduces AI load, eliminates inconsistency for simple cases

**5. Implement Checkpointing for Production**
- Save progress every 100 pairs
- Allow resume after interruption
- Production will have millions of records (not 1,000/year test set)

**6. Generate SQL Scripts**
- Create UPDATE statements for approved standardizations
- Include rollback scripts
- Dry-run mode for validation

### LONG-TERM

**7. Phase 2: Parameter Inference**
- Use standardized Make/Model to infer missing fields:
  - vehicle_type (PAU/CAU/PMC/etc.)
  - mass (from canonical fingerprint)
  - fuel_type (from canonical fingerprint)
- Depends on successful Phase 1 standardization

**8. Build Regression Test Suite**
- Known good: VOLV0→VOLVO, CX3→CX-3
- Known bad: BMW X4→X3, KIA CARNI→CADEN
- Automated testing for future versions

**9. Full Dataset Testing**
- Current: 1,000 records/year (test)
- Production: Millions of records
- Runtime: Expect hours instead of minutes
- Monitor Foundation Models API rate limits

---

## 7. Important Context

### Errors Solved

**1. Foundation Models API Hanging** ✅
- **Error**: Scripts hung indefinitely
- **Cause**: `Task { @MainActor in ... } + RunLoop.main.run()` incompatible with Foundation Models
- **Solution**: Use `@MainActor func main() async throws` + `try await main()`

**2. Segmentation Faults in Concurrent Processing** ✅
- **Error**: Trace trap / segfault when processing 72 makes
- **Cause**: Shared database connections across TaskGroup tasks (SQLite not thread-safe)
- **Solution**: Pass database paths (strings), open connection per-task
- **Pattern**: Each task creates its own `DatabaseHelper` instance

**3. AI Response Parsing Failure (v1)** ✅
- **Error**: 0 standardizations despite AI saying "yes" with high confidence
- **Cause**: AI not following pipe-delimited format
- **Solution**: Added fallback parsing for colon/newline formats
- **Result**: v2 now parses responses (but AI is inconsistent)

**4. Make Standardization Impossible** ✅
- **Discovery**: 30 makes produce multiple vehicle types (HONDA, FORD, YAMAHA, etc.)
- **Impact**: Can't standardize makes first, then models
- **Solution**: Abandoned two-pass, implemented single-pass with Make/Model pairs

**5. Hyphenation Variant Matching** ✅
- **Error**: CX3 matched to CX30 (75%) instead of CX-3 (should be 99%)
- **Cause**: SAAQ format changed 2011-2022 (hyphenated) to 2023-2024 (no hyphens)
- **Solution**: Boost similarity to 0.99 if models identical after hyphen removal

### Dependencies & Requirements

**Swift 6.2:**
- macOS Tahoe 26.0+
- Apple Silicon required (M3 Ultra in development)
- Foundation Models framework: `import FoundationModels`
- Top-level async/await support

**SQLite3:**
- Native macOS library
- Two databases with different schemas (SAAQ and CVS)

**Foundation Models API:**
- `LanguageModelSession(instructions:)` pattern
- Response access: `.content` property
- Throughput: ~0.7-0.8 pairs/sec
- Parallelism: Works with TaskGroup concurrent execution
- **Critical**: Must create fresh session per task (not shared)

### Compilation & Execution

**Always compile Swift scripts:**
```bash
swiftc PriorityFilteredStandardization.swift -o PriorityFilteredStandardization -O
```

**Never use shebang execution** - Foundation Models API doesn't work in interpreted mode

**Run with full paths:**
```bash
./PriorityFilteredStandardization \
  ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  ~/Desktop/cvs_complete.sqlite \
  ~/Desktop/Priority-Filtered-Report-v3.md
```

### Critical Gotchas

**1. Database Table Name Differences**
- SAAQ: Uses `vehicles` table with enumeration joins
- CVS: Uses `cvs_data` table (NOT vehicles!)

**2. Test Dataset Limitation**
- All analysis based on 1,000 records/year (14,000 total)
- Production will have dramatically different scale (millions of records)
- Unique pair counts will increase 10-50x

**3. CVS Coverage Gaps**
- PAU (passenger): 63.5% coverage
- CAU (commercial): 82.1% coverage
- Specialty vehicles (snowmobiles, ATVs, motorcycles, tractors): **0% coverage**
- Discontinued pre-2010 models: Often missing

**4. AI Prompt Sensitivity**
- Current prompt produces inconsistent/contradictory responses
- Needs explicit definition of "should_standardize: yes" vs "no"
- Consider using @Generable struct for structured output

**5. Vehicle Type Classification Codes**
```
PAU = Personal automobile/light truck
CAU = Commercial automobile/light truck
PMC = Personal motorcycle
HMN = Off-road snowmobile
HVT = Off-road all-terrain vehicle (ATV)
HVO = Off-road tool vehicle (tractor)
BCA = Truck/road tractor
CVO = Tool vehicle
... (21 total classifications)
```

### Session Statistics

**Development Time:** ~4 hours
**Code Written:** ~2,500 lines (scripts + analysis)
**Test Iterations:** 2 major versions (v1, v2)
**Key Bugs Fixed:** 5 critical issues
**Architecture Pivots:** 2 (two-pass → single-pass → priority-filtered)

---

## Quick Start for Next Session

**To continue where we left off:**

1. **Review this document** - Complete context preserved

2. **Check latest test results:**
   ```bash
   cat ~/Desktop/Priority-Filtered-Report-v2.md
   ```

3. **Key decision:** Improve AI prompt consistency
   - Current prompt at line 443-450 in PriorityFilteredStandardization.swift
   - Need to eliminate contradictory responses ("genuinely different" + "should standardize: yes")

4. **Manually review bad recommendations:**
   - LEXUS UX → GX
   - MERCE C300 → B200
   - MOFFE M8 → MERCE ML
   - POLAR 8730 → 800

5. **Test improved prompt:**
   ```bash
   swiftc PriorityFilteredStandardization.swift -o PriorityFilteredStandardization -O
   ./PriorityFilteredStandardization \
     ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
     ~/Desktop/cvs_complete.sqlite \
     ~/Desktop/Priority-Filtered-Report-v3.md
   ```

---

**Session Complete. Priority-filtered architecture working. AI prompt refinement needed for production readiness.**
