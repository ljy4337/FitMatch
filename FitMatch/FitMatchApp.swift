//
//  FitMatchApp.swift
//  FitMatch
//
//  Created by 이진영 on 7/3/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct FitMatchApp: App {
    private let modelContainer: ModelContainer?
    private let modelContainerError: Error?

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-fitmatchUITesting") {
            UIView.setAnimationsEnabled(false)
        }
        if arguments.contains("-fitmatchResetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "FitMatch.hasCompletedOnboarding")
        }
        #endif

        do {
            let schema = Schema(FitMatchSchemaV1.models)
            let container: ModelContainer
            #if DEBUG
            if let persistentStoreName = Self.argumentValue(
                after: "-fitmatchUITestingPersistentStore",
                in: arguments
            ) {
                let supportDirectory = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let safeStoreName = persistentStoreName
                    .replacingOccurrences(of: "/", with: "-")
                let configuration = ModelConfiguration(
                    schema: schema,
                    url: supportDirectory.appendingPathComponent("\(safeStoreName).store")
                )
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: FitMatchSchemaMigrationPlan.self,
                    configurations: [configuration]
                )
            } else if arguments.contains("-fitmatchUITesting") {
                let configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: FitMatchSchemaMigrationPlan.self,
                    configurations: [configuration]
                )
            } else {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: FitMatchSchemaMigrationPlan.self
                )
            }
            #else
            container = try ModelContainer(
                for: schema,
                migrationPlan: FitMatchSchemaMigrationPlan.self
            )
            #endif
            #if DEBUG
            if arguments.contains("-fitmatchUITestSeedExistingData") {
                try Self.seedExistingUserData(in: container)
                UserDefaults.standard.set(true, forKey: "FitMatch.hasCompletedOnboarding")
            }
            #endif
            modelContainer = container
            modelContainerError = nil
        } catch {
            modelContainer = nil
            modelContainerError = error
            #if DEBUG
            print("[FitMatch] model container creation failed: \(error.localizedDescription)")
            #endif
        }
    }

    #if DEBUG
    private static func argumentValue(after key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    @MainActor
    private static func seedExistingUserData(in container: ModelContainer) throws {
        let context = container.mainContext
        guard try context.fetchCount(FetchDescriptor<UserFit>()) == 0 else { return }

        let brand = Brand(name: "기존 브랜드")
        let measurements = GarmentMeasurements(
            shoulder: 48,
            chest: 54,
            totalLength: 70,
            sleeveLength: 24
        )
        let size = ProductSize(name: "M", measurements: measurements)
        let product = Product(
            name: "기존 비교상품",
            brand: brand,
            category: .top,
            sourceURLString: "https://www.musinsa.com/products/existing-ui-test",
            sourceName: "무신사",
            sizes: [size]
        )
        let item = UserFit(
            sourceName: "직접 입력",
            brandName: "기존 브랜드",
            gender: .unisex,
            productName: "기존 기준옷",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: measurements,
            fitMemo: "업데이트 보존 검증",
            satisfaction: 5,
            isRepresentative: true
        )
        let history = RecommendationHistory(
            product: product,
            recommendedSize: size,
            userFit: item,
            totalDifference: 0,
            measurementDifferences: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 0,
                sleeveLength: 0
            ),
            recommendationScore: 100,
            productDetailCategory: .shortSleeve
        )

        context.insert(brand)
        context.insert(product)
        context.insert(item)
        context.insert(history)
        try context.save()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .modelContainer(modelContainer)
            } else {
                ModelContainerRecoveryView(error: modelContainerError)
            }
        }
    }
}

private struct ModelContainerRecoveryView: View {
    let error: Error?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("저장된 데이터를 불러오지 못했어요")
                .font(.title3.weight(.bold))

            Text("앱을 종료한 뒤 다시 실행해 주세요. 같은 문제가 계속되면 앱을 삭제하지 말고 고객 지원에 문의해 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("진단 코드: DATA-STORE-001")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .accessibilityLabel("진단 코드 DATA STORE 001")
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .contain)
        .onAppear {
            #if DEBUG
            if let error {
                print("[FitMatch] recovery screen presented: \(error.localizedDescription)")
            }
            #endif
        }
    }
}
