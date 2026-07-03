import SwiftUI

struct MeasurementField: View {
    let title: String
    let placeholder: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text("cm")
                .foregroundStyle(.secondary)
        }
    }
}

struct MeasurementSummaryView: View {
    let measurements: GarmentMeasurements

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                summaryItem("어깨", measurements.shoulder)
                summaryItem("가슴", measurements.chest)
            }
            GridRow {
                summaryItem("총장", measurements.totalLength)
                summaryItem("소매", measurements.sleeveLength)
            }
        }
        .font(.subheadline)
    }

    private func summaryItem(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.cmText)
                .fontWeight(.medium)
        }
    }
}

extension Double {
    var cmText: String {
        String(format: "%.1fcm", self)
    }
}
