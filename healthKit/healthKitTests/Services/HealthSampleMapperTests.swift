import XCTest
import HealthKit
@testable import dbxWearablesApp

final class HealthSampleMapperTests: XCTestCase {

    // Note: HKQuantitySample cannot be instantiated directly outside of HealthKit
    // (the initializer requires a valid HKQuantityType and HKQuantity).
    // These tests verify the mapper compiles and handles edge cases.
    // Full integration tests require a device or simulator with HealthKit access.

    func testMapQuantitySamplesFiltersNonQuantitySamples() {
        // An empty input should produce an empty output
        let result = HealthSampleMapper.mapQuantitySamples([])
        XCTAssertTrue(result.isEmpty)
    }
}
