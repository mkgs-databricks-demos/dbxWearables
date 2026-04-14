import Foundation
import HealthKit

/// Maps raw HKQuantitySample and HKCategorySample objects into Codable HealthSample models.
enum HealthSampleMapper {

    // MARK: - Quantity samples

    /// Convert an HKQuantitySample to a HealthSample ready for JSON serialization.
    static func map(_ sample: HKQuantitySample) -> HealthSample {
        let quantityType = sample.quantityType
        let unit = quantityType.canonicalUnit
        let value = sample.quantity.doubleValue(for: unit)

        return HealthSample(
            uuid: sample.uuid.uuidString,
            type: quantityType.identifier,
            value: value,
            unit: unit.unitString,
            startDate: sample.startDate,
            endDate: sample.endDate,
            sourceName: sample.sourceRevision.source.name,
            sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
            metadata: stringMetadata(from: sample.metadata)
        )
    }

    /// Convert a batch of HKSample results (from an anchored query) into HealthSample models,
    /// filtering to only HKQuantitySample instances.
    static func mapQuantitySamples(_ samples: [HKSample]) -> [HealthSample] {
        samples.compactMap { $0 as? HKQuantitySample }.map(map)
    }

    // MARK: - Category samples (appleStandHour, etc.)

    /// Convert an HKCategorySample to a HealthSample.
    /// Category values are integer enums — stored as the numeric value with unit "category".
    static func map(_ sample: HKCategorySample) -> HealthSample {
        HealthSample(
            uuid: sample.uuid.uuidString,
            type: sample.categoryType.identifier,
            value: Double(sample.value),
            unit: "category",
            startDate: sample.startDate,
            endDate: sample.endDate,
            sourceName: sample.sourceRevision.source.name,
            sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
            metadata: stringMetadata(from: sample.metadata)
        )
    }

    /// Convert a batch of HKSample results into HealthSample models,
    /// filtering to only HKCategorySample instances.
    static func mapCategorySamples(_ samples: [HKSample]) -> [HealthSample] {
        samples.compactMap { $0 as? HKCategorySample }.map(map)
    }

    /// Flatten HealthKit metadata values to string key-value pairs.
    /// Metadata values can be String, NSNumber, Date, or other types —
    /// we coerce everything to String for consistent JSON output.
    private static func stringMetadata(from metadata: [String: Any]?) -> [String: String]? {
        guard let metadata, !metadata.isEmpty else { return nil }

        var result: [String: String] = [:]
        for (key, value) in metadata {
            switch value {
            case let string as String:
                result[key] = string
            case let number as NSNumber:
                result[key] = number.stringValue
            case let date as Date:
                result[key] = DateFormatters.iso8601WithTimezone.string(from: date)
            default:
                result[key] = String(describing: value)
            }
        }
        return result.isEmpty ? nil : result
    }
}
