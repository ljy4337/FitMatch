//
//  FitMatchApp.swift
//  FitMatch
//
//  Created by 이진영 on 7/3/26.
//

import SwiftUI
import SwiftData

@main
struct FitMatchApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Schema(FitMatchSchemaV1.models),
                migrationPlan: FitMatchSchemaMigrationPlan.self
            )
        } catch {
            fatalError("Failed to create FitMatch model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
