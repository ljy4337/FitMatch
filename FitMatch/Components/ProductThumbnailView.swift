import SwiftUI

struct ProductThumbnailView: View {
    let imageURLString: String?
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
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    @unknown default:
                        placeholder {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            } else {
                placeholder {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
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
}
