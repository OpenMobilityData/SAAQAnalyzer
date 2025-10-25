# RWI Settings Pane Design and Implementation

**Date**: October 24, 2025, 20:42:46
**Session Type**: Feature Design and Planning
**Status**: 🎯 **READY FOR IMPLEMENTATION**
**Complexity**: Medium-High (estimated 2-3 hours)

---

## 1. Executive Summary

### Current Session Accomplishments ✅

**Today's Completed Work:**
1. ✅ Removed all vestigial "optimized" terminology from codebase (3 commits)
   - QueryManager.swift: Cleaned up comments and print statements
   - DataModels.swift, RegularizationView.swift, QueryManagerTests.swift: Comment cleanup
2. ✅ Implemented "Exclude Zeroes" toggle feature (1 commit: c92b518)
   - User-configurable toggle to show/hide years with zero values
   - Default OFF (show all years for transparency)
   - Persistent via @AppStorage
   - Resolves ambiguity between NULL data and unmatched filters

**Git Status:**
- Branch: `rhoge-dev`
- Commits ahead of origin: 1 (c92b518)
- Working tree: Clean
- Ready to push or continue development

### Next Feature: RWI Settings Pane 🎯

**Objective**: Create a Settings pane that exposes Road Wear Index calculation logic, making assumptions transparent and allowing user customization of parameters.

**Why This Matters**:
- RWI is sophisticated but currently "black box" to users
- Hardcoded assumptions may not match all use cases
- Users need transparency for policy/research applications
- Foundation for future enhancements (custom vehicle data)

---

## 2. Current RWI Implementation (Baseline)

### Existing Code Locations

**Primary Implementation**: `QueryManager.swift:692-726`
```swift
case .roadWearIndex:
    // Road Wear Index: 4th power law based on vehicle mass
    // Uses actual axle count when available (max_axles), falls back to vehicle type
    let rwiCalculation = """
        CASE
            -- Use actual axle data when available (BCA trucks)
            WHEN v.max_axles = 2 THEN 0.1325 * POWER(v.net_mass_int, 4)
            WHEN v.max_axles = 3 THEN 0.0234 * POWER(v.net_mass_int, 4)
            WHEN v.max_axles = 4 THEN 0.0156 * POWER(v.net_mass_int, 4)
            WHEN v.max_axles = 5 THEN 0.0080 * POWER(v.net_mass_int, 4)
            WHEN v.max_axles >= 6 THEN 0.0046 * POWER(v.net_mass_int, 4)
            -- Fallback: vehicle type assumptions when max_axles is NULL
            WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code IN ('CA', 'VO'))
            THEN 0.0234 * POWER(v.net_mass_int, 4)
            WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'AB')
            THEN 0.1935 * POWER(v.net_mass_int, 4)
            ELSE 0.125 * POWER(v.net_mass_int, 4)
        END
        """
```

**Current Hardcoded Assumptions**:

| Axle Count | Weight Distribution | Coefficient | Used For |
|------------|-------------------|-------------|----------|
| 2 axles | 45% front, 55% rear | 0.1325 | Standard vehicles, fallback |
| 3 axles | 30% F, 35% R1, 35% R2 | 0.0234 | Heavy trucks, CA/VO types |
| 4 axles | 25% each | 0.0156 | Articulated trucks |
| 5 axles | 20% each | 0.0080 | Heavy transport |
| 6+ axles | ~16.67% each | 0.0046 | Specialized heavy vehicles |

**Vehicle Type Fallbacks** (when `max_axles` is NULL):
- **CA (Truck) / VO (Tool)**: Assume 3 axles → 0.0234
- **AB (Bus)**: Assume 2 axles (35/65 split) → 0.1935
- **AU (Car) / Other**: Assume 2 axles (50/50 split) → 0.125

**Documentation**: `CLAUDE.md:196-233` (comprehensive RWI section)

---

## 3. Proposed Feature Design

### 3.1 User Interface Structure

**Settings Window Location**:
- Add new tab: **"Road Wear Index"** (alongside "General" and "Regularization")
- Access via: Menu → Settings (⌘,) → Road Wear Index tab

**Layout Hierarchy**:
```
Settings Window
└── Road Wear Index Tab
    ├── Overview Section (read-only, educational)
    ├── Axle-Based Coefficients Section (editable)
    ├── Vehicle Type Fallbacks Section (editable)
    ├── Advanced Options Section (placeholder for future)
    └── Action Buttons (Reset to Defaults, Export, Import)
```

### 3.2 Section Details

#### **Section 1: Overview (Read-Only)**

**Purpose**: Educate users about RWI methodology

**Content**:
```
┌─────────────────────────────────────────────────────────────┐
│ Road Wear Index Overview                                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ The Road Wear Index (RWI) quantifies infrastructure impact  │
│ using the 4th power law:                                    │
│                                                              │
│   Road Damage ∝ (Axle Load)⁴                                │
│                                                              │
│ This means a vehicle with twice the axle load causes 16x    │
│ the road damage. The calculation uses:                      │
│                                                              │
│ • Actual axle count data when available (BCA trucks)        │
│ • Vehicle type assumptions as fallback (when axle data      │
│   is NULL)                                                   │
│ • Net vehicle mass (kg) from SAAQ records                   │
│                                                              │
│ Example: A 6-axle truck causes 97% less damage per kg       │
│ than a 2-axle truck due to weight distribution.             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Implementation**: Static text with SF Symbols icon (􀐾 chart.bar.doc.horizontal)

---

#### **Section 2: Axle-Based Coefficients (Editable)**

**Purpose**: Configure weight distribution and coefficients for vehicles with known axle counts

**UI Design**:
```
┌─────────────────────────────────────────────────────────────┐
│ Axle-Based Weight Distribution                              │
│ (Used when max_axles data is available)                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ Axles │ Weight Distribution      │ Coefficient │ Edit │  │
│ ├───────┼──────────────────────────┼─────────────┼──────┤  │
│ │   2   │ 45% F, 55% R             │ 0.1325      │ [✎] │  │
│ │   3   │ 30% F, 35% R1, 35% R2    │ 0.0234      │ [✎] │  │
│ │   4   │ 25% each                 │ 0.0156      │ [✎] │  │
│ │   5   │ 20% each                 │ 0.0080      │ [✎] │  │
│ │  6+   │ 16.67% each (6 axles)    │ 0.0046      │ [✎] │  │
│ └────────────────────────────────────────────────────────┘  │
│                                                              │
│ [Reset Axle Coefficients to Defaults]                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Edit Dialog** (when user clicks [✎]):
```
┌───────────────────────────────────────┐
│ Edit 3-Axle Configuration             │
├───────────────────────────────────────┤
│                                        │
│ Weight Distribution:                  │
│   Front Axle:    [30] %                │
│   Rear Axle 1:   [35] %                │
│   Rear Axle 2:   [35] %                │
│                  ───────                │
│   Total:         100 % ✓               │
│                                        │
│ Calculated Coefficient: 0.0234         │
│                                        │
│ ℹ️ Coefficient = Σ(weight_fraction⁴)  │
│                                        │
│         [Cancel]        [Save]         │
└───────────────────────────────────────┘
```

