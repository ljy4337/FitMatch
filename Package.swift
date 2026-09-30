// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FitMatchReleaseValidation",
    defaultLocalization: "ko",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.6"),
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.53.0")
    ],
    targets: [
        .executableTarget(
            name: "FitMatchReleaseE2ERunner",
            dependencies: [
                "SwiftSoup",
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: ".",
            exclude: [
                "FitMatch/Services/ScrollPerformanceDiagnostics.swift"
            ],
            sources: [
                "FitMatch/Models",
                "FitMatch/Services",
                "FitMatch/ViewModels/ShoppingProductViewModel.swift",
                "Tools/FitMatchReleaseE2ERunner/main.swift"
            ],
            resources: [
                .copy("FitMatch/CanonicalTaxonomyBundle"),
                .copy("FitMatch/FitMatchTaxonomy.json")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
