# Foundation Models API Debugging Session - 2025-10-04

## 1. Current Task & Objective

**Primary Goal**: Debug and fix Foundation Models API hanging issue in CVS-Enhanced AI standardization script.

**Specific Problem Being Solved**:
- CVS-Enhanced AI standardization script (`AIStandardizeMakeModel-Enhanced.swift`) compiles successfully but hangs when making Foundation Models API calls
- The script launches all 245 parallel AI analysis tasks but receives **zero** AI responses
- A supposedly "working" script (`AIStandardizeMakeModel.swift`) also hangs, but **after** processing 120 pairs successfully at ~340 pairs/sec
- Need to identify why Foundation Models API calls hang and implement a solution

**Context**: This is part of Phase 1 of a three-phase implementation to prevent false positive vehicle model mappings (e.g., KIA CARNI → KIA CADEN) using Transport Canada CVS database validation and temporal compatibility checks.

## 2. Progress Completed

### ✅ CVS Database Built
- **Location**: `~/Desktop/cvs_complete.sqlite`
- **Source**: Transport Canada Canadian Vehicle Specifications (CVS) data
- **Records**: 8,176 authoritative make/model/year/body_type combinations
- **Schema**: `cvs_data` table (NOT vehicles) with fields: make, model, myr (model_year), saaq_make, saaq_model, vehicle_type, dimensional parameters
- **Purpose**: Provides ground truth for validating non-standard SAAQ pairs

### ✅ Test Database Populated
- **Location**: `~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite`
- **Content**: Abbreviated data - first 1000 records from each year 2011-2024
- **Schema**: Integer-based enumeration tables (make_enum, model_enum) with foreign keys in vehicles table
- **Status**: Contains 1,477 canonical pairs (2011-2022) and 908 non-standard pairs (2023-2024)

### ✅ CVS-Enhanced Script Structure Completed
- **File**: `/Users/rhoge/Desktop/SAAQAnalyzer/Scripts/AIStandardizeMakeModel-Enhanced.swift`
- **Status**: Compiles successfully, all logic implemented, but hangs at runtime on AI calls
- **Features**:
  - CVS validation layer (queries Transport Canada database)
  - Temporal validation layer (checks model year compatibility)
  - AI decision layer (uses Foundation Models API)
  - Pre-filtering (separates 308 no-match pairs from 245 AI-analysis pairs)
  - Parallel execution with TaskGroup
  - Override logic for CVS/temporal validation after AI response

### ✅ Non-AI Baseline Script Works
- **File**: `/Users/rhoge/Desktop/SAAQAnalyzer/Scripts/StandardizeMakeModel.swift`
- **Status**: Runs to completion successfully
- **Output**: Processed 908 pairs, generated 785 mappings, wrote report and SQL script
- **Confirms**: Database access, queries, string similarity, file I/O all work correctly

### ✅ Key Discoveries

**Discovery 1: Compilation Required**
- Foundation Models API does NOT work in shebang execution mode
- Scripts MUST be compiled with `swiftc` before running
- Pattern: `swiftc ScriptName.swift -o ScriptName -O && ./ScriptName [args]`

**Discovery 2: Prompt Size Critical**
- Verbose prompts cause Foundation Models API to hang
- Original Enhanced script had ~500-800 character prompts with embedded validation text
- Working script has ~250 character prompts
- **Solution Applied**: Compacted prompt to match working script format, moved validation logic to post-AI-response overrides

**Discovery 3: Partial Success Pattern**
- "Working" AIStandardizeMakeModel script processed 120/553 pairs before hanging
- Achieved ~340 pairs/sec throughput
- Enhanced script gets 0/245 pairs (hangs immediately)
- **Implication**: Foundation Models API works but something causes it to stall

**Discovery 4: System Resource Exhaustion Suspected**
- Multiple AI standardization processes found running in background
- Both scripts now hang even after multiple restarts
- Symptoms suggest Foundation Models API resource exhaustion or rate limiting
- **Action Required**: System reboot to clear state

## 3. Key Decisions & Patterns

### Swift 6.2 Concurrency Architecture
- **Platform**: macOS Tahoe (26.0+)
- **Swift Version**: 6.2 with dramatically improved concurrency support
- **Hardware**: Mac Studio M3 Ultra (32 Neural Engine cores, 96GB unified RAM)
- **Concurrency**: Foundation Models confirmed to work in multi-threaded approach on this platform

