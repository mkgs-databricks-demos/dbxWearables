import SwiftUI

#if DEBUG

/// Displays integration test results in a detailed view
struct TestResultsView: View {
    let results: [TestResult]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary Header
                    summaryCard
                    
                    // Individual Test Results
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        testResultCard(result, index: index + 1)
                    }
                }
                .padding()
            }
            .background(DBXColors.dbxLightGray)
            .navigationTitle("Test Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var summaryCard: some View {
        let passed = results.filter { $0.success }.count
        let failed = results.count - passed
        let totalDuration = results.map { $0.duration }.reduce(0, +)
        
        return VStack(spacing: 12) {
            HStack {
                Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(failed == 0 ? DBXColors.dbxGreen : DBXColors.dbxYellow)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(failed == 0 ? "All Tests Passed!" : "\(failed) Test(s) Failed")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(passed)/\(results.count) passed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f seconds", totalDuration))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Tests Run")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(results.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .background(DBXColors.dbxCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func testResultCard(_ result: TestResult, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("#\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DBXColors.dbxRed)
                    .clipShape(Capsule())
                
                Text(result.scenarioName)
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? DBXColors.dbxGreen : .red)
            }
            
            // Duration
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f seconds", result.duration))
                    .font(.subheadline)
                    .monospacedDigit()
            }
            
            Divider()
            
            // Configuration
            VStack(alignment: .leading, spacing: 6) {
                Text("Configuration")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DBXColors.dbxRed)
                    .textCase(.uppercase)
                
                configRow(icon: "calendar", label: "Days", value: "\(result.config.daysToGenerate)")
                configRow(icon: "figure.walk", label: "Fitness", value: result.config.fitnessLevel.displayName)
                configRow(icon: "checkmark.circle", label: "Workouts", value: result.config.includeWorkouts ? "Yes" : "No")
                configRow(icon: "bed.double", label: "Sleep Stages", value: result.config.includeSleepStages ? "Yes" : "No")
            }
            
            Divider()
            
            // Records Synced
            VStack(alignment: .leading, spacing: 6) {
                Text("Records Synced")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DBXColors.dbxRed)
                    .textCase(.uppercase)
                
                ForEach(result.recordsSynced.sorted(by: { $0.key < $1.key }), id: \.key) { type, count in
                    if count > 0 {
                        HStack {
                            Text(type.capitalized)
                                .font(.subheadline)
                            Spacer()
                            Text("\(count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
                
                if result.deletionCount > 0 {
                    HStack {
                        Text("Deletions")
                            .font(.subheadline)
                        Spacer()
                        Text("\(result.deletionCount)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(DBXColors.dbxYellow)
                            .monospacedDigit()
                    }
                }
            }
            
            // Validation Notes
            if !result.notes.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Validation")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DBXColors.dbxRed)
                        .textCase(.uppercase)
                    
                    Text(result.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(DBXColors.dbxCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func configRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#endif