**Validation Rules**:
- Weight percentages must sum to 100%
- Each percentage must be > 0 and ≤ 100
- Number of weight fields matches axle count
- Auto-calculate coefficient: `Σ(weight_fraction⁴)`

**Data Model**:
```swift
struct AxleConfiguration: Codable, Equatable {
    let axleCount: Int  // 2, 3, 4, 5, or 6+
    var weightDistribution: [Double]  // Percentages (sum = 100)
    var coefficient: Double  // Calculated from distribution

    // Validation
    var isValid: Bool {
        let sum = weightDistribution.reduce(0, +)
        return abs(sum - 100.0) < 0.01 &&
               weightDistribution.allSatisfy { $0 > 0 && $0 <= 100 }
    }

    // Auto-calculate coefficient from distribution
    mutating func recalculateCoefficient() {
        coefficient = weightDistribution
            .map { pow($0 / 100.0, 4) }
            .reduce(0, +)
    }
}
```

---

#### **Section 3: Vehicle Type Fallbacks (Editable)**

**Purpose**: Configure assumptions for vehicles without axle data (max_axles is NULL)

**UI Design**:
```
┌─────────────────────────────────────────────────────────────┐
│ Vehicle Type Fallbacks                                       │
│ (Used when max_axles is NULL)                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ Type │ Description   │ Assumed │ Weight      │ Coef. │  │
│ │ Code │               │ Axles   │ Dist        │       │  │
│ ├──────┼───────────────┼─────────┼─────────────┼───────┤  │
│ │ CA   │ Truck         │ 3       │ 30/35/35    │ 0.0234│  │
│ │ VO   │ Tool Vehicle  │ 3       │ 30/35/35    │ 0.0234│  │
│ │ AB   │ Bus           │ 2       │ 35/65       │ 0.1935│  │
│ │ AU   │ Car           │ 2       │ 50/50       │ 0.1250│  │
│ │ *    │ Other         │ 2       │ 50/50       │ 0.1250│  │
│ └────────────────────────────────────────────────────────┘  │
│                                                              │
│ [Reset Vehicle Type Fallbacks to Defaults]                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Edit Dialog**: Similar to axle configuration, but includes:
- Dropdown to select assumed axle count (2-6+)
- Weight distribution fields (auto-populate based on axle count)
- Displays calculated coefficient

**Data Model**:
```swift
struct VehicleTypeFallback: Codable, Equatable, Identifiable {
    let id = UUID()
    let typeCode: String  // "CA", "VO", "AB", "AU", "*" (wildcard)
    let description: String  // "Truck", "Bus", etc.
    var assumedAxles: Int  // 2-6+
    var weightDistribution: [Double]  // Percentages
    var coefficient: Double  // Calculated

    var isValid: Bool {
        let sum = weightDistribution.reduce(0, +)
        return abs(sum - 100.0) < 0.01 &&
               weightDistribution.count == assumedAxles &&
               weightDistribution.allSatisfy { $0 > 0 && $0 <= 100 }
    }
}
```

---

#### **Section 4: Advanced Options (Future Placeholder)**

**Purpose**: Reserve space for Make/Model-specific overrides

**UI Design**:
```
┌─────────────────────────────────────────────────────────────┐
│ Advanced Options                                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ 🚧 Coming Soon                                              │
│                                                              │
│ Future capabilities:                                         │
│ • Make/Model-specific mass overrides                        │
│ • Make/Model-specific axle count defaults                   │
│ • Useful for uncurated years with incomplete data           │
│                                                              │
│ This feature will allow you to define defaults for new      │
│ vehicle combinations appearing in recent years.             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Implementation**: Disabled/grayed out section with explanatory text

---

#### **Section 5: Action Buttons**

**Buttons**:
```
┌────────────────────────────────────────────────────────┐
│                                                         │
│  [Reset All to Defaults]  [Export Config]  [Import]    │
│                                                         │
└────────────────────────────────────────────────────────┘
```

**Functionality**:
1. **Reset All to Defaults**:
   - Confirmation dialog: "Reset all RWI settings to defaults?"
   - Restores hardcoded values from current implementation
   - Clears UserDefaults and reinitializes

2. **Export Config**:
   - Save current settings to JSON file
   - NSSavePanel with suggested filename: `RWI_Configuration_YYYY-MM-DD.json`
   - Use case: Share configuration across machines, backup

3. **Import Config**:
   - NSOpenPanel to select JSON file
   - Validate schema before applying
   - Show preview/confirmation before overwriting current settings

---

## 4. Implementation Plan

### 4.1 File Structure

**New Files to Create**:
```
SAAQAnalyzer/
├── Settings/
│   ├── RWISettings.swift              # Main settings view
│   ├── RWIConfigurationManager.swift  # Configuration storage/logic
│   ├── RWIEditDialogs.swift           # Edit dialog views
│   └── RWIConfiguration.swift         # Data models
├── Utilities/
│   └── RWICalculator.swift            # Extract calculation logic
```

