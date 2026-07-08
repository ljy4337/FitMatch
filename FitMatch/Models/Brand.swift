import Foundation
import SwiftData

@Model
final class Brand {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var normalizedName: String
    var countryCode: String?
    var websiteURL: String?
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Product.brand)
    var products: [Product]

    init(
        id: UUID = UUID(),
        name: String,
        countryCode: String? = nil,
        websiteURL: String? = nil,
        notes: String = "",
        products: [Product] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.normalizedName = name.normalizedBrandName
        self.countryCode = countryCode
        self.websiteURL = websiteURL
        self.notes = notes
        self.products = products
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension String {
    var normalizedBrandName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
