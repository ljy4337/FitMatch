import SwiftData

enum FitMatchSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Brand.self,
            Product.self,
            ProductSize.self,
            UserFit.self,
            RecommendationHistory.self,
            GarmentMeasurementRecord.self
        ]
    }
}

enum FitMatchSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FitMatchSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