**Files to Modify**:
```
SAAQAnalyzer/
├── SAAQAnalyzerApp.swift              # Add RWI tab to Settings window
├── DataLayer/
│   └── QueryManager.swift             # Use RWICalculator instead of hardcoded
└── Models/
    └── DataModels.swift               # May need extensions
```

**Documentation to Update**:
```
Documentation/
├── CLAUDE.md                          # Reference user-configurable settings
└── ARCHITECTURAL_GUIDE.md             # Document RWI configuration system
```

---

### 4.2 Implementation Steps (Recommended Order)

#### **Phase 1: Data Models and Storage** (30-45 min)

1. **Create `RWIConfiguration.swift`**:
   ```swift
   import Foundation

   struct AxleConfiguration: Codable, Equatable {
       let axleCount: Int
       var weightDistribution: [Double]
       var coefficient: Double

       var isValid: Bool { /* validation */ }
       mutating func recalculateCoefficient() { /* calculate */ }
   }

   struct VehicleTypeFallback: Codable, Equatable, Identifiable {
       let id = UUID()
       let typeCode: String
       let description: String
       var assumedAxles: Int
       var weightDistribution: [Double]
       var coefficient: Double

       var isValid: Bool { /* validation */ }
   }

   struct RWIConfigurationData: Codable {
       var axleConfigurations: [Int: AxleConfiguration]  // Key = axle count
       var vehicleTypeFallbacks: [String: VehicleTypeFallback]  // Key = type code
       var schemaVersion: Int = 1  // For future migrations

       static var defaultConfiguration: RWIConfigurationData {
           // Return hardcoded defaults from current implementation
       }
   }
   ```

2. **Create `RWIConfigurationManager.swift`**:
   ```swift
   import Foundation

   @Observable
   class RWIConfigurationManager {
       static let shared = RWIConfigurationManager()

       private let storageKey = "rwiConfiguration"
       private(set) var configuration: RWIConfigurationData

       init() {
           // Load from UserDefaults or use defaults
           if let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(RWIConfigurationData.self, from: data) {
               self.configuration = decoded
           } else {
               self.configuration = .defaultConfiguration
           }
       }

       func save() {
           if let encoded = try? JSONEncoder().encode(configuration) {
               UserDefaults.standard.set(encoded, forKey: storageKey)
           }
       }

       func resetToDefaults() {
           configuration = .defaultConfiguration
           save()
       }

       func exportConfiguration(to url: URL) throws { /* export JSON */ }
       func importConfiguration(from url: URL) throws { /* import JSON */ }

       // Get coefficient for axle count
       func coefficient(forAxles axles: Int) -> Double {
           configuration.axleConfigurations[axles]?.coefficient ?? 0.125
       }

       // Get coefficient for vehicle type (fallback)
       func coefficient(forVehicleType typeCode: String) -> Double {
           configuration.vehicleTypeFallbacks[typeCode]?.coefficient
               ?? configuration.vehicleTypeFallbacks["*"]?.coefficient
               ?? 0.125
       }
   }
   ```

**Testing Checkpoint**:
- Unit tests for coefficient calculation
- Validate JSON encoding/decoding
- Test default configuration values

---

#### **Phase 2: Calculation Logic Extraction** (30-45 min)

3. **Create `RWICalculator.swift`**:
   ```swift
   import Foundation

   struct RWICalculator {
       let configManager = RWIConfigurationManager.shared

       /// Generate SQL CASE expression for RWI calculation
       /// Returns SQL string that can be embedded in queries
       func generateSQLCalculation() -> String {
           var cases: [String] = []

           // Axle-based cases (when max_axles is not NULL)
           for (axleCount, config) in configManager.configuration.axleConfigurations.sorted(by: { $0.key < $1.key }) {
               let condition = axleCount == 6
                   ? "v.max_axles >= 6"
                   : "v.max_axles = \(axleCount)"
               cases.append("WHEN \(condition) THEN \(config.coefficient) * POWER(v.net_mass_int, 4)")
           }

           // Vehicle type fallbacks (when max_axles is NULL)
           for (typeCode, fallback) in configManager.configuration.vehicleTypeFallbacks {
               if typeCode == "*" {
                   // Wildcard fallback goes in ELSE clause
                   continue
               }
               cases.append("""
                   WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = '\(typeCode)')
                   THEN \(fallback.coefficient) * POWER(v.net_mass_int, 4)
                   """)
           }

           // Default fallback
           let defaultCoef = configManager.configuration.vehicleTypeFallbacks["*"]?.coefficient ?? 0.125

           return """
               CASE
                   \(cases.joined(separator: "\n    "))
                   ELSE \(defaultCoef) * POWER(v.net_mass_int, 4)
               END
               """
       }
   }
   ```

4. **Modify `QueryManager.swift`**:
   - Replace hardcoded RWI calculation with `RWICalculator().generateSQLCalculation()`
   - Location: `QueryManager.swift:692-726`

   ```swift
   case .roadWearIndex:
       let calculator = RWICalculator()
       let rwiCalculation = calculator.generateSQLCalculation()

       if filters.roadWearIndexMode == .average {
           selectClause = "AVG(\(rwiCalculation)) as value"
           additionalWhereConditions = " AND v.net_mass_int IS NOT NULL"
       } else if filters.roadWearIndexMode == .median {
           // ... median logic
       } else {
           selectClause = "SUM(\(rwiCalculation)) as value"
           additionalWhereConditions = " AND v.net_mass_int IS NOT NULL"
       }
   ```

**Testing Checkpoint**:
- SQL generation produces valid queries
- Queries execute without errors
- Results match previous hardcoded implementation

---

#### **Phase 3: Settings UI** (60-90 min)

