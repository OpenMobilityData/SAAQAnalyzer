import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppKit

/// Main chart view for displaying time series data
struct ChartView: View {
    @Binding var dataSeries: [FilteredDataSeries]
    @Binding var selectedSeries: FilteredDataSeries?
    
    // Chart display options
    @State private var showLegend = true
    @State private var showGridLines = true
    @State private var includeZero = true
    @State private var chartType: ChartType = .line
    
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
                        chartContent
                            .frame(minHeight: 400)
                            .padding()
                        
                        // Legend (if enabled)
                        if showLegend && !dataSeries.isEmpty {
                            ChartLegend(
                                series: $dataSeries,
                                selectedSeries: $selectedSeries
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    /// Chart toolbar with display options
    private var chartToolbar: some View {
        HStack {
            // Chart type selector
            Picker("Chart Type", selection: $chartType) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.systemImage)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            
            Spacer()
            
            // Display options
            Toggle(isOn: $showGridLines) {
                Image(systemName: "grid")
            }
            .toggleStyle(.button)
            .help("Toggle grid lines")
            
            Toggle(isOn: $includeZero) {
                Image(systemName: includeZero ? "0.square.fill" : "chart.line.uptrend.xyaxis")
            }
            .toggleStyle(.button)
            .help(includeZero ? "Y-axis starts at zero (click to fit data range)" : "Y-axis fits data range (click to include zero)")
            
            Toggle(isOn: $showLegend) {
                Image(systemName: "list.bullet.rectangle")
            }
            .toggleStyle(.button)
            .help("Toggle legend")
            
            Divider()
                .frame(height: 20)
            
            // Export button
            ExportButton(dataSeries: dataSeries, includeZero: includeZero)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    /// Main chart content
    @ViewBuilder
    private var chartContent: some View {
        Chart(dataSeries, id: \.id) { series in
            ForEach(series.points.sorted { $0.year < $1.year }) { point in
                switch chartType {
                case .line:
                    LineMark(
                        x: .value("Year", point.year),
                        y: .value("Count", point.value),
                        series: .value("Series", series.id.uuidString)
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.linear)
                    
                    PointMark(
                        x: .value("Year", point.year),
                        y: .value("Count", point.value)
                    )
                    .foregroundStyle(series.color)
                    .symbolSize(selectedSeries?.id == series.id ? 100 : 60)
                    
                case .bar:
                    BarMark(
                        x: .value("Year", point.year),
                        y: .value("Count", point.value)
                    )
                    .foregroundStyle(series.color.opacity(
                        selectedSeries?.id == series.id ? 1.0 : 0.7
                    ))
                    
                case .area:
                    AreaMark(
                        x: .value("Year", point.year),
                        y: .value("Count", point.value),
                        series: .value("Series", series.id.uuidString)
                    )
                    .foregroundStyle(series.color.opacity(0.3))
                    
                    LineMark(
                        x: .value("Year", point.year),
                        y: .value("Count", point.value),
                        series: .value("Series", series.id.uuidString)
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.linear)
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
            AxisMarks { _ in
                AxisGridLine()
                    .foregroundStyle(.quaternary)
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartXScale(domain: xAxisDomain())
        .chartYScale(domain: yAxisDomain())
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color(NSColor.controlBackgroundColor))
                .border(Color.secondary.opacity(0.2), width: 1)
        }
    }
    
    /// Calculate X-axis domain based on data range
    private func xAxisDomain() -> ClosedRange<Double> {
        guard !dataSeries.isEmpty else { return 2020...2024 }
        
        let allYears = dataSeries.flatMap { $0.points.map { Double($0.year) } }
        let minYear = allYears.min() ?? 2020
        let maxYear = allYears.max() ?? 2024
        
        // Add small padding (0.5 years) on each side
        return (minYear - 0.5)...(maxYear + 0.5)
    }
    
    /// Calculate Y-axis domain based on data and settings
    private func yAxisDomain() -> ClosedRange<Double> {
        guard !dataSeries.isEmpty else { return 0...100 }
        
        let allValues = dataSeries.flatMap { $0.points.map { $0.value } }
        let minValue = allValues.min() ?? 0
        let maxValue = allValues.max() ?? 100
        
        if includeZero {
            return 0...(maxValue * 1.1)  // Add 10% padding
        } else {
            let range = maxValue - minValue
            return (minValue - range * 0.1)...(maxValue + range * 0.1)
        }
    }

    /// Get symbol for series index
    private func symbolForIndex(_ index: Int) -> BasicChartSymbolShape {
        let symbols: [BasicChartSymbolShape] = [
            .circle, .square, .diamond, .triangle, .pentagon, .plus, .cross
        ]
        return symbols[index % symbols.count]
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
}

// MARK: - Empty Chart View

struct EmptyChartView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Data Series")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Add a data series using the filters on the left")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chart Legend

struct ChartLegend: View {
    @Binding var series: [FilteredDataSeries]
    @Binding var selectedSeries: FilteredDataSeries?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Legend")
                    .font(.headline)
                
                Spacer()
                
                // Clear all button
                if !series.isEmpty {
                    Button {
                        series.removeAll()
                        selectedSeries = nil
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
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
                        Text("\(lastPoint.year): \(Int(lastPoint.value).formatted())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Delete button
                    Button {
                        if selectedSeries?.id == seriesItem.id {
                            selectedSeries = nil
                        }
                        series.removeAll { $0.id == seriesItem.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
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
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Export Button

struct ExportButton: View {
    let dataSeries: [FilteredDataSeries]
    let includeZero: Bool
    @State private var showExportOptions = false
    
    var body: some View {
        Menu {
            Button {
                exportAsPNG()
            } label: {
                Label("Export as PNG", systemImage: "photo")
            }
            
            Button {
                exportAsCSV()
            } label: {
                Label("Export as CSV", systemImage: "tablecells")
            }
            
            // PDF export placeholder for future
            Button {
                // TODO: Implement PDF export
                print("PDF export not yet implemented")
            } label: {
                Label("Export as PDF", systemImage: "doc.richtext")
            }
            .disabled(true)
            
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
    }
    
    /// Export chart as PNG image
    private func exportAsPNG() {
        // Create a save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "saaq_chart_\(Date().timeIntervalSince1970).png"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Build the chart content separately to avoid compiler timeout
            let chartContent: AnyView
            if dataSeries.isEmpty {
                chartContent = AnyView(
                    Text("No data available")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(width: 900, height: 500)
                )
            } else {
                // Simple line chart for export with axis fixes
                let chartView = Chart {
                    ForEach(dataSeries, id: \.id) { series in
                        ForEach(series.points, id: \.year) { point in
                            LineMark(
                                x: .value("Year", point.year),
                                y: .value("Count", point.value)
                            )
                            .foregroundStyle(series.color)
                            .lineStyle(StrokeStyle(lineWidth: 6))
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

            // Build simplified legend for export
            let legendView = Group {
                if dataSeries.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Series")
                            .font(.headline)
                            .foregroundColor(.black)

                        ForEach(Array(dataSeries.enumerated()), id: \.element.id) { index, series in
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

            // Assemble the complete export view
            let exportView = VStack(spacing: 16) {
                Text("SAAQ Vehicle Registration Data")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)

                chartContent

                legendView

                Text("Generated on \(Date().formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .background(Color.white)
            .frame(width: 1000, height: 700)

            // Render using ImageRenderer (macOS 13+)
            if #available(macOS 13.0, *) {
                let renderer = ImageRenderer(content: exportView)
                renderer.scale = 2.0  // High DPI for crisp export

                if let nsImage = renderer.nsImage {
                    // Convert NSImage to PNG data
                    if let tiffData = nsImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) {

                        do {
                            try pngData.write(to: url)
                            print("✅ PNG exported successfully to: \(url.path)")
                            print("📊 Chart rendered with \(dataSeries.count) data series")
                        } catch {
                            print("❌ Error writing PNG file: \(error)")
                        }
                    } else {
                        print("❌ Error converting image to PNG format")
                    }
                } else {
                    print("❌ Error rendering chart to image")
                }
            } else {
                // Fallback for older macOS versions - create basic white image
                print("⚠️ ImageRenderer requires macOS 13.0+, creating basic placeholder")

                let width = 1000
                let height = 700
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

                guard let context = CGContext(data: nil,
                                            width: width,
                                            height: height,
                                            bitsPerComponent: 8,
                                            bytesPerRow: width * 4,
                                            space: colorSpace,
                                            bitmapInfo: bitmapInfo) else {
                    print("❌ Error creating graphics context")
                    return
                }

                // Fill with white background
                context.setFillColor(CGColor.white)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))

                // Create PNG data
                guard let cgImage = context.makeImage() else {
                    print("❌ Error creating image")
                    return
                }

                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

                if let tiffData = nsImage.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {

                    do {
                        try pngData.write(to: url)
                        print("✅ PNG exported to: \(url.path)")
                        print("📄 Note: Placeholder image created (requires macOS 13+ for full chart rendering)")
                    } catch {
                        print("❌ Error writing PNG file: \(error)")
                    }
                } else {
                    print("❌ Error converting image to PNG format")
                }
            }
        }
    }
    
    /// Export data series as CSV
    private func exportAsCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "saaq_data_\(Date().timeIntervalSince1970).csv"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // Create CSV content
            var csvContent = "Series,Year,Value\n"
            
            for series in dataSeries {
                for point in series.points {
                    csvContent += "\"\(series.name)\",\(point.year),\(point.value)\n"
                }
            }
            
            // Write to file
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
                print("CSV exported to: \(url)")
            } catch {
                print("Error exporting CSV: \(error)")
            }
        }
    }
}
