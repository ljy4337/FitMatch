#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/fitmatch-metrics.XXXXXX)"
python3 - "$repo" "$work" <<'PY'
from pathlib import Path
import sys
r,w=map(Path,sys.argv[1:])
a=w/'Sources/FitMatch';b=w/'Tests/FitMatchTests';a.mkdir(parents=True);b.mkdir(parents=True)
(w/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MetricsAudit", targets: [.target(name: "FitMatch"), .testTarget(name: "FitMatchTests", dependencies: ["FitMatch"])])
''')
(a/'FitMatchMetricsRecorder.swift').write_bytes((r/'FitMatch/Services/FitMatchMetricsRecorder.swift').read_bytes())
(a/'DetailPerformanceDiagnostics.swift').write_bytes((r/'FitMatch/Services/DetailPerformanceDiagnostics.swift').read_bytes())
# Minimal domain stand-ins only for unrelated adapter initializers. Recorder,
# persistence, provider resolver and test bodies are copied unchanged.
(a/'Domain.swift').write_text('''import Foundation
enum ClothingCategory { case top; var taxonomyCode: String { "tops" } }
enum ProductMeasurementAvailability { case actualMeasurements,standardSizeChart,unavailable }
enum Status { case legacy,insufficientEvidence,confirmed }
struct RecommendationHistory { let comparisonStatus:Status; let comparisonMethod:String; let comparedMeasurementUsages:[Int] }
enum AppGroupConfig { static let identifier = "MetricsAudit" }
''')
t=(r/'FitMatchTests/FitMatchMetricsRecorderTests.swift').read_text()
t=t[:t.index('    @Test func productLoadRecordsFiniteParserDimensionsWithoutProductData()')]+'}\n'
(b/'Tests.swift').write_text(t)
(b/'PerformanceTests.swift').write_bytes((r/'FitMatchTests/FitMatchPerformanceDiagnosticsStoreTests.swift').read_bytes())
PY
swift test --disable-sandbox --cache-path "$work/cache" --package-path "$work"
