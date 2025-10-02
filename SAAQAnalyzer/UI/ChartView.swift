import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppKit  // FIXME: Remove AppKit dependency - only used for NSPasteboard clipboard access

/// Main chart view for displaying time series data
struct ChartView: View {
    @Binding var dataSeries: [FilteredDataSeries]
    @Binding var selectedSeries: FilteredDataSeries?

    // Chart display options
    @State private var showLegend = true
    @State private var showGridLines = true
    @State private var includeZero = true
    @State private var chartType: ChartType = .line
    @State private var chartRefreshTrigger = false

    enum ChartType: String, CaseIterable {
        case line = "Line"
        case bar = "Bar"
        case area = "Area"
        
        var systemImage: String {
            switch self {
            case .line: return "chart.line.uptrend.xyaxis"
            case .bar: return "chart.bar"
            case .area: return "chart.line.uptrend.xyaxis.circle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            chartToolbar
            
            Divider()
            
            // Chart area
            if dataSeries.isEmpty {
                EmptyChartView()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Main chart
                        chartContentView
                            .frame(minHeight: 400)
                            .padding(.leading, 16)
                            .padding(.trailing, 40)  // Extra padding for Y-axis labels
                            .padding(.vertical, 16)
                            .id(chartRefreshTrigger)
                        
                        // Legend (if enabled)
                        if showLegend && !dataSeries.isEmpty {
                            ChartLegend(
                                series: $dataSeries,
                                selectedSeries: $selectedSeries,
                                chartRefreshTrigger: $chartRefreshTrigger
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .scrollIndicators(.visible, axes: .vertical)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 0))
    }
    
    /// Chart toolbar with display options
    private var chartToolbar: some View {
        HStack {
            // Chart type selector
            Picker("Chart Type", selection: $chartType) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            
            Spacer()
            
            // Display options
            Toggle(isOn: $showGridLines) {
                Image(systemName: "grid")
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.button)
            .help("Toggle grid lines")

            Toggle(isOn: $includeZero) {
                Image(systemName: includeZero ? "0.square.fill" : "chart.line.uptrend.xyaxis")
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.button)
            .help(includeZero ? "Y-axis starts at zero (click to fit data range)" : "Y-axis fits data range (click to include zero)")

            Toggle(isOn: $showLegend) {
                Image(systemName: "list.bullet.rectangle")
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.button)
            .help("Toggle legend")
            
            Divider()
                .frame(height: 20)

            // Export button
            Menu {
                Button {
                    exportCurrentViewAsPNG()
                } label: {
                    Label("Copy Current View as PNG", systemImage: "photo")
                        .symbolRenderingMode(.hierarchical)
                }

                Button {
                    exportForPublicationAsPNG()
                } label: {
                    Label("Copy Publication PNG", systemImage: "doc.richtext")
                        .symbolRenderingMode(.hierarchical)
                }

                Button {
                    exportAsCSV()
                } label: {
                    Label("Copy Data as CSV", systemImage: "tablecells")
                        .symbolRenderingMode(.hierarchical)
                }
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                    .symbolRenderingMode(.hierarchical)
            }
            .menuStyle(.button)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    /// Main chart content
    private var chartContent: AnyView {
        AnyView(chartContentView)
    }

    /// Main chart content view
    @ViewBuilder
    private var chartContentView: some View {
        Chart {
            ForEach(dataSeries.filter { $0.isVisible }, id: \.id) { series in
                ForEach(series.points.sorted { $0.year < $1.year }) { point in
                    switch chartType {
                    case .line:
                        LineMark(
                            x: .value("Year", point.year),
                            y: .value(series.yAxisLabel, point.value),
                            series: .value("Series", series.name)
                        )
                        .foregroundStyle(series.color)
                        .interpolationMethod(.linear)

                        PointMark(
                            x: .value("Year", point.year),
                            y: .value(series.yAxisLabel, point.value)
                        )
                        .foregroundStyle(series.color)
                        .symbolSize(selectedSeries?.id == series.id ? 100 : 60)

                    case .bar:
                        BarMark(
                            x: .value("Year", point.year),
                            y: .value(series.yAxisLabel, point.value)
                        )
                        .foregroundStyle(series.color.opacity(
                            selectedSeries?.id == series.id ? 1.0 : 0.7
                        ))
                        .position(by: .value("Series", series.name))

                    case .area:
                        AreaMark(
                            x: .value("Year", point.year),
                            y: .value(series.yAxisLabel, point.value),
                            series: .value("Series", series.name)
                        )
                        .foregroundStyle(series.color.opacity(0.3))

                        LineMark(
                            x: .value("Year", point.year),
                            y: .value(series.yAxisLabel, point.value),
                            series: .value("Series", series.name)
                        )
                        .foregroundStyle(series.color)
                        .interpolationMethod(.linear)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                    .foregroundStyle(.quaternary)
                AxisTick()
                AxisValueLabel {
                    if let year = value.as(Double.self) {
                        Text(String(format: "%.0f", year))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                    .foregroundStyle(.quaternary)
                AxisTick()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(formatYAxisValue(val))
                    }
                }
            }
        }
        .chartXScale(domain: xAxisDomain())
        .chartYScale(domain: chartType == .line ? yAxisDomain() : yAxisDomainForBarArea())
        .chartPlotStyle { plotArea in
            plotArea
                .background(.ultraThinMaterial.opacity(0.5))
                .border(Color.secondary.opacity(0.2), width: 1)
        }
    }
    
    /// Calculate X-axis domain based on data range
    private func xAxisDomain() -> ClosedRange<Double> {
        let visibleSeries = dataSeries.filter { $0.isVisible }
        guard !visibleSeries.isEmpty else { return 2020...2024 }

        let allYears = visibleSeries.flatMap { $0.points.map { Double($0.year) } }
        let minYear = allYears.min() ?? 2020
        let maxYear = allYears.max() ?? 2024
        
        // Add small padding (0.5 years) on each side
        return (minYear - 0.5)...(maxYear + 0.5)
    }
    
    /// Calculate Y-axis domain based on data and settings
    private func yAxisDomain() -> ClosedRange<Double> {
        let visibleSeries = dataSeries.filter { $0.isVisible }
        guard !visibleSeries.isEmpty else { return 0...100 }

        let allValues = visibleSeries.flatMap { $0.points.map { $0.value } }
        let minValue = allValues.min() ?? 0
        let maxValue = allValues.max() ?? 100

        if includeZero {
            return 0...(maxValue * 1.1)  // Add 10% padding
        } else {
            let range = maxValue - minValue
            return (minValue - range * 0.1)...(maxValue + range * 0.1)
        }
    }

    /// Calculate Y-axis domain for bar and area charts (always includes zero)
    private func yAxisDomainForBarArea() -> ClosedRange<Double> {
        let visibleSeries = dataSeries.filter { $0.isVisible }
        guard !visibleSeries.isEmpty else { return 0...100 }

        let allValues = visibleSeries.flatMap { $0.points.map { $0.value } }
        let maxValue = allValues.max() ?? 100

        // Bar and area charts always start from zero
        return 0...(maxValue * 1.1)  // Add 10% padding at the top
    }

    /// Get symbol for series index
    private func symbolForIndex(_ index: Int) -> BasicChartSymbolShape {
        let symbols: [BasicChartSymbolShape] = [
            .circle, .square, .diamond, .triangle, .pentagon, .plus, .cross
        ]
        return symbols[index % symbols.count]
    }

    /// Format Y-axis value based on the metric type of visible series
    private func formatYAxisValue(_ value: Double) -> String {
        let visibleSeries = dataSeries.filter { $0.isVisible }
        guard let firstSeries = visibleSeries.first else {
            return String(format: "%.0f", value)
        }

        // Check if all visible series have the same metric type and field
        let allSameMetric = visibleSeries.allSatisfy {
            $0.metricType == firstSeries.metricType && $0.metricField == firstSeries.metricField
        }

        // Only show units if all visible series use the same metric and field
        let showUnits = allSameMetric

        switch firstSeries.metricType {
        case .count:
            // Format as integer for counts
            if value >= 1_000_000 {
                return String(format: "%.1fM", value / 1_000_000)
            } else if value >= 1_000 {
                return String(format: "%.0fK", value / 1_000)
            } else {
                return String(format: "%.0f", value)
            }

        case .sum:
            if showUnits && firstSeries.metricField == .netMass {
                // Convert to tonnes for large mass values with units
                if value >= 1_000_000 {
                    return String(format: "%.0fKt", value / 1_000_000)
                } else if value >= 1_000 {
                    return String(format: "%.0ft", value / 1_000)
                } else {
                    return String(format: "%.0fkg", value)
                }
            } else {
                // Generic sum formatting without units (mixed series) or for non-mass fields
                if value >= 1_000_000 {
                    return String(format: "%.1fM", value / 1_000_000)
                } else if value >= 1_000 {
                    return String(format: "%.0fK", value / 1_000)
                } else {
                    return String(format: "%.0f", value)
                }
            }

        case .average, .minimum, .maximum:
            // Show one decimal place for averages/min/max with conditional units
            if showUnits, let unit = firstSeries.metricField.unit {
                return String(format: "%.1f%@", value, unit)
            } else {
                return String(format: "%.1f", value)
            }

        case .percentage:
            // Format as percentage
            return String(format: "%.0f%%", value)
        case .coverage:
            // Check if showing percentage or raw count
            if firstSeries.filters.coverageAsPercentage {
                return String(format: "%.0f%%", value)
            } else {
                // Format as integer count
                if value >= 1_000_000 {
                    return String(format: "%.1fM", value / 1_000_000)
                } else if value >= 1_000 {
                    return String(format: "%.0fK", value / 1_000)
                } else {
                    return String(format: "%.0f", value)
                }
            }
        }
    }
    
    /// Handle hover interaction
    private func handleHover(phase: HoverPhase, geometry: GeometryProxy, chartProxy: ChartProxy) {
        switch phase {
        case .active(_):
            // Hover functionality could be implemented here in the future
            break

            // Find closest data point
            // This would require more complex calculation based on chart scaling
            // For now, we'll leave it as a placeholder for hover tooltips

        case .ended:
            // Clear any hover state
            break
        }
    }

    // MARK: - Export Functions

    /// Export current view exactly as displayed in UI
    private func exportCurrentViewAsPNG() {
        print("📸 Export Current View as PNG button clicked")
        let darkBackground = Color(red: 0.1, green: 0.1, blue: 0.1)

        let contentView = VStack(spacing: 16) {
            if dataSeries.isEmpty {
                EmptyChartView()
                    .frame(height: 400)
            } else {
                chartContent
                    .frame(height: 400)
                    .padding()

                if showLegend && !dataSeries.isEmpty {
                    ChartLegend(
                        series: .constant(dataSeries),
                        selectedSeries: .constant(nil),
                        chartRefreshTrigger: .constant(false)
                    )
                    .padding(.horizontal)
                }
            }
        }
        .frame(width: 900, height: 700)
        .background(darkBackground)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)

        let renderer = ImageRenderer(content: contentView)
        renderer.scale = AppSettings.shared.exportScaleFactor

        if let cgImage = renderer.cgImage {
            print("✅ Successfully rendered CGImage")
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
                print("❌ Error creating image destination")
                return
            }

            CGImageDestinationAddImage(destination, cgImage, nil)

            if CGImageDestinationFinalize(destination) {
                print("✅ PNG data created, size: \(mutableData.length) bytes")

                // FIXME: Replace NSPasteboard with pure SwiftUI when available
                // Copy PNG to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(mutableData as Data, forType: .png)

                print("📋 PNG copied to clipboard! (Size: \(mutableData.length) bytes)")
                print("💡 Paste into Preview.app (⌘N) or any image editor to save")
            } else {
                print("❌ Error finalizing PNG export")
            }
        } else {
            print("❌ Error rendering current view to image")
        }
    }

    /// Export chart formatted for publication
    private func exportForPublicationAsPNG() {
        let chartContent: AnyView
        if dataSeries.isEmpty {
            chartContent = AnyView(
                Text("No data available")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 900, height: 500)
            )
        } else {
            let chartView = Chart {
                ForEach(dataSeries.filter { $0.isVisible }, id: \.id) { series in
                    ForEach(series.points, id: \.year) { point in
                        LineMark(
                            x: .value("Year", point.year),
                            y: .value("Count", point.value),
                            series: .value("Series", series.name)
                        )
                        .foregroundStyle(series.color)
                        .lineStyle(StrokeStyle(lineWidth: AppSettings.shared.exportLineThickness))
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let year = value.as(Double.self) {
                            Text(String(format: "%.0f", year))
                                .fontWeight(.bold)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color(red: 0.9, green: 0.9, blue: 0.9))
            }
            .chartXScale(domain: .automatic(includesZero: false))
            .chartYScale(domain: .automatic(includesZero: includeZero))
            .frame(width: 900, height: 500)

            chartContent = AnyView(chartView)
        }

        let legendView = Group {
            if dataSeries.filter({ $0.isVisible }).count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Series")
                        .font(.headline)
                        .foregroundColor(.black)

                    ForEach(Array(dataSeries.filter { $0.isVisible }.enumerated()), id: \.element.id) { index, series in
                        HStack {
                            Rectangle()
                                .fill(series.color)
                                .frame(width: 12, height: 12)
                            Text(series.name)
                                .font(.caption)
                                .foregroundColor(.black)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }

        let exportView = VStack(spacing: 16) {
            Text("SAAQ Vehicle Registration Data")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.black)

            chartContent

            legendView

            Text("Generated on \(Date().formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(Color.white)
        .frame(width: 1000, height: 700)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = AppSettings.shared.exportScaleFactor

        if let cgImage = renderer.cgImage {
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
                print("❌ Error creating image destination")
                return
            }

            CGImageDestinationAddImage(destination, cgImage, nil)

            if CGImageDestinationFinalize(destination) {
                print("✅ Publication PNG created, size: \(mutableData.length) bytes")

                // FIXME: Replace NSPasteboard with pure SwiftUI when available
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(mutableData as Data, forType: .png)

                print("📋 Publication-quality PNG copied to clipboard!")
                print("💡 Paste into Preview.app (⌘N) or any image editor to save")
            } else {
                print("❌ Error finalizing PNG export")
            }
        } else {
            print("❌ Error rendering chart to image")
        }
    }

    /// Export data series as CSV
    private func exportAsCSV() {
        var csvContent = "Series,Year,Value\n"

        for series in dataSeries {
            for point in series.points {
                csvContent += "\"\(series.name)\",\(point.year),\(point.value)\n"
            }
        }

        if let data = csvContent.data(using: .utf8) {
            // FIXME: Replace NSPasteboard with pure SwiftUI when available
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(csvContent, forType: .string)

            print("📋 CSV data copied to clipboard! (\(dataSeries.count) series)")
            print("💡 Paste into Numbers, Excel, or any text editor to save")
        } else {
            print("❌ Error converting CSV to data")
        }
    }
}

// MARK: - Empty Chart View

struct EmptyChartView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("No Data Series")
                .font(.title2.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
            
            Text("Add a data series using the filters on the left")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chart Legend

struct ChartLegend: View {
    @Binding var series: [FilteredDataSeries]
    @Binding var selectedSeries: FilteredDataSeries?
    @Binding var chartRefreshTrigger: Bool
    @State private var refreshTrigger = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Legend")
                    .font(.headline.weight(.medium))
                    .fontDesign(.rounded)

                Spacer()
                
                // Clear all button
                if !series.isEmpty {
                    Button {
                        series.removeAll()
                        selectedSeries = nil
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(.caption)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            
            ForEach(Array(series.enumerated()), id: \.element.id) { index, seriesItem in
                HStack(spacing: 8) {
                    // Color indicator
                    Circle()
                        .fill(seriesItem.color)
                        .frame(width: 12, height: 12)
                    
                    // Series name
                    Text(seriesItem.name)
                        .font(.caption)
                        .foregroundColor(selectedSeries?.id == seriesItem.id ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Data summary
                    if let lastPoint = seriesItem.points.last {
                        Text("\(lastPoint.year.formatted(.number.grouping(.never))): \(Int(lastPoint.value).formatted())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Hide/Show button
                    Button {
                        seriesItem.isVisible.toggle()
                        refreshTrigger.toggle()
                        chartRefreshTrigger.toggle()
                    } label: {
                        Image(systemName: seriesItem.isVisible ? "eye" : "eye.slash")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .help(seriesItem.isVisible ? "Hide this series" : "Show this series")

                    // Delete button
                    Button {
                        if selectedSeries?.id == seriesItem.id {
                            selectedSeries = nil
                        }
                        series.removeAll { $0.id == seriesItem.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this series")
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedSeries?.id == seriesItem.id ?
                              Color.accentColor.opacity(0.1) : Color.clear)
                )
                .onTapGesture {
                    if selectedSeries?.id == seriesItem.id {
                        selectedSeries = nil
                    } else {
                        selectedSeries = seriesItem
                    }
                }
            }
        }
        .padding()
        .id(refreshTrigger)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Exportable Document

/// Document wrapper for file export
struct ExportableDocument: FileDocument, Transferable {
    static var readableContentTypes: [UTType] { [.png, .commaSeparatedText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    // Transferable conformance
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { document in
            document.data
        }
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            document.data
        }
    }
}

// MARK: - View Extension for File Exporters

extension View {
    func withFileExporters(
        showingCurrentViewExporter: Binding<Bool>,
        showingPublicationExporter: Binding<Bool>,
        showingCSVExporter: Binding<Bool>,
        exportData: Data?,
        exportFileName: String,
        onResult: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        self
            .fileExporter(
                isPresented: showingCurrentViewExporter,
                document: ExportableDocument(data: exportData ?? Data()),
                contentType: .png,
                defaultFilename: exportFileName
            ) { result in
                onResult(result)
            }
            .fileExporter(
                isPresented: showingPublicationExporter,
                document: ExportableDocument(data: exportData ?? Data()),
                contentType: .png,
                defaultFilename: exportFileName
            ) { result in
                onResult(result)
            }
            .fileExporter(
                isPresented: showingCSVExporter,
                document: ExportableDocument(data: exportData ?? Data()),
                contentType: .commaSeparatedText,
                defaultFilename: exportFileName
            ) { result in
                onResult(result)
            }
    }
}
