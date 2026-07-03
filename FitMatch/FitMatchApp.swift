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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            ClosetItem.self,
            BaselineFit.self,
            ShoppingProduct.self,
            ClothingSize.self,
            RecommendationRecord.self
        ])
    }
}