5. **Create `RWISettings.swift`**:
   ```swift
   import SwiftUI

   struct RWISettingsView: View {
       @State private var configManager = RWIConfigurationManager.shared
       @State private var showingResetConfirmation = false
       @State private var editingAxleConfig: AxleConfiguration?
       @State private var editingVehicleType: VehicleTypeFallback?

       var body: some View {
           ScrollView {
               VStack(alignment: .leading, spacing: 24) {
                   // Overview Section
                   overviewSection

                   Divider()

                   // Axle-Based Coefficients Section
                   axleCoefficientsSection

                   Divider()

                   // Vehicle Type Fallbacks Section
                   vehicleTypeFallbacksSection

                   Divider()

                   // Advanced Options (placeholder)
                   advancedOptionsSection

                   Divider()

                   // Action Buttons
                   actionButtonsSection
               }
               .padding()
           }
           .frame(width: 700, height: 600)
           .sheet(item: $editingAxleConfig) { config in
               AxleConfigEditView(configuration: $editingAxleConfig) { updated in
                   // Save updated config
                   configManager.configuration.axleConfigurations[updated.axleCount] = updated
                   configManager.save()
               }
           }
           .sheet(item: $editingVehicleType) { fallback in
               VehicleTypeFallbackEditView(fallback: $editingVehicleType) { updated in
                   // Save updated fallback
                   configManager.configuration.vehicleTypeFallbacks[updated.typeCode] = updated
                   configManager.save()
               }
           }
           .confirmationDialog("Reset All RWI Settings?", isPresented: $showingResetConfirmation) {
               Button("Reset to Defaults", role: .destructive) {
                   configManager.resetToDefaults()
               }
               Button("Cancel", role: .cancel) {}
           } message: {
               Text("This will restore all Road Wear Index settings to their default values. This action cannot be undone.")
           }
       }

       // Section views...
   }
   ```

6. **Create `RWIEditDialogs.swift`**:
   - `AxleConfigEditView`: Edit weight distribution for axle configuration
   - `VehicleTypeFallbackEditView`: Edit fallback configuration
   - Include validation UI (weight sum must = 100%)
   - Auto-calculate coefficient when user changes weights
   - Prevent saving invalid configurations

7. **Update `SAAQAnalyzerApp.swift`**:
   - Add RWI tab to Settings window
   - Location: Around line 1918 (in RegularizationSettingsView)

   ```swift
   TabView {
       GeneralSettingsView()
           .tabItem {
               Label("General", systemImage: "gearshape")
           }

       RegularizationSettingsView(databaseManager: databaseManager)
           .tabItem {
               Label("Regularization", systemImage: "wand.and.stars")
           }

       RWISettingsView()
           .tabItem {
               Label("Road Wear Index", systemImage: "chart.bar.doc.horizontal")
           }
   }
   .frame(width: 700, height: 600)
   ```

**Testing Checkpoint**:
- Settings UI displays correctly
- Edit dialogs open and validate input
- Changes persist across app restarts
- Reset to defaults works correctly

---

#### **Phase 4: Import/Export** (30 min)

8. **Implement Export**:
   ```swift
   func exportConfiguration() {
       let savePanel = NSSavePanel()
       savePanel.allowedContentTypes = [.json]
       savePanel.nameFieldStringValue = "RWI_Configuration_\(Date().formatted(.iso8601.year().month().day())).json"

       savePanel.begin { response in
           guard response == .OK, let url = savePanel.url else { return }

           do {
               try configManager.exportConfiguration(to: url)
               // Show success message
           } catch {
               // Show error alert
           }
       }
   }
   ```

9. **Implement Import**:
   ```swift
   func importConfiguration() {
       let openPanel = NSOpenPanel()
       openPanel.allowedContentTypes = [.json]
       openPanel.allowsMultipleSelection = false

       openPanel.begin { response in
           guard response == .OK, let url = openPanel.urls.first else { return }

           do {
               try configManager.importConfiguration(from: url)
               // Show success message
           } catch {
               // Show validation error
           }
       }
   }
   ```

**Testing Checkpoint**:
- Export produces valid JSON
- Exported file can be imported
- Invalid JSON files are rejected with helpful error
- Imported settings are applied immediately

---

#### **Phase 5: Testing and Documentation** (30-45 min)

10. **Create Unit Tests**:
    ```swift
    // RWIConfigurationTests.swift

    func testCoefficientCalculation() {
        var config = AxleConfiguration(
            axleCount: 2,
            weightDistribution: [50.0, 50.0],
            coefficient: 0.0
        )
        config.recalculateCoefficient()
        XCTAssertEqual(config.coefficient, 0.125, accuracy: 0.0001)
    }

    func testWeightDistributionValidation() {
        let valid = AxleConfiguration(
            axleCount: 3,
            weightDistribution: [30.0, 35.0, 35.0],
            coefficient: 0.0234
        )
        XCTAssertTrue(valid.isValid)

        let invalid = AxleConfiguration(
            axleCount: 3,
            weightDistribution: [30.0, 30.0, 30.0],  // Sums to 90%
            coefficient: 0.0
        )
        XCTAssertFalse(invalid.isValid)
    }

    func testSQLGeneration() {
        let calculator = RWICalculator()
        let sql = calculator.generateSQLCalculation()

        XCTAssertTrue(sql.contains("CASE"))
        XCTAssertTrue(sql.contains("POWER(v.net_mass_int, 4)"))
        XCTAssertTrue(sql.contains("WHEN v.max_axles = 2"))
    }
    ```

11. **Update Documentation**:

    **CLAUDE.md changes**:
    ```markdown
    ### Road Wear Index Configuration

    The application includes user-configurable settings for Road Wear Index
    calculations. Access via Settings → Road Wear Index tab.

    **Configuration Options**:
    - Axle-based weight distributions (when max_axles data available)
    - Vehicle type fallback assumptions (when max_axles is NULL)
    - Import/export configurations for sharing across machines

    **Default Settings**:
    - Based on standard engineering assumptions for Quebec vehicle fleet
    - Documented in Settings UI with explanatory tooltips
    - Can be reset to defaults at any time

    **File Locations**:
    - Configuration: `RWIConfiguration.swift`
    - Calculator: `RWICalculator.swift`
    - Settings UI: `RWISettings.swift`
    - Storage: UserDefaults (key: "rwiConfiguration")
    ```

    **ARCHITECTURAL_GUIDE.md**:
    - Add section on RWI configuration system
    - Document the two-tier fallback strategy (axles → vehicle type → default)
    - Explain coefficient calculation formula
    - Reference Settings UI for user customization

---

## 5. Technical Considerations

### 5.1 Storage Strategy

