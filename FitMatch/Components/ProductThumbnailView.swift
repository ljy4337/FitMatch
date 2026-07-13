import SwiftUI

struct ProductThumbnailView: View {
    let imageURLString: String?
    var category: ClothingCategory? = nil
    var width: CGFloat = 80
    var height: CGFloat = 96
    var cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder {
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder {
                            placeholderIcon
                        }
                    @unknown default:
                        placeholder {
                            placeholderIcon
                        }
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            } else {
                placeholder {
                    placeholderIcon
                }
            }
        }
        .frame(width: width, height: height)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var imageURL: URL? {
        guard let imageURLString = imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !imageURLString.isEmpty else {
            return nil
        }

        return URL(string: imageURLString)
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay {
                content()
            }
    }

    private var placeholderIcon: some View {
        Image(systemName: placeholderSystemImage)
            .font(.system(size: min(width, height) * 0.28, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var placeholderSystemImage: String {
        switch category?.serviceGroup {
        case .top, .shirt, .knit:
            return "tshirt"
        case .bottom, .pants:
            return "figure.walk"
        case .outer:
            return "person.crop.rectangle"
        case .dress:
            return "figure.dress.line.vertical.figure"
        case .underwear:
            return "rectangle.roundedtop"
        case .shoes:
            return "shoeprints.fill"
        case .accessory:
            return "watch.analog"
        case .other, nil:
            return "photo"
        }
    }
}
