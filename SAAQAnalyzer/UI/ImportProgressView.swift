import SwiftUI

/// Comprehensive import progress indicator with detailed stage information
struct ImportProgressView: View {
    @ObservedObject var progressManager: ImportProgressManager
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Main progress content
            VStack(spacing: 16) {
                // Header with step information
                progressHeader
                
                // Overall progress bar
                overallProgressBar
                
                // Stage-specific details
                stageDetailsSection
                
                // Action buttons
                actionButtons
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .onAppear {
            startProgressAnimation()
        }
    }
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        VStack(spacing: 12) {
            // Batch import indicator (if applicable) - make it very prominent
            if progressManager.isBatchImport {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("Batch Import: File \(progressManager.currentFileIndex + 1) of \(progressManager.totalFiles)")
                            .font(.headline.weight(.medium))
                            .fontDesign(.rounded)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)

                    if !progressManager.currentFileName.isEmpty {
                        HStack {
                            Text("Current file:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(progressManager.currentFileName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                }
            }

            HStack {
                Image(systemName: progressManager.currentStage.systemImage)
                    .foregroundColor(.accentColor)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progressManager.currentStage.title)
                        .font(.headline.weight(.medium))
                        .fontDesign(.rounded)

                    Text(progressManager.currentStage.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Step indicator
                if progressManager.currentStage != .idle {
                    stepIndicator
                }
            }
        }
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 4) {
            Text("Step")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text("\(progressManager.currentStage.stepNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            
            Text("of")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text("\(ImportProgressManager.ImportStage.totalSteps)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Overall Progress Bar
    
    private var overallProgressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Overall Progress")
                    .font(.subheadline.weight(.medium))
                    .fontDesign(.rounded)

                Spacer()
                
                Text("\(Int(progressManager.overallProgress * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundColor(.accentColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressGradient)
                        .frame(width: geometry.size.width * progressManager.overallProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progressManager.overallProgress)
                    
                    // Animated shimmer effect for active progress
                    if progressManager.isImporting {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .clear,
                                        Color.white.opacity(0.3),
                                        .clear
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 60, height: 8)
                            .offset(x: animationOffset)
                            .mask(
                                RoundedRectangle(cornerRadius: 4)
                                    .frame(width: geometry.size.width * progressManager.overallProgress, height: 8)
                            )
                    }
                }
            }
            .frame(height: 8)
        }
    }
    
    private var progressGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.accentColor.opacity(0.8),
                Color.accentColor
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Stage Details
    
    private var stageDetailsSection: some View {
        VStack(spacing: 12) {
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Stage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(progressManager.stageProgress.progressText)
                        .font(.subheadline.weight(.medium))
                        .fontDesign(.rounded)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Stage-specific progress indicator
                stageProgressIndicator
            }
            
            // Detailed progress bar for quantitative stages
            if let stageProgress = progressManager.stageProgress.quantitativeProgress {
                detailedProgressBar(progress: stageProgress)
            }
        }
    }
    
    @ViewBuilder
    private var stageProgressIndicator: some View {
        switch progressManager.currentStage {
        case .idle, .completed:
            Image(systemName: progressManager.currentStage == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(progressManager.currentStage == .completed ? .green : .secondary)
                .font(.title2)
            
        case .reading, .indexing:
            // Indeterminate spinner
            ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
            
        case .parsing, .importing:
            // Percentage indicator
            if let progress = progressManager.stageProgress.quantitativeProgress {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                    
                    Text("\(Int(progress * 100))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
    
    private func detailedProgressBar(progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 4)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: progress)
            }
        }
        .frame(height: 4)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack {
            if progressManager.currentStage == .completed {
                Button("New Import") {
                    progressManager.reset()
                }
                .buttonStyle(.borderedProminent)
            }
            
            if progressManager.isImporting {
                Button("Cancel") {
                    // TODO: Implement cancel functionality
                    progressManager.reset()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Animation
    
    private func startProgressAnimation() {
        withAnimation(Animation.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            animationOffset = 300 // Adjust based on typical progress bar width
        }
    }
}

// MARK: - ImportStage Extensions

extension ImportProgressManager.ImportStage {
    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .reading: return "doc.text"
        case .parsing: return "cpu"
        case .importing: return "cylinder.split.1x2"
        case .indexing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Idle state
        ImportProgressView(progressManager: {
            let manager = ImportProgressManager()
            return manager
        }())
        
        // Parsing state
        ImportProgressView(progressManager: {
            let manager = ImportProgressManager()
            manager.startImport()
            manager.updateToParsing(totalRecords: 1000000, workerCount: 16)
            manager.updateParsingProgress(processedRecords: 450000, workerCount: 16)
            return manager
        }())
        
        // Importing state
        ImportProgressView(progressManager: {
            let manager = ImportProgressManager()
            manager.startImport()
            manager.updateToImporting(totalBatches: 128)
            manager.updateImportingProgress(currentBatch: 64, recordsProcessed: 3200000)
            return manager
        }())
    }
    .padding()
    .frame(width: 500)
}