**Recommended Approach**: UserDefaults with JSON encoding
```swift
// Pros:
// - Simple implementation
// - Automatic sync via iCloud (if enabled)
// - No file management needed
// - Built-in versioning via schemaVersion

// Cons:
// - Size limit (~4MB, not a concern for this data)
// - No transactional updates (not needed here)
```

**Alternative**: Separate config file in Application Support
```swift
// Use if configuration grows large or needs transactional updates
let url = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SAAQAnalyzer")
    .appendingPathComponent("RWIConfiguration.json")
```

**Recommendation**: Start with UserDefaults, migrate to file-based if needed

---

### 5.2 SQL Generation Considerations

**Current Approach**: String interpolation in Swift
```swift
// Pros:
// - Simple, readable
// - Easy to debug
// - No SQL injection risk (no user input in SQL)

// Cons:
// - String manipulation can be error-prone
// - No SQL syntax validation at compile time
```

**Safety Measures**:
1. **No user input in SQL**: All values come from validated Swift structs
2. **Type checking**: Vehicle type codes validated against enum table
3. **Testing**: Verify generated SQL with EXPLAIN QUERY PLAN
4. **Logging**: Log generated SQL for debugging

**Example Test**:
```swift
func testGeneratedSQLIsValid() async throws {
    let calculator = RWICalculator()
    let sql = calculator.generateSQLCalculation()

    // Test that SQL executes without error
    let query = "SELECT \(sql) as rwi FROM vehicles LIMIT 1"
    let result = try await databaseManager.executeQuery(query)

    XCTAssertNotNil(result)
}
```

---

### 5.3 Backward Compatibility

**Schema Versioning**:
```swift
struct RWIConfigurationData: Codable {
    var schemaVersion: Int = 1
    // ...

    // Future migration example:
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)

        switch version {
        case 1:
            // Decode v1 format
            self.schemaVersion = 1
            // ...
        case 2:
            // Future: Handle v2 format
            self.schemaVersion = 2
            // ...
        default:
            throw DecodingError.dataCorrupted(/* ... */)
        }
    }
}
```

**Handling Missing Config**:
```swift
// Always fall back to defaults if config is missing/corrupt
init() {
    if let data = UserDefaults.standard.data(forKey: storageKey),
       let decoded = try? JSONDecoder().decode(RWIConfigurationData.self, from: data) {
        self.configuration = decoded
    } else {
        // Graceful fallback
        self.configuration = .defaultConfiguration
        AppLogger.app.warning("Failed to load RWI config, using defaults")
    }
}
```

---

### 5.4 Performance Considerations

**SQL Generation Caching**:
```swift
class RWICalculator {
    private var cachedSQL: String?
    private var lastConfigHash: Int?

    func generateSQLCalculation() -> String {
        let currentHash = configManager.configuration.hashValue

        if let cached = cachedSQL, lastConfigHash == currentHash {
            return cached
        }

        // Regenerate SQL
        let sql = generateSQLInternal()
        cachedSQL = sql
        lastConfigHash = currentHash

        return sql
    }
}
```

**Why Caching Matters**:
- SQL generation called for every RWI query
- Configuration changes infrequently
- String manipulation can be expensive for complex configs
- Cache invalidation simple: compare hash values

**Expected Performance**:
- Cached lookup: <0.001ms
- Fresh generation: <1ms (negligible)
- Query execution: Dominated by database time, not SQL generation

---

### 5.5 UI/UX Best Practices

**Validation Feedback**:
```swift
// Real-time validation with visual feedback
struct WeightDistributionField: View {
    @Binding var weights: [Double]

    var totalWeight: Double { weights.reduce(0, +) }
    var isValid: Bool { abs(totalWeight - 100.0) < 0.01 }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(weights.indices, id: \.self) { index in
                HStack {
                    Text("Axle \(index + 1):")
                    TextField("Percent", value: $weights[index], format: .number)
                        .frame(width: 60)
                    Text("%")
                }
            }

            Divider()

            HStack {
                Text("Total:")
                Text(String(format: "%.1f%%", totalWeight))
                    .foregroundColor(isValid ? .green : .red)

                if isValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
        }
    }
}
```

**Prevent Invalid States**:
```swift
// Disable Save button until valid
Button("Save") {
    saveConfiguration()
}
.disabled(!configuration.isValid)
```

**Confirmation for Destructive Actions**:
```swift
// Always confirm before reset
.confirmationDialog("Reset All RWI Settings?", isPresented: $showingResetConfirmation) {
    Button("Reset to Defaults", role: .destructive) {
        configManager.resetToDefaults()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will restore all Road Wear Index settings to their default values. This action cannot be undone.")
}
```

---

### 5.6 Testing Strategy

**Unit Tests** (Priority 1):
```swift
// RWIConfigurationTests.swift
- testCoefficientCalculation()
- testWeightDistributionValidation()
- testInvalidWeightDistribution()
- testAxleConfigurationCoding()
- testVehicleTypeFallbackCoding()
- testDefaultConfiguration()
- testSchemaVersionMigration()

// RWICalculatorTests.swift
- testSQLGeneration()
- testSQLGenerationWithCustomConfig()
- testSQLCaching()
- testSQLValidation()

// RWIConfigurationManagerTests.swift
- testSaveAndLoad()
- testResetToDefaults()
- testExportConfiguration()
- testImportConfiguration()
- testImportInvalidJSON()
```

**Integration Tests** (Priority 2):
```swift
// RWIQueryIntegrationTests.swift
- testRWIQueryWithDefaultConfig()
- testRWIQueryWithCustomConfig()
- testRWIResultsMatchExpected()
- testConfigurationChangeUpdatesQueries()
```

**UI Tests** (Priority 3):
```swift
// RWISettingsUITests.swift
- testEditAxleConfiguration()
- testEditVehicleTypeFallback()
- testResetToDefaults()
- testExportImport()
- testValidationFeedback()
```

