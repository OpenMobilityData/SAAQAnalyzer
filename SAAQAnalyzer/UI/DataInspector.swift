import SwiftUI
import UniformTypeIdentifiers

/// Data inspector panel showing details of selected series
struct DataInspectorView: View {
    let series: FilteredDataSeries?
    @State private var selectedTab: InspectorTab = .summary
    
    enum InspectorTab: String, CaseIterable {
        case summary = "Summary"
        case data = "Data"
        case statistics = "Statistics"
        
        var systemImage: String {
            switch self {
            case .summary: return "info.circle"
            case .data: return "tablecells"
            case .statistics: return "chart.bar.doc.horizontal"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Data Inspector", systemImage: "sidebar.right")
                    .font(.headline)
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            if let series = series {
                // Tab selector
                Picker("Inspector Tab", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Tab content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .summary:
                            SeriesSummaryView(series: series)
                        case .data:
                            SeriesDataView(series: series)
                        case .statistics:
                            SeriesStatisticsView(series: series)
                        }
                    }
                    .padding()
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Series Selected")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Select a data series from the chart to view details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Series Summary View

struct SeriesSummaryView: View {
    let series: FilteredDataSeries
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Series name
            VStack(alignment: .leading, spacing: 4) {
                Text("Series Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(series.name)
                    .font(.body)
                    .textSelection(.enabled)
            }
            
            // Color indicator
            HStack {
                Text("Color:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(series.color)
                    .frame(width: 60, height: 20)
            }
            
            // Filter summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Filters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                FilterSummaryView(filters: series.filters)
            }
            
            // Quick actions
            VStack(alignment: .leading, spacing: 8) {
                Text("Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button {
                    copySeriesToClipboard()
                } label: {
                    Label("Copy Data to Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                
                Button {
                    exportSeriesAsCSV()
                } label: {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private func copySeriesToClipboard() {
        var clipboardData = "Year\tValue\n"
        for point in series.points {
            clipboardData += "\(point.year)\t\(Int(point.value))\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clipboardData, forType: .string)
    }
    
    private func exportSeriesAsCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(series.name.replacingOccurrences(of: " ", with: "_")).csv"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            var csvContent = "Year,Value\n"
            for point in series.points {
                csvContent += "\(point.year),\(point.value)\n"
            }
            
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error exporting CSV: \(error)")
            }
        }
    }
}

// MARK: - Filter Summary View

struct FilterSummaryView: View {
    let filters: FilterConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !filters.years.isEmpty {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .frame(width: 16)
                    Text("Years: \(formatYears(filters.years))")
                        .font(.caption)
                }
            }
            
            if !filters.regions.isEmpty {
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.blue)
                        .frame(width: 16)
                    Text("Regions: \(filters.regions.count)")
                        .font(.caption)
                }
            }
            
            if !filters.mrcs.isEmpty {
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.green)
                        .frame(width: 16)
                    Text("MRCs: \(filters.mrcs.count)")
                        .font(.caption)
                }
            }
            
            if !filters.municipalities.isEmpty {
                HStack {
                    Image(systemName: "house.fill")
                        .foregroundColor(.orange)
                        .frame(width: 16)
                    Text("Municipalities: \(filters.municipalities.count)")
                        .font(.caption)
                }
            }
            
            if !filters.vehicleClassifications.isEmpty {
                HStack {
                    Image(systemName: "car")
                        .foregroundColor(.purple)
                        .frame(width: 16)
                    Text("Vehicle Types: \(filters.vehicleClassifications.count)")
                        .font(.caption)
                }
            }
            
            if !filters.fuelTypes.isEmpty {
                HStack {
                    Image(systemName: "fuelpump")
                        .foregroundColor(.red)
                        .frame(width: 16)
                    Text("Fuel Types: \(filters.fuelTypes.count)")
                        .font(.caption)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func formatYears(_ years: Set<Int>) -> String {
        let sorted = years.sorted()
        if sorted.count <= 3 {
            return sorted.map(String.init).joined(separator: ", ")
        } else {
            return "\(sorted.first!)–\(sorted.last!)"
        }
    }
}

// MARK: - Series Data View

struct SeriesDataView: View {
    let series: FilteredDataSeries
    @State private var sortOrder: SortOrder = .yearAscending
    
    enum SortOrder {
        case yearAscending, yearDescending
        case valueAscending, valueDescending
    }
    
    var sortedPoints: [TimeSeriesPoint] {
        switch sortOrder {
        case .yearAscending:
            return series.points.sorted { $0.year < $1.year }
        case .yearDescending:
            return series.points.sorted { $0.year > $1.year }
        case .valueAscending:
            return series.points.sorted { $0.value < $1.value }
        case .valueDescending:
            return series.points.sorted { $0.value > $1.value }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sort controls
            HStack {
                Text("Sort by:")
                    .font(.caption)
                
                Menu {
                    Button("Year ↑") { sortOrder = .yearAscending }
                    Button("Year ↓") { sortOrder = .yearDescending }
                    Button("Value ↑") { sortOrder = .valueAscending }
                    Button("Value ↓") { sortOrder = .valueDescending }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
            }
            
            // Data table
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Year")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Value")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                
                Divider()
                
                // Data rows
                ForEach(sortedPoints) { point in
                    HStack {
                        Text(String(point.year))
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(formatNumber(point.value))
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    
                    Divider()
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
}

// MARK: - Series Statistics View

struct SeriesStatisticsView: View {
    let series: FilteredDataSeries
    
    var statistics: Statistics {
        calculateStatistics()
    }
    
    struct Statistics {
        let count: Int
        let sum: Double
        let mean: Double
        let median: Double
        let min: Double
        let max: Double
        let standardDeviation: Double
        let growthRate: Double?  // Compound annual growth rate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatisticRow(label: "Data Points", value: String(statistics.count))
            StatisticRow(label: "Total", value: formatNumber(statistics.sum))
            StatisticRow(label: "Mean", value: formatNumber(statistics.mean))
            StatisticRow(label: "Median", value: formatNumber(statistics.median))
            StatisticRow(label: "Minimum", value: formatNumber(statistics.min))
            StatisticRow(label: "Maximum", value: formatNumber(statistics.max))
            StatisticRow(label: "Std. Deviation", value: formatNumber(statistics.standardDeviation))
            
            if let growthRate = statistics.growthRate {
                StatisticRow(
                    label: "CAGR",
                    value: formatPercentage(growthRate),
                    help: "Compound Annual Growth Rate"
                )
            }
            
            // Trend analysis placeholder
            Divider()
            
            Text("Trend Analysis")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Future: Polynomial fitting will be implemented here")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
        }
    }
    
    private func calculateStatistics() -> Statistics {
        let values = series.points.map { $0.value }
        let count = values.count
        let sum = values.reduce(0, +)
        let mean = count > 0 ? sum / Double(count) : 0
        
        // Median
        let sortedValues = values.sorted()
        let median: Double
        if count % 2 == 0 && count > 0 {
            median = (sortedValues[count/2 - 1] + sortedValues[count/2]) / 2
        } else if count > 0 {
            median = sortedValues[count/2]
        } else {
            median = 0
        }
        
        // Min/Max
        let min = values.min() ?? 0
        let max = values.max() ?? 0
        
        // Standard deviation
        let variance = values.reduce(0) { total, value in
            total + pow(value - mean, 2)
        } / Double(count > 1 ? count - 1 : 1)
        let standardDeviation = sqrt(variance)
        
        // CAGR (if we have at least 2 years of data)
        let growthRate: Double?
        if let firstPoint = series.points.first,
           let lastPoint = series.points.last,
           firstPoint.year != lastPoint.year && firstPoint.value > 0 {
            let years = Double(lastPoint.year - firstPoint.year)
            growthRate = pow(lastPoint.value / firstPoint.value, 1.0 / years) - 1.0
        } else {
            growthRate = nil
        }
        
        return Statistics(
            count: count,
            sum: sum,
            mean: mean,
            median: median,
            min: min,
            max: max,
            standardDeviation: standardDeviation,
            growthRate: growthRate
        )
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value < 100 ? 2 : 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    
    private func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value * 100)%"
    }
}

// MARK: - Statistic Row

struct StatisticRow: View {
    let label: String
    let value: String
    var help: String? = nil
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let help = help {
                    Image(systemName: "questionmark.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .help(help)
                }
            }
            
            Spacer()
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Export Menu

struct ExportMenu: View {
    let chartData: [FilteredDataSeries]
    
    var body: some View {
        Menu {
            Button {
                exportChartAsPNG()
            } label: {
                Label("Export Chart as PNG", systemImage: "photo")
            }
            
            Button {
                exportDataAsCSV()
            } label: {
                Label("Export Data as CSV", systemImage: "tablecells")
            }
            
            Divider()
            
            // Sharing submenu
            Menu("Share") {
                Button {
                    shareToPhotos()
                } label: {
                    Label("Save to Photos", systemImage: "photo.on.rectangle")
                }
                
                Button {
                    shareViaEmail()
                } label: {
                    Label("Mail", systemImage: "envelope")
                }
                
                Button {
                    shareViaMessages()
                } label: {
                    Label("Messages", systemImage: "message")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .help("Export or share")
    }
    
    private func exportChartAsPNG() {
        // Create a save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "saaq_chart_\(Date().timeIntervalSince1970).png"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Note: This creates a basic export. For a full chart export,
            // the ChartView should handle the export directly since it has
            // access to the actual chart content.
            print("PNG export requested to: \(url.path)")
            print("💡 Tip: Use the Export button in the Chart panel for full chart export functionality")
        }
    }
    
    private func exportDataAsCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "saaq_export_\(Date().timeIntervalSince1970).csv"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // Create comprehensive CSV with all series
            var csvContent = "Series,Year,Value\n"
            
            for series in chartData {
                for point in series.points {
                    csvContent += "\"\(series.name)\",\(point.year),\(point.value)\n"
                }
            }
            
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error exporting CSV: \(error)")
            }
        }
    }
    
    private func shareToPhotos() {
        // Would need to implement image capture and Photos framework integration
        print("Share to Photos")
    }
    
    private func shareViaEmail() {
        // Use NSSharingService for email
        print("Share via Email")
    }
    
    private func shareViaMessages() {
        // Use NSSharingService for Messages
        print("Share via Messages")
    }
}
