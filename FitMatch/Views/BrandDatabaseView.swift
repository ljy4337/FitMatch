import SwiftUI
import SwiftData

struct BrandDatabaseView: View {
    @Query(sort: \Brand.name) private var brands: [Brand]

    var body: some View {
        List {
            if brands.isEmpty {
                ContentUnavailableView(
                    "브랜드 데이터가 없습니다",
                    systemImage: "tag",
                    description: Text("상품 비교를 진행하면 브랜드와 상품이 저장됩니다.")
                )
            } else {
                ForEach(brands) { brand in
                    Section {
                        ForEach(brand.products.sorted { $0.name < $1.name }) { product in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(product.name)
                                    .font(.headline)
                                Text("\(product.category.rawValue) / \(product.sizes.count)개 사이즈")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(brand.name)
                    }
                }
            }
        }
        .navigationTitle("브랜드 DB")
        .hidesTabBarOnScroll()
    }
}
