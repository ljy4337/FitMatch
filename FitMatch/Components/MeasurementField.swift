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
    var category: ClothingCategory = .top
    var detailCategory: ClosetDetailCategory = .other
    var gender: UserGender = .unisex

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { kind in
                        summaryItem(kind.title, measurements.value(for: kind))
                    }
                    ForEach(0..<max(0, columnCount - row.count), id: \.self) { _ in
                        Color.clear
                    }
                }
            }
        }
        .font(.subheadline)
    }

    private var rows: [[MeasurementKind]] {
        if category.serviceGroup == .bottom {
            return stride(from: 0, to: bottomKinds.count, by: 3).map {
                Array(bottomKinds[$0..<min($0 + 3, bottomKinds.count)])
            }
        }

        let visibleKinds = measurementKinds.filter {
            measurements.value(for: $0) > 0
        }
        let kinds = visibleKinds.isEmpty ? measurementKinds : visibleKinds
        return stride(from: 0, to: kinds.count, by: 2).map {
            Array(kinds[$0..<min($0 + 2, kinds.count)])
        }
    }

    private var columnCount: Int {
        category.serviceGroup == .bottom ? 3 : 2
    }

    private var bottomKinds: [MeasurementKind] {
        [.totalLength, .waist, .hip, .thigh, .rise, .hem]
    }

    private var measurementKinds: [MeasurementKind] {
        category.measurementKinds(detailCategory: detailCategory, gender: gender)
    }

    private func summaryItem(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value > 0 ? value.cmText : "-")
                .fontWeight(.medium)
        }
    }
}

extension Double {
    var cmText: String {
        String(format: "%.1fcm", self)
    }
}
