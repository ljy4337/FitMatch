import SwiftUI

struct ProductSizeSelectionGrid: View {
    let sizes: [ProductSize]
    @Binding var selectedSizeName: String?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
            ForEach(sizes) { size in
                let isSelected = selectedSizeName == size.name

                Button {
                    selectedSizeName = size.name
                } label: {
                    HStack(spacing: 8) {
                        Text(size.name.fitMatchDisplaySizeName)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        isSelected ? Color.black : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color.black : Color(.separator).opacity(0.35), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension String {
    var fitMatchDisplaySizeName: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("/") else {
            return value
        }

        return value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
    }
}
