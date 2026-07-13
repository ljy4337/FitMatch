import SwiftUI

struct ProductSizeSelectionGrid: View {
    let sizes: [ProductSize]
    @Binding var selectedSizeID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rowStartIndices, id: \.self) { rowStartIndex in
                HStack(spacing: 12) {
                    sizeButton(options[rowStartIndex])

                    if rowStartIndex + 1 < options.count {
                        sizeButton(options[rowStartIndex + 1])
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                    }
                }
            }
        }
    }

    private var rowStartIndices: [Int] {
        Array(stride(from: 0, to: options.count, by: 2))
    }

    private var options: [ProductSizeSelectionOption] {
        ParsedProductSizeNormalizer.uniqueProductSizes(sizes).map { size in
            ProductSizeSelectionOption(
                id: size.id,
                name: size.name,
                displayName: size.name.fitMatchDisplaySizeName
            )
        }
    }

    private func sizeButton(_ option: ProductSizeSelectionOption) -> some View {
        let isSelected = selectedSizeID == option.id

        return Button {
            selectedSizeID = option.id
        } label: {
            HStack(spacing: 8) {
                Text(option.displayName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

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
        .frame(maxWidth: .infinity)
    }
}

private struct ProductSizeSelectionOption: Identifiable {
    let id: UUID
    let name: String
    let displayName: String
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
