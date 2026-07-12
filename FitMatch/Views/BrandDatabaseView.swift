import SwiftUI
import SwiftData

struct BrandDatabaseView: View {
    @Query(sort: \Brand.name) private var brands: [Brand]

    var body: some View {
        ScrollView {
            if brands.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "tag")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, height: 64)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())

                    Text("브랜드 데이터가 없습니다")
                        .font(.headline.weight(.bold))

                    Text("상품 비교를 진행하면 브랜드와 상품이 저장됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(brands) { brand in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(brand.name)
                                    .font(.title3.weight(.bold))
                                Text("\(brand.products.count)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            VStack(spacing: 10) {
                                ForEach(brand.products.sorted { $0.name < $1.name }) { product in
                                    BrandProductCard(product: product)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("브랜드 DB")
        .hidesTabBarOnScroll()
    }
}

private struct BrandProductCard: View {
    let product: Product

    var body: some View {
        CardView(radius: 20, padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                ProductThumbnailView(
                    imageURLString: product.imageURLString,
                    width: 58,
                    height: 72,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(product.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(product.category.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(product.sizes.count)개 사이즈")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }

                Spacer(minLength: 0)
            }
        }
    }
}
