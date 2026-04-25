import UIKit
import OSLog

/// Drives the Payload Inspector tab — shows the last-sent NDJSON payload per record type.
@MainActor
final class PayloadInspectorViewModel: ObservableObject {

    static let recordTypes = ["samples", "workouts", "sleep", "activity_summaries", "deletes"]

    var syncLedger: SyncLedger

    @Published var selectedRecordType = "samples"
    @Published var lastPayload: SyncRecord?
    @Published var parsedLines: [PayloadLine] = []
    @Published var availableTypes: Set<String> = []

    init(syncLedger: SyncLedger) {
        self.syncLedger = syncLedger
    }

    func loadPayload() async {
        Log.ui.info("PayloadInspectorViewModel: loadPayload() called for type: \(self.selectedRecordType)")
        
        lastPayload = await syncLedger.getLastPayload(for: selectedRecordType)
        parsedLines = parseNDJSON(lastPayload?.ndjsonPayload)
        
        // Update available types by checking which ones have payloads
        var types: Set<String> = []
        for recordType in Self.recordTypes {
            if await syncLedger.getLastPayload(for: recordType) != nil {
                types.insert(recordType)
            }
        }
        self.availableTypes = types
        
        Log.ui.info("PayloadInspectorViewModel: Loaded \(self.parsedLines.count) lines, available types: \(types)")
    }
    
    func hasPayload(for type: String) -> Bool {
        availableTypes.contains(type)
    }

    func copyPayloadToClipboard() {
        guard let payload = lastPayload?.ndjsonPayload else { return }
        UIPasteboard.general.string = payload
    }

    // MARK: - NDJSON Parsing

    private func parseNDJSON(_ raw: String?) -> [PayloadLine] {
        guard let raw, !raw.isEmpty else { return [] }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.enumerated().map { index, line in
            let lineStr = String(line)
            let preview = truncatedPreview(lineStr)
            let pretty = prettyPrint(lineStr)
            return PayloadLine(id: index, preview: preview, fullJSON: pretty)
        }
    }

    private func truncatedPreview(_ json: String) -> String {
        if json.count <= 100 {
            return json
        }
        return String(json.prefix(100)) + "..."
    }

    private func prettyPrint(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return result
    }
}

/// A single parsed NDJSON line for display in the Payload Inspector.
struct PayloadLine: Identifiable {
    let id: Int
    let preview: String
    let fullJSON: String
}
