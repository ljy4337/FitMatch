import Foundation
import Testing
@testable import FitMatch

@MainActor
struct ManualClosetUXRegressionTests {
    @Test func paddedMeasurementPreservesValidatedValueAndRecord() throws {
        let form = makeForm()
        form.chest = " 50 \n"
        let item = try #require(form.makeUserFit())
        #expect(item.measurements.chest == 50)
        #expect(item.measurementRecords.contains { $0.value == 50 })
    }

    private func makeForm() -> AddClosetItemViewModel {
        let form = AddClosetItemViewModel(
            prefillCategory: .top, prefillDetailCategory: .shortSleeve,
            prefillGender: .men, prefillSourceOption: .manual,
            prefillBrand: "UX regression", prefillProductName: "Manual shirt"
        )
        form.chest = "50"
        return form
    }
}
