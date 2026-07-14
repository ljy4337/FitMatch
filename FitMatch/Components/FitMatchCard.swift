import SwiftUI

struct CardView<Content: View>: View {
    var radius: CGFloat = 22
    var padding: CGFloat = 18
    var background: Color = Color(.systemBackground)
    private let content: Content

    init(
        radius: CGFloat = 22,
        padding: CGFloat = 18,
        background: Color = Color(.systemBackground),
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.background = background
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 16, x: 0, y: 8)
    }
}

struct FitMatchCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        CardView(radius: 20, padding: 18) {
            content
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.body)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateActionButton: View {
    let title: String
    var systemImage: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 156, height: 46)
                .background(Color.primary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FitMatchNavigationTitle: View {
    var body: some View {
        Image("FitMatchWordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(width: 148, height: 34)
            .accessibilityLabel("FitMatch")
    }
}

struct FitMatchNavigationHeader: View {
    var onLogout: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FitMatchNavigationTitle()

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                NavigationLink {
                    GlobalSearchView()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color(.systemBackground), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색")

                NavigationLink {
                    SettingsView(onLogout: onLogout)
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color(.systemBackground), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("설정")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SmallInfoCard<Content: View>: View {
    let title: String
    let value: String
    var systemImage: String?
    private let content: Content

    init(
        title: String,
        value: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        CardView(radius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }

                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                content
            }
        }
    }
}

struct ProductPriceView: View {
    let product: Product

    var body: some View {
        EmptyView()
    }
}

private extension Product {
    var displayPrice: String? {
        (finalPrice ?? salePrice ?? normalPrice).map(Self.formatPrice)
    }

    var normalPriceTextForDisplay: String? {
        guard let normalPrice,
              let currentPrice = finalPrice ?? salePrice,
              normalPrice > currentPrice else {
            return nil
        }

        return Self.formatPrice(normalPrice)
    }

    var discountText: String? {
        if let discountRate, discountRate > 0 {
            let normalizedRate = discountRate <= 1 ? discountRate * 100 : discountRate
            return "\(Int(normalizedRate.rounded()))% 할인"
        }

        guard let normalPrice,
              let currentPrice = finalPrice ?? salePrice,
              normalPrice > currentPrice else {
            return nil
        }

        let rate = Double(normalPrice - currentPrice) / Double(normalPrice) * 100
        return "\(Int(rate.rounded()))% 할인"
    }

    static func formatPrice(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted)원"
    }
}