**Manual Testing Checklist**:
- [ ] Open Settings → Road Wear Index tab
- [ ] Edit 2-axle configuration, verify coefficient updates
- [ ] Enter invalid weights (sum ≠ 100%), verify Save disabled
- [ ] Reset to defaults, verify all values restore
- [ ] Export config, verify JSON is valid
- [ ] Import exported config, verify settings apply
- [ ] Run RWI query, verify results match expected
- [ ] Modify config, verify queries use new coefficients
- [ ] Close and reopen app, verify settings persist

---

## 6. Future Enhancements (Post-MVP)

### 6.1 Make/Model-Specific Overrides

**Use Case**: User knows a specific make/model has different mass/axle characteristics than database default

**UI Design**:
```
┌─────────────────────────────────────────────────────────────┐
│ Make/Model Overrides                                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ [Add Override]                                              │
│                                                              │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ Make      │ Model  │ Override     │ Value   │ Remove │  │
│ ├───────────┼────────┼──────────────┼─────────┼────────┤  │
│ │ TESLA     │ MODEL3 │ Mass (kg)    │ 1850    │ [✗]   │  │
│ │ VOLVO     │ VNL    │ Axle Count   │ 5       │ [✗]   │  │
│ │ FORD      │ F-150  │ Weight Dist  │ 40/60   │ [✗]   │  │
│ └────────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Implementation**:
```swift
struct MakeModelOverride: Codable, Identifiable {
    let id = UUID()
    let makeId: Int
    let modelId: Int
    var overrideType: OverrideType
    var value: OverrideValue

    enum OverrideType: String, Codable {
        case mass = "Mass (kg)"
        case axleCount = "Axle Count"
        case weightDistribution = "Weight Distribution"
    }

    enum OverrideValue: Codable {
        case mass(Int)
        case axleCount(Int)
        case weightDistribution([Double])
    }
}
```

**SQL Integration**:
```sql
-- Join with overrides table
LEFT JOIN make_model_overrides o
    ON v.make_id = o.make_id
    AND v.model_id = o.model_id

-- Use override value if present
COALESCE(o.mass_override, v.net_mass_int) as net_mass
COALESCE(o.axle_count_override, v.max_axles) as axle_count
```

---

### 6.2 Historical Configuration Tracking

**Use Case**: User wants to see how RWI results change with different assumptions

**Feature**: Save named configuration presets

```
┌─────────────────────────────────────────────────────────────┐
│ Configuration Presets                                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ Active Preset: [Default ▼]                                  │
│                                                              │
│ Saved Presets:                                              │
│ • Default (factory settings)                                │
│ • Conservative (higher penalties for heavy vehicles)        │
│ • Engineering Study 2025-10-24                              │
│                                                              │
│ [Save Current as New Preset]  [Delete Preset]               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

### 6.3 RWI Coefficient Calculator Tool

**Use Case**: User wants to experiment with weight distributions to see impact on coefficient

**Feature**: Interactive calculator
```
┌─────────────────────────────────────────────────────────────┐
│ RWI Coefficient Calculator                                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ Number of Axles: [3 ▼]                                      │
│                                                              │
│ Weight Distribution:                                         │
│   Axle 1: [━━━━━━━━━━━━] 30%                               │
│   Axle 2: [━━━━━━━━━━━━━━] 35%                             │
│   Axle 3: [━━━━━━━━━━━━━━] 35%                             │
│           Total: 100% ✓                                     │
│                                                              │
│ Calculated Coefficient: 0.0234                              │
│                                                              │
│ Road Damage Comparison:                                     │
│ This configuration causes 82% less damage per kg            │
│ compared to 50/50 2-axle vehicle                            │
│                                                              │
│ [Apply to Configuration]                                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

### 6.4 Visualization of RWI Assumptions

**Use Case**: User wants to see graphical representation of weight distributions

**Feature**: Chart showing damage per kg for different configurations
```
Road Damage per kg vs. Axle Configuration

Damage │  ████████████████  2-axle (50/50)    0.125
Index  │  ████████████████  2-axle (35/65)    0.194
       │  ████████         3-axle (30/35/35)  0.023
       │  ██████           4-axle (25/25...)  0.016
       │  ████             5-axle (20/20...)  0.008
       │  ██               6-axle (16.67...)  0.005
       └────────────────────────────────────────────
```

---

## 7. Known Challenges and Solutions

### Challenge 1: AppKit Dependency

**Issue**: Using NSOpenPanel/NSSavePanel for import/export (AppKit)

**Solution Options**:
1. **Accept AppKit** (RECOMMENDED):
   - Already using AppKit elsewhere (`CLAUDE.md` line 39)
   - File dialogs are cleaner with AppKit
   - macOS-only app, no cross-platform concerns

2. **Use SwiftUI fileImporter/fileExporter**:
   - More SwiftUI-native
   - Known bugs with multiple file dialogs (line 105-112 in SAAQAnalyzerApp.swift)
   - May need workarounds

**Recommendation**: Use AppKit for Settings window (isolated usage)

---

### Challenge 2: Real-Time SQL Regeneration

**Issue**: Configuration changes must immediately affect queries

**Solution**:
1. **RWICalculator caching** (implemented in Phase 2)
2. **Configuration observer pattern**:
   ```swift
   class RWIConfigurationManager {
       var onConfigurationChanged: (() -> Void)?

       func save() {
           // Save to storage
           onConfigurationChanged?()  // Notify observers
       }
   }

   // In QueryManager
   init() {
       RWIConfigurationManager.shared.onConfigurationChanged = { [weak self] in
           self?.invalidateCachedSQL()
       }
   }
   ```

3. **Query re-execution**:
   - Settings changes don't auto-refresh charts
   - User must re-execute query to see new results
   - Add notice: "Settings changed. Re-run query to see updated results."

---

### Challenge 3: Validation Complexity

**Issue**: Multiple validation rules (weights sum to 100%, positive values, etc.)

**Solution**: Centralized validation with helpful error messages
```swift
enum ValidationError: Error, LocalizedError {
    case weightsSumIncorrect(expected: Double, actual: Double)
    case negativeWeight(index: Int, value: Double)
    case invalidAxleCount(count: Int)

