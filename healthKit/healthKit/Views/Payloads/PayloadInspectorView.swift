import SwiftUI

/// Tab 3: Inspect the last-sent NDJSON payload per record type.
/// Terminal-aesthetic dark viewer for demo verification.
struct PayloadInspectorView: View {
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @StateObject private var viewModel: PayloadInspectorViewModel
    @State private var showCopiedToast = false
    @State private var isVisible = false
    
    init() {
        // Create with a temporary SyncLedger - will be replaced in task
        _viewModel = StateObject(wrappedValue: PayloadInspectorViewModel(syncLedger: SyncLedger()))
    }

    var body: some View {
        NavigationStack {
            payloadInspectorContent(viewModel: viewModel)
                .task {
                    // Replace the dummy syncLedger with the real one
                    viewModel.syncLedger = syncCoordinator.syncLedger
                    await viewModel.loadPayload()
                }
        }
    }
    
    @ViewBuilder
    private func payloadInspectorContent(viewModel: PayloadInspectorViewModel) -> some View {
        VStack(spacing: 0) {
            categoryPicker(viewModel: viewModel)
                .padding()

            if let payload = viewModel.lastPayload {
                metadataBanner(payload)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                ndjsonViewer(viewModel: viewModel)
            } else {
                emptyState
            }
        }
        .id(viewModel.selectedRecordType) // Force view refresh when selection changes
        .background(DBXColors.dbxLightGray)
        .navigationTitle("Payloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.loadPayload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                    Button {
                        viewModel.copyPayloadToClipboard()
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedToast = false
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(viewModel.lastPayload == nil)
                }
            }
        }
        .overlay(alignment: .top) {
            if showCopiedToast {
                copiedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .refreshable {
            await viewModel.loadPayload()
        }
        .onAppear {
            isVisible = true
            Task { await viewModel.loadPayload() }
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: syncCoordinator.lastSyncDate) { _, _ in
            // Reload payload whenever a sync completes
            if isVisible {
                Task { await viewModel.loadPayload() }
            }
        }
    }

    // MARK: - Category Picker

    private func categoryPicker(viewModel: PayloadInspectorViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PayloadInspectorViewModel.recordTypes, id: \.self) { type in
                    categoryButton(for: type, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func categoryButton(for type: String, viewModel: PayloadInspectorViewModel) -> some View {
        let isSelected = viewModel.selectedRecordType == type
        let hasData = viewModel.hasPayload(for: type)
        
        return Button {
            print("🔘 Tapped button for: \(type)")
            print("   Current selected: \(viewModel.selectedRecordType)")
            print("   Has data: \(hasData)")
            viewModel.selectedRecordType = type
            print("   New selected: \(viewModel.selectedRecordType)")
            Task { 
                await viewModel.loadPayload()
                print("   Payload loaded for: \(type)")
            }
        } label: {
            HStack(spacing: 6) {
                Text(displayName(for: type))
                    .font(.system(size: 13, weight: .medium))
                
                // Show badge if this type has data
                if hasData {
                    Circle()
                        .fill(isSelected ? .white : DBXColors.dbxGreen)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? DBXColors.dbxRed : DBXColors.dbxCardBackground
            )
            .foregroundStyle(
                isSelected ? .white : .primary
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metadata Banner

    private func metadataBanner(_ payload: SyncRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(payload.recordCount) records", systemImage: "doc.text")
                Spacer()
                Label("HTTP \(payload.httpStatusCode)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DBXColors.dbxGreen)
            }
            .font(.caption)

            Text(payload.timestamp, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
            + Text(" at ")
                .font(.caption2)
                .foregroundStyle(.secondary)
            + Text(payload.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Show key headers
            let keyHeaders = ["X-Record-Type", "X-Device-Id", "X-Platform", "X-App-Version"]
            ForEach(keyHeaders, id: \.self) { key in
                if let value = payload.requestHeaders[key] {
                    HStack(spacing: 4) {
                        Text(key + ":")
                            .font(DBXTypography.monoSmall)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(DBXTypography.monoSmall)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .dbxCard()
    }

    // MARK: - NDJSON Viewer

    private func ndjsonViewer(viewModel: PayloadInspectorViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.parsedLines) { line in
                    NDJSONLineView(line: line)
                    if line.id != viewModel.parsedLines.last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.1))
                    }
                }
            }
            .padding()
        }
        .background(DBXColors.dbxNavy)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No data sent yet")
                .font(.headline)
            Text("Tap Sync on the Dashboard to send HealthKit data to Databricks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Toast

    private var copiedToast: some View {
        Text("NDJSON copied to clipboard")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DBXColors.dbxDarkTeal)
            .clipShape(Capsule())
            .padding(.top, 8)
    }

    // MARK: - Helpers

    private func displayName(for type: String) -> String {
        switch type {
        case "samples": return "Samples"
        case "workouts": return "Workouts"
        case "sleep": return "Sleep"
        case "activity_summaries": return "Activity"
        case "deletes": return "Deletes"
        default: return type
        }
    }
}