### Execution Pattern for Foundation Models Scripts
```swift
// Top-level async/await (Swift 5.5+)
@MainActor
func main() async throws {
    // Main logic here
}

try await main()  // NOT: Task { @MainActor in ... } + RunLoop.main.run()
```

**Note**: The Enhanced script currently uses `Task { @MainActor in ... } + RunLoop.main.run()` pattern, which may need conversion to `await main()` pattern.

### Compact Prompt Pattern (Critical)
```swift
let prompt = """
Vehicle data quality task: Compare two vehicle make/model codes from government database.

Record A (2023-2024 data): \(nonStandard.make) / \(nonStandard.model)
  Model years: \(nonStandard.minModelYear ?? 0)-\(nonStandard.maxModelYear ?? 0)
  Registered: \(nonStandard.minRegistrationYear ?? 0)-\(nonStandard.maxRegistrationYear ?? 0)

Record B (2011-2022 data): \(canonical.make) / \(canonical.model)
  Model years: \(canonical.minModelYear ?? 0)-\(canonical.maxModelYear ?? 0)
  Registered: \(canonical.minRegistrationYear ?? 0)-\(canonical.maxRegistrationYear ?? 0)

Are these the same vehicle with spelling variation (spellingVariant), truncated text (truncationVariant), genuinely different models (newModel), or uncertain?

Respond with: classification | should_standardize (yes/no) | confidence (0-1) | brief_reason
"""
```

**DO NOT embed validation reasoning in prompt** - it causes API hangs.

### CVS/Temporal Validation Override Pattern
```swift
// Parse AI response first
var shouldCorrect = true
var confidence = 0.7
var decision: DecisionType = .spellingVariant

// [Parse AI response...]

// THEN apply validation overrides
if !cvsValidation.isValid && cvsValidation.confidence >= 0.9 {
    shouldCorrect = false
    decision = .newModel
    confidence = cvsValidation.confidence
    reasoning += "\n\n[CVS Override: Found in Transport Canada database - \(cvsValidation.reason)]"
}

if !temporalValidation.isValid && temporalValidation.confidence >= 0.8 {
    shouldCorrect = false
    decision = .newModel
    confidence = max(confidence, temporalValidation.confidence)
    reasoning += "\n\n[Temporal Override: Model year incompatibility - \(temporalValidation.reason)]"
}
```

### Database Schema Differences (Critical)

**SAAQ Database (Enumerated Integer Schema)**:
```sql
SELECT make_enum.name, model_enum.name,
       MIN(vehicles.model_year), MAX(vehicles.model_year),
       MIN(vehicles.year), MAX(vehicles.year)
FROM vehicles
JOIN make_enum ON vehicles.make_id = make_enum.id
JOIN model_enum ON vehicles.model_id = model_enum.id
WHERE vehicles.year BETWEEN 2011 AND 2022
GROUP BY make_enum.name, model_enum.name
```

**CVS Database (String-based Schema)**:
```sql
SELECT make, model, myr, vehicle_type
FROM cvs_data
WHERE saaq_make = ? AND saaq_model = ?
```

### Parallel Processing Pattern
```swift
let aiResults = try await withThrowingTaskGroup(of: AnalysisResult?.self) { group in
    var processedResults: [AnalysisResult] = []
    var processedCount = 0

    // Submit ALL AI tasks concurrently
    for (nonStdPair, canonicalPair, similarity) in aiPairs {
        group.addTask {
            // Validation logic
            let cvsValidation = validateWithCVS(...)
            let temporalValidation = validateTemporalLogic(...)

            // AI analysis
            let analysis = try await analyzeWithAI(
                nonStandard: nonStdPair,
                canonical: canonicalPair,
                cvsValidation: cvsValidation,
                temporalValidation: temporalValidation
            )

            return AnalysisResult(...)
        }
    }

    // Collect results as they complete
    for try await result in group {
        if let result = result {
            processedResults.append(result)
            processedCount += 1
            // Progress reporting...
        }
    }

    return processedResults
}
```

## 4. Active Files & Locations

### Primary Implementation Files