    var errorDescription: String? {
        switch self {
        case .weightsSumIncorrect(let expected, let actual):
            return "Weight distribution must sum to \(expected)%, but sums to \(actual)%"
        case .negativeWeight(let index, let value):
            return "Axle \(index + 1) has invalid weight: \(value)%"
        case .invalidAxleCount(let count):
            return "Axle count must be between 2 and 6, got \(count)"
        }
    }
}

struct AxleConfiguration {
    func validate() throws {
        let sum = weightDistribution.reduce(0, +)
        if abs(sum - 100.0) > 0.01 {
            throw ValidationError.weightsSumIncorrect(expected: 100.0, actual: sum)
        }

        for (index, weight) in weightDistribution.enumerated() {
            if weight < 0 || weight > 100 {
                throw ValidationError.negativeWeight(index: index, value: weight)
            }
        }
    }
}
```

---

### Challenge 4: Testing SQL Generation

**Issue**: Need to verify generated SQL is valid without running full queries

**Solution**: Use EXPLAIN QUERY PLAN
```swift
func testGeneratedSQLIsValid() async throws {
    let calculator = RWICalculator()
    let sql = calculator.generateSQLCalculation()

    let query = "EXPLAIN QUERY PLAN SELECT \(sql) as rwi FROM vehicles v LIMIT 1"

    let result = try await databaseManager.executeQuery(query)
    XCTAssertNotNil(result, "Generated SQL should be valid")
}
```

---

## 8. Code Reference Locations

### Files with RWI Logic (Current)

**QueryManager.swift**:
- Lines 692-726: RWI calculation (PRIMARY - REPLACE THIS)
- Used in: Vehicle queries only (not license queries)

**CLAUDE.md**:
- Lines 196-233: RWI documentation
- Lines 39-44: NS-prefixed API warning (AppKit usage)

**DataModels.swift**:
- Lines 1081-1095: RoadWearIndexMode enum
- Lines 1073: roadWearIndexMode property in FilterConfiguration

**FilterPanel.swift**:
- Lines 1731-1768: RWI mode selector UI
- Lines 1908: roadWearIndexMode binding parameter

**ChartView.swift**:
- Lines 385-387: RWI y-axis formatting
- Lines 688: RWI legend display

**DatabaseManager.swift**:
- Lines 1227-1245: RWI calculation (legacy path, not used)
- Lines 1923-1941: RWI calculation (percentage query path, legacy)

### Settings Infrastructure (Existing Patterns)

**SAAQAnalyzerApp.swift**:
- Lines 1512-1640: GeneralSettingsView (appearance mode)
- Lines 1918-2046: RegularizationSettingsView (good template)
- Lines 1918-1919: @AppStorage pattern for persistence

**Pattern to Follow**:
```swift
struct RegularizationSettingsView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @AppStorage("regularizationEnabled") private var regularizationEnabled = false
    @AppStorage("regularizationCoupling") private var regularizationCoupling = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Query Regularization", isOn: $regularizationEnabled)
                // ...
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

**Apply this pattern to RWISettingsView**

---

## 9. Success Criteria

### Minimum Viable Product (MVP)

**Must Have**:
- ✅ Settings tab appears in Settings window
- ✅ Display current RWI configuration (read-only overview)
- ✅ Edit axle-based coefficients (2-6+ axles)
- ✅ Edit vehicle type fallbacks (CA, VO, AB, AU, *)
- ✅ Validate weight distributions (sum = 100%)
- ✅ Auto-calculate coefficients from distributions
- ✅ Reset to defaults functionality
- ✅ Configuration persists across app restarts
- ✅ Queries use custom configuration
- ✅ Export/import configuration as JSON

**Nice to Have** (defer if time-constrained):
- Export/import JSON configurations
- Advanced options placeholder section
- Comprehensive unit test coverage
- Updated documentation

### Testing Checklist (Must Pass)

**Functional Tests**:
- [ ] Settings UI displays without errors
- [ ] Edit dialog opens and validates input
- [ ] Invalid configurations cannot be saved
- [ ] Coefficient auto-calculates correctly
- [ ] Reset to defaults restores hardcoded values
- [ ] Configuration persists after app restart
- [ ] RWI queries execute without SQL errors
- [ ] Results match expected values for known configs

**Edge Cases**:
- [ ] Weights sum to 99.99% (rounding tolerance)
- [ ] Weights sum to 0% (invalid, rejected)
- [ ] Negative weights (invalid, rejected)
- [ ] Single axle (invalid, rejected)
- [ ] 10+ axles (should work, treat as 6+)
- [ ] Empty UserDefaults (graceful fallback to defaults)
- [ ] Corrupted JSON import (validation error with helpful message)

**Performance**:
- [ ] SQL generation < 1ms (uncached)
- [ ] SQL generation < 0.001ms (cached)
- [ ] Settings UI opens in < 500ms
- [ ] Configuration save < 100ms

---

## 10. Post-Implementation Tasks

### Documentation Updates

**CLAUDE.md**:
```markdown
### Road Wear Index Configuration

The Road Wear Index (RWI) calculation is fully user-configurable via
Settings → Road Wear Index tab.

**Configurable Parameters**:
- Axle-based weight distributions (2-6+ axles)
- Vehicle type fallback assumptions (CA, VO, AB, AU, *)
- Import/export configurations for sharing

**Default Configuration**:
Based on standard engineering assumptions for Quebec vehicle fleet.
Can be reset to defaults at any time.

**Configuration Storage**:
- Location: UserDefaults (key: "rwiConfiguration")
- Format: JSON (exportable/importable)
- Version: 1 (schema versioning for future migrations)

**File Locations**:
- Configuration models: `Settings/RWIConfiguration.swift`
- Settings UI: `Settings/RWISettings.swift`
- Calculator: `Utilities/RWICalculator.swift`
- Manager: `Settings/RWIConfigurationManager.swift`
```

