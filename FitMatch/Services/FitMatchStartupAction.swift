import Foundation
import SwiftData

/// Narrow, non-visual startup orchestration shared by the app bootstrap and
/// headless tests. It owns no product policy: container construction and the
/// legacy migration remain the existing production implementations.
@MainActor
enum FitMatchStartupAction {
    enum ContainerOutcome {
        case ready(ModelContainer)
        case failed(Error)
    }

    enum LegacyMeasurementMigrationOutcome: Equatable {
        case completed
        case failed(message: String)
    }

    static func makeContainer(
        _ build: () throws -> ModelContainer
    ) -> ContainerOutcome {
        do {
            return .ready(try build())
        } catch {
            return .failed(error)
        }
    }

    static func runLegacyMeasurementMigration(
        modelContext: ModelContext,
        products: [Product],
        userFits: [UserFit]
    ) -> LegacyMeasurementMigrationOutcome {
        runLegacyMeasurementMigration(
            modelContext: modelContext,
            products: products,
            userFits: userFits,
            run: { context, products, userFits in
                try MeasurementLegacyBackfillService.run(
                    modelContext: context,
                    products: products,
                    userFits: userFits
                )
            }
        )
    }

    /// The overload is the production-used orchestration with its one testable
    /// side-effect boundary exposed for deterministic startup-failure tests.
    static func runLegacyMeasurementMigration(
        modelContext: ModelContext,
        products: [Product],
        userFits: [UserFit],
        run: (ModelContext, [Product], [UserFit]) throws -> Void
    ) -> LegacyMeasurementMigrationOutcome {
        do {
            try run(modelContext, products, userFits)
            return .completed
        } catch {
            modelContext.rollback()
            return .failed(
                message: "기존 의류 데이터를 업데이트하지 못했어요. 원본 데이터는 삭제되지 않았습니다."
            )
        }
    }
}