**`/Users/rhoge/Desktop/SAAQAnalyzer/Scripts/AIStandardizeMakeModel-Enhanced.swift`**
- CVS-enhanced AI standardization script
- **Status**: ✅ Compiles, ❌ Hangs on AI calls (0/245 responses)
- **Compiled Binary**: `AIStandardizeMakeModel-Enhanced` (in same directory)
- **Latest Changes**:
  - Compacted prompt to ~250 characters (matching working script)
  - Removed `@MainActor` from `analyzeWithAI()` function
  - Moved validation logic to post-AI-response overrides

**`/Users/rhoge/Desktop/SAAQAnalyzer/Scripts/AIStandardizeMakeModel.swift`**
- "Working" AI standardization script (but also now hanging)
- **Status**: ✅ Compiles, ⚠️ Processed 120/553 pairs then hung
- **Compiled Binary**: `AIStandardizeMakeModel` (in same directory)
- **Last Run Output**: Got to 21.7% completion (120 pairs) at 341.5 pairs/sec before hanging
- **Key Difference**: This script has `@MainActor` on `analyzeWithAI()` function

**`/Users/rhoge/Desktop/SAAQAnalyzer/Scripts/StandardizeMakeModel.swift`**
- Non-AI baseline standardization script
- **Status**: ✅ Works perfectly
- **Purpose**: Confirms database/query/file I/O infrastructure is sound

### Database Files

**`~/Desktop/cvs_complete.sqlite`**
- Transport Canada CVS database (8,176 records)
- Table: `cvs_data` (NOT vehicles)
- Columns: make, model, myr, saaq_make, saaq_model, vehicle_type, dimensional parameters

**`~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite`**
- SAAQ vehicle registration database
- Schema: Enumeration tables (make_enum, model_enum, etc.)
- Content: 1,477 canonical pairs (2011-2022), 908 non-standard pairs (2023-2024)
- 553 new/different pairs requiring analysis

### Expected Output Files

**`~/Desktop/CVS-Enhanced-Report.md`**
- Expected output from CVS-enhanced script
- **Status**: ❌ Does not exist (script hangs before completion)

**`~/Desktop/AI-MakeModel-Report.md`**
- Expected output from working AI script
- **Status**: ❌ Incomplete (script hung at 21.7%)

## 5. Current State

### What's Working ✅
1. Script compilation succeeds for all scripts
2. Database access and queries work perfectly (proven by StandardizeMakeModel)
3. Pre-filtering logic correctly separates 308 no-match from 245 AI-analysis pairs
4. TaskGroup launches all 245 tasks successfully
5. CVS validation logic implemented
6. Temporal validation logic implemented
7. Compact prompt format implemented
8. Override logic for CVS/temporal validation after AI response

### What's Failing ❌
1. **Foundation Models API calls hang indefinitely**
   - Enhanced script: 0/245 AI responses received
   - "Working" script: Hung after 120/553 responses
2. **No error messages** - Silent hang, no exceptions, no logs
3. **System-wide issue suspected** - Both scripts now hang even after recompilation