**ARCHITECTURAL_GUIDE.md**:
Add new section:
```markdown
## RWI Configuration System

### Overview

The Road Wear Index (RWI) system uses a two-tier fallback strategy:
1. **Primary**: Actual axle count data (when max_axles is not NULL)
2. **Fallback**: Vehicle type assumptions (when max_axles is NULL)
3. **Default**: Wildcard fallback for unknown vehicle types

### Architecture

**Configuration Model**:
- `RWIConfigurationData`: Root configuration object
- `AxleConfiguration`: Axle-specific weight distributions
- `VehicleTypeFallback`: Vehicle type assumptions

**Calculation Flow**:
1. User modifies settings via UI
2. Settings saved to UserDefaults (JSON encoded)
3. RWICalculator reads configuration
4. SQL CASE expression generated
5. SQL embedded in vehicle queries
6. Database executes query with custom coefficients

### Coefficient Calculation

Coefficient = Σ(weight_fraction⁴)

Example (3 axles, 30/35/35 distribution):
Coefficient = (0.30)⁴ + (0.35)⁴ + (0.35)⁴ = 0.0234

### SQL Generation

RWICalculator generates dynamic SQL CASE expression:
```sql
CASE
    WHEN v.max_axles = 2 THEN 0.1325 * POWER(v.net_mass_int, 4)
    WHEN v.max_axles = 3 THEN 0.0234 * POWER(v.net_mass_int, 4)
    ...
    WHEN v.vehicle_type_id IN (...) THEN 0.0234 * POWER(...)
    ELSE 0.125 * POWER(v.net_mass_int, 4)
END
```

### Extensibility

Future enhancements:
- Make/Model-specific overrides
- Configuration presets
- Historical configuration tracking
- Visual coefficient calculator
```

---

### Git Commit Message Template

```
feat: Add user-configurable RWI Settings pane

Implement comprehensive settings UI for Road Wear Index calculations,
making assumptions transparent and allowing user customization.

Features:
- Settings tab in Settings window (⌘,)
- Editable axle-based weight distributions (2-6+ axles)
- Editable vehicle type fallback assumptions (CA, VO, AB, AU, *)
- Real-time validation (weights must sum to 100%)
- Auto-calculated coefficients from weight distributions
- Reset to defaults functionality
- Configuration persistence via UserDefaults
- Export/import configurations as JSON

Implementation:
- RWIConfiguration.swift: Data models (AxleConfiguration, VehicleTypeFallback)
- RWIConfigurationManager.swift: Storage and persistence logic
- RWICalculator.swift: SQL generation from configuration
- RWISettings.swift: Settings UI with validation
- RWIEditDialogs.swift: Edit dialogs for configurations

Changes:
- QueryManager.swift: Use RWICalculator instead of hardcoded SQL
- SAAQAnalyzerApp.swift: Add RWI tab to Settings window
- CLAUDE.md: Document user-configurable settings
- ARCHITECTURAL_GUIDE.md: Document RWI configuration system

Benefits:
- Transparency: Users see all assumptions clearly
- Flexibility: Customize for different use cases
- Validation: Prevents invalid configurations
- Portability: Export/import for sharing
- Foundation for future Make/Model-specific overrides

Testing:
- Unit tests for coefficient calculation
- Validation tests for weight distributions
- SQL generation tests
- Integration tests for query execution
- UI tests for settings interactions

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## 11. Quick Start Guide (For Next Session)

### Immediate Next Steps

1. **Read this document thoroughly** (15 min)
2. **Review current RWI implementation** (10 min):
   - Read `QueryManager.swift:692-726`
   - Read `CLAUDE.md:196-233`
3. **Create data models** (30 min):
   - Create `Settings/RWIConfiguration.swift`
   - Implement `AxleConfiguration` struct
   - Implement `VehicleTypeFallback` struct
   - Implement `RWIConfigurationData` struct with defaults
4. **Create configuration manager** (30 min):
   - Create `Settings/RWIConfigurationManager.swift`
   - Implement save/load from UserDefaults
   - Implement reset to defaults
5. **Extract calculation logic** (30 min):
   - Create `Utilities/RWICalculator.swift`
   - Implement SQL generation
   - Add caching
6. **Update QueryManager** (15 min):
   - Replace hardcoded SQL with `RWICalculator().generateSQLCalculation()`
7. **Test calculation** (15 min):
   - Run app, execute RWI query
   - Verify results match previous implementation
8. **Create Settings UI** (60-90 min):
   - Create `Settings/RWISettings.swift`
   - Implement overview section
   - Implement axle coefficients table
   - Implement vehicle type fallbacks table
9. **Create edit dialogs** (45 min):
   - Create `Settings/RWIEditDialogs.swift`
   - Implement validation UI
10. **Add to Settings window** (15 min):
    - Update `SAAQAnalyzerApp.swift`
    - Add RWI tab

**Total Estimated Time**: 4-5 hours

---

## 12. Questions for User (If Clarification Needed)

1. **Default Configuration**:
   - Are current hardcoded assumptions acceptable as defaults?
   - Should we add tooltip explaining why these specific values were chosen?

2. **UI Placement**:
   - Settings window → RWI tab (as designed)?
   - Or separate RWI configuration window?

3. **Export/Import**:
   - Should exported JSON be human-readable (pretty-printed)?
   - Should we support importing from URL (not just file)?

4. **Validation Strictness**:
   - Allow small rounding errors (99.99% vs 100%)?
   - Or require exact 100.00%?

5. **Future Features**:
   - Priority order for enhancements?
   - Should we implement Make/Model overrides in same session?

---

## 13. Session Context Summary

**Current State**:
- Branch: `rhoge-dev`
- Unpushed commits: 1 (Exclude Zeroes feature)
- Working tree: Clean
- All tests passing
- Production ready

**Recent Work** (October 24, 2025):
- Removed vestigial "optimized" terminology (3 commits)
- Implemented "Exclude Zeroes" toggle (1 commit)
- Both features tested and working

**Next Feature**: RWI Settings Pane (this document)

**Team Context**:
- Solo developer (rhoge)
- macOS-only application
- Swift 6.2, SwiftUI
- SQLite database (35GB+ in production)
- Active development on `rhoge-dev` branch

---

**End of Handoff Document**

*Generated: October 24, 2025, 20:42:46*
*Session Type: Feature Design and Implementation Planning*
*Status: 🎯 READY FOR IMPLEMENTATION*
*Estimated Complexity: Medium-High (4-5 hours)*
*Priority: High (transparency and user control)*
