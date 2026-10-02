#!/usr/bin/env bash
set -euo pipefail

# Runs the real Foundation-only candidate/deletion contracts and test sources.
# No Simulator, network dependency, credentials, or database connection.
audit_repo="$(cd "$(dirname "$0")/.." && pwd)"
audit_dir="$(mktemp -d /tmp/fitmatch-candidate-contract.XXXXXX)"
python3 - "$audit_repo" "$audit_dir" <<'PY'
from pathlib import Path
import sys
repo, work = map(Path, sys.argv[1:])
source = work / 'Sources/FitMatch'
tests = work / 'Tests/FitMatchTests'
source.mkdir(parents=True)
tests.mkdir(parents=True)
(work / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CandidateContractAudit", platforms: [.macOS(.v14)],
    targets: [.target(name: "FitMatch"),
              .testTarget(name: "FitMatchTests", dependencies: ["FitMatch"])])
''')
for name in ['FitMatchVNextDTOs.swift', 'FitMatchVNextContractValidator.swift',
             'FitMatchClosetDeletionTransaction.swift']:
    (source / name).write_bytes((repo / 'FitMatch/Services' / name).read_bytes())
# Exact production copy constants; no replacement validator or DTO stub.
text = (repo / 'FitMatch/Services/FitMatchServerAuthorityCoordinator.swift').read_text()
start = text.index('nonisolated enum FitMatchFailureCopy {')
end = text.index('\n}', start) + 2
(source / 'FailureCopy.swift').write_text('import Foundation\n' + text[start:end] + '\n')
for name in ['FitMatchCandidateEnvelopeTests.swift', 'FitMatchClosetDeletionTransactionTests.swift']:
    (tests / name).write_bytes((repo / 'FitMatchTests' / name).read_bytes())
PY
echo "Local contract test package: $audit_dir"
swift test --package-path "$audit_dir"