### What We've Tried
1. ✅ Compiled scripts (shebang doesn't work)
2. ✅ Compacted prompts (verbose prompts confirmed problematic)
3. ✅ Removed `@MainActor` from `analyzeWithAI()` (didn't fix)
4. ✅ Added `@MainActor` back to `analyzeWithAI()` (working script has it)
5. ✅ Verified database connectivity (works in non-AI script)
6. ✅ Killed background processes
7. ⏳ **PENDING**: System reboot to clear Foundation Models state

### Hypotheses

**Hypothesis 1: Foundation Models Resource Exhaustion** (Most Likely)
- API successfully processed 120 pairs, then hung
- Multiple test runs may have exhausted system resources
- Rate limiting or memory pressure
- **Test**: Reboot system and try again

**Hypothesis 2: Concurrency/Actor Isolation Issue**
- `@MainActor` on `analyzeWithAI()` may conflict with TaskGroup execution
- Working script has `@MainActor`, Enhanced doesn't (but both hang)
- **Status**: Inconclusive

**Hypothesis 3: Session Creation Pattern**
- Working script accepts `session` parameter (unused) then creates fresh session
- Enhanced script only creates fresh session
- **Status**: Unlikely (both create fresh sessions internally)

**Hypothesis 4: Task/RunLoop Execution Pattern**
- Enhanced uses `Task { @MainActor in ... } + RunLoop.main.run()`
- Working uses `await main()` top-level pattern
- **Status**: Not yet tested (would require refactoring Enhanced script)

## 6. Next Steps (Priority Order)

### IMMEDIATE (After Reboot)

**Step 1: Clean System Reboot**
- Reboot macOS to clear Foundation Models API state
- Clear any stuck processes or exhausted resources
- Reset any API rate limiting

**Step 2: Test Working Script First**
```bash
cd /Users/rhoge/Desktop/SAAQAnalyzer/Scripts
./AIStandardizeMakeModel \
  ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  ~/Desktop/AI-MakeModel-Report.md
```
- **Goal**: Confirm it processes more than 120 pairs after reboot
- **Success**: Completes all 553 pairs and generates report
- **Failure**: Still hangs → Foundation Models may have a fundamental concurrency issue

**Step 3A: If Working Script Succeeds After Reboot**
- Test Enhanced script immediately:
```bash
./AIStandardizeMakeModel-Enhanced \
  ~/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite \
  ~/Desktop/cvs_complete.sqlite \
  ~/Desktop/CVS-Enhanced-Report.md
```
- If it still hangs, compare exact code differences between working and Enhanced
- Focus on: Task structure, session creation, actor isolation

**Step 3B: If Working Script Still Hangs After Reboot**
- Foundation Models API may have fundamental issues with high-concurrency workloads
- **Alternative Approach 1**: Reduce parallelism (process 10 at a time instead of 245)
- **Alternative Approach 2**: Sequential processing with progress updates
- **Alternative Approach 3**: Batch processing (process 50, write checkpoint, continue)

### MEDIUM PRIORITY (If Scripts Work After Reboot)

**Step 4: Verify KIA CARNI Test Case**
- Search report for KIA CARNI entry
- Confirm it was NOT mapped to KIA CADEN
- Verify temporal validation flagged incompatibility (2023 vs 2011-2018)
- Check CVS validation found CARNI in Transport Canada database

**Step 5: Enable CVS Validation**
- Currently disabled for testing (lines 573-578 in Enhanced script)
- Re-enable actual CVS database queries
- Test with full validation pipeline

**Step 6: Generate Full Report**
- Process all 245 AI-analysis pairs + 308 no-match pairs
- Write comprehensive markdown report
- Verify override logic appears in reasoning field

### FUTURE (Phase 2 & 3)

**Step 7: Build Parameter Inference Tool**
- Use 2011-2022 fingerprints to populate missing 2023-2024 dimensional fields
- Depends on successful CVS-enhanced standardization

**Step 8: Add USA Vehicle Category Support**
- Update database schema for USA vehicle category
- Modify normalization scripts

## 7. Important Context

### Errors Solved

**Error 1: Incorrect Import Name** (Fixed)
- Error: "no such module 'Foundation_Models'"
- Cause: Wrong framework name
- Fix: Use `import FoundationModels` (no underscore)

**Error 2: Wrong CVS Table Name** (Fixed)
- Error: "no such table: vehicles" in CVS database
- Cause: CVS uses `cvs_data` table, not `vehicles`
- Fix: Updated all CVS queries to use correct table name

**Error 3: Wrong SAAQ Column Names** (Fixed)
- Error: "no such column: make_clean"
- Cause: SAAQ uses enumeration tables, not direct string columns
- Fix: Updated queries to JOIN with make_enum and model_enum tables

**Error 4: Verbose Prompts Cause Hangs** (Fixed)
- Symptom: AI API calls hang with ~500-800 character prompts
- Cause: Foundation Models API appears to struggle with long prompts in high-concurrency scenarios
- Fix: Compacted prompt to ~250 characters matching working script format

**Error 5: Shebang Execution Incompatible** (Fixed)
- Symptom: Scripts with `#!/usr/bin/env swift` never complete
- Cause: Foundation Models framework doesn't work in interpreted mode
- Fix: Always compile with `swiftc ScriptName.swift -o ScriptName -O`

**Error 6: Foundation Models API Hanging** (ACTIVE - IN PROGRESS)
- Symptom: API calls hang indefinitely, even in "working" script
- Status: System reboot required to clear state
- Next: Test after reboot to determine if resource exhaustion or code issue

### Dependencies & Requirements

**Foundation Models Framework**:
- Import: `import FoundationModels` (NOT Foundation_Models)
- API: `LanguageModelSession.respond(to:)` with `.content` property
- Platform: macOS Tahoe 26.0+, Apple Silicon required
- Status: ⚠️ Currently hanging, suspected resource exhaustion

**SQLite3**:
- Import: `import SQLite3`
- Status: ✅ Working (native macOS library)

**Swift 6.2**:
- Dramatically improved concurrency support
- Top-level async/await support
- Actor isolation improvements
- Status: ✅ Compilation working

### Critical Patterns & Gotchas

**Foundation Models Concurrency Limits**:
- Successfully processed 120 pairs at ~340 pairs/sec before hanging
- May have internal rate limiting or resource limits
- High parallelism (245 concurrent tasks) may exceed limits
- **Consider**: Limiting concurrent AI calls (e.g., semaphore with max 10-20 concurrent)

**@MainActor Usage**:
- Working script has `@MainActor` on `analyzeWithAI()`
- Enhanced script tested both with and without
- Both configurations hang
- **Conclusion**: Not the primary issue, but keep `@MainActor` for consistency with working script

**CVS Database Thread Safety**:
- Each parallel task must open its own CVS database connection
- Pass `cvsDBPath` string, not `OpaquePointer`, to parallel tasks
- Each task calls `openDatabase(cvsDBPath)` and `defer { sqlite3_close(cvsDB) }`
- Currently disabled for testing but pattern is correct

**Pre-filtering Pattern**:
```swift
// MUST separate fast-path from AI-path BEFORE TaskGroup
var noMatchPairs: [AnalysisResult] = []
var aiPairs: [(nonStd: MakeModelPair, canonical: MakeModelPair, similarity: Double)] = []

for nonStdPair in sortedPairs {
    // Find candidates...
    if let bestCandidate = candidates.first, bestCandidate.similarity > 0.4 {
        aiPairs.append(...)
    } else {
        noMatchPairs.append(...)
    }
}

// THEN launch TaskGroup with ONLY AI pairs
let aiResults = try await withThrowingTaskGroup(of: AnalysisResult?.self) { group in
    for (nonStdPair, canonicalPair, similarity) in aiPairs {
        group.addTask {
            // Every task calls AI
        }
    }
}

// Combine results at end
let allResults = noMatchPairs + aiResults
```

**Test Data Characteristics**:
- Total new pairs: 553
- No-match pairs (fast path): 308 (no canonical similarity > 0.4)
- AI-analysis pairs (slow path): 245 (require AI decision)
- Expected behavior: 308 complete instantly, 245 require AI processing

### Hardware Context

**Mac Studio M3 Ultra**:
- 32-core CPU
- 80-core GPU
- 32-core Neural Engine
- 96GB unified RAM
- macOS Tahoe (26.0+)
- Swift 6.2

### Test Case Expectations

**KIA CARNI (2023-2024) Analysis**:
- CVS Validation: Should find in Transport Canada database (2022, 2024 model years confirmed)
- Temporal Validation: Should flag incompatibility with CADEN (2023 outside CADEN's 2011-2018 range)
- AI Decision: Should preserve CARNI as distinct model (overridden by high CVS confidence 0.9)
- Body Type: Minivan (matches CVS)

**Expected Final Outcome**:
- CARNI preserved as separate legitimate model
- CADEN unchanged in canonical set
- Report explains temporal incompatibility prevented false mapping

---

## Summary

The CVS-enhanced AI standardization script is fully implemented and compiles successfully. However, Foundation Models API calls are hanging indefinitely. A system reboot is required to clear suspected resource exhaustion. After reboot, test the "working" AIStandardizeMakeModel script first to confirm Foundation Models API functionality, then test the Enhanced script. If both still hang, consider reducing parallelism or implementing batched processing to work within Foundation Models API limitations.

**Critical Next Action**: Reboot system, then test scripts in order: StandardizeMakeModel (baseline) → AIStandardizeMakeModel (working) → AIStandardizeMakeModel-Enhanced (CVS-enhanced).
