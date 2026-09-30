#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR_ROOT="${FITMATCH_RETAILER_COLLECTOR_ROOT:-$(cd "$PROJECT_ROOT/../../.." && pwd)/RetailerCatalogCollector}"
FIXTURE_ROOT="${FITMATCH_FIXTURE_ROOT:-$COLLECTOR_ROOT/data/fitmatch_fixtures}"
MODE="${1:-all}"
DESTINATION="${FITMATCH_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
DERIVED_DATA="${FITMATCH_DERIVED_DATA_PATH:-/tmp/FitMatchFixtureDerivedData}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
REPORT_ROOT="${FITMATCH_FIXTURE_REPORT_DIR:-$PROJECT_ROOT/data/test-results/fixture-replay-$RUN_ID}"
REPLAY_CONFIG="$PROJECT_ROOT/.fitmatch-fixture-replay-config.json"
DB_PAYLOAD_STAGING="/tmp/fitmatch-fixture-payloads.csv"

mkdir -p "$REPORT_ROOT"

cleanup() {
    rm -f "$REPLAY_CONFIG"
    rm -f "$DB_PAYLOAD_STAGING"
}
trap cleanup EXIT

require_fixtures() {
    if [[ ! -f "$FIXTURE_ROOT/report.json" ]]; then
        echo "Fixture report not found: $FIXTURE_ROOT/report.json" >&2
        exit 2
    fi
}

run_builder_tests() {
    (
        cd "$COLLECTOR_ROOT"
        PYTHONPYCACHEPREFIX=/tmp/fitmatch-fixture-pycache \
            .venv/bin/python -m unittest tests.test_fitmatch_fixture_builder
    )
}

run_xcode_tests() {
    local result_name="$1"
    shift
    local result_path="$REPORT_ROOT/$result_name.xcresult"
    rm -rf "$result_path"
    (
        cd "$PROJECT_ROOT"
        FITMATCH_RUN_COLLECTED_FIXTURE_REPLAY="${FITMATCH_RUN_COLLECTED_FIXTURE_REPLAY:-0}" \
        FITMATCH_FIXTURE_ROOT="$FIXTURE_ROOT" \
        FITMATCH_FIXTURE_PROVIDERS="${FITMATCH_FIXTURE_PROVIDERS:-uniqlo,musinsa,zara}" \
        FITMATCH_FIXTURE_LIMIT_PER_PROVIDER="${FITMATCH_FIXTURE_LIMIT_PER_PROVIDER:-0}" \
        FITMATCH_EXPORT_SWIFT_PAYLOADS="${FITMATCH_EXPORT_SWIFT_PAYLOADS:-0}" \
        FITMATCH_FIXTURE_REPORT_DIR="$REPORT_ROOT" \
        xcodebuild \
            -project FitMatch.xcodeproj \
            -scheme FitMatch \
            -destination "$DESTINATION" \
            -derivedDataPath "$DERIVED_DATA" \
            -resultBundlePath "$result_path" \
            "$@" \
            test
    ) 2>&1 | tee "$REPORT_ROOT/$result_name.log"
}

write_replay_config() {
    jq -n \
        --arg fixtureRoot "$FIXTURE_ROOT" \
        --arg providers "${FITMATCH_FIXTURE_PROVIDERS:-uniqlo,musinsa,zara}" \
        --argjson limitPerProvider "${FITMATCH_FIXTURE_LIMIT_PER_PROVIDER:-0}" \
        --argjson exportPayloads "${FITMATCH_EXPORT_SWIFT_PAYLOADS:-0}" \
        --arg reportRoot "$REPORT_ROOT" \
        '{fixtureRoot: $fixtureRoot, providers: $providers, limitPerProvider: $limitPerProvider, exportPayloads: ($exportPayloads == 1), reportRoot: $reportRoot}' \
        > "$REPLAY_CONFIG"
}

run_fixture_replay() {
    require_fixtures
    run_builder_tests
    FITMATCH_EXPORT_SWIFT_PAYLOADS=1 write_replay_config
    FITMATCH_RUN_COLLECTED_FIXTURE_REPLAY=1 run_xcode_tests \
        swift-fixture-replay \
        -only-testing:FitMatchTests/FitMatchCollectedFixtureReplayTests/testCollectedRetailerAPIsUseCurrentSwiftParsersAndEncoder
}

run_closet_and_compare() {
    run_xcode_tests \
        closet-comparison-flow \
        -only-testing:FitMatchTests/FitMatchFinalReleaseProviderSnapshotTests
}

guard_local_database() {
    local database_url="${FITMATCH_FIXTURE_DATABASE_URL:-}"
    local actor_id="${FITMATCH_FIXTURE_ACTOR_ID:-}"
    if [[ -z "$database_url" ]]; then
        echo "FITMATCH_FIXTURE_DATABASE_URL is required for database mode." >&2
        exit 2
    fi
    case "$database_url" in
        *localhost*|*127.0.0.1*|*%2Flocalhost*|*%2F127.0.0.1*) ;;
        *)
            echo "Refusing non-local database URL. Fixture DB replay is local/disposable only." >&2
            exit 2
            ;;
    esac
    if [[ ! "$actor_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        echo "FITMATCH_FIXTURE_ACTOR_ID must be a user UUID seeded in the local database." >&2
        exit 2
    fi
}

run_database() {
    require_fixtures
    guard_local_database
    write_replay_config
    FITMATCH_RUN_COLLECTED_FIXTURE_REPLAY=1 \
    FITMATCH_EXPORT_SWIFT_PAYLOADS=1 \
        run_xcode_tests \
            swift-payload-export \
            -only-testing:FitMatchTests/FitMatchCollectedFixtureReplayTests/testCollectedRetailerAPIsUseCurrentSwiftParsersAndEncoder
    local payload_file="$REPORT_ROOT/swift-payloads.jsonl"
    local payload_csv="$REPORT_ROOT/swift-payloads.csv"
    if [[ ! -s "$payload_file" ]]; then
        echo "Swift payload export was not created: $payload_file" >&2
        exit 2
    fi
    jq -Rr '[.] | @csv' "$payload_file" > "$payload_csv"
    cp "$payload_csv" "$DB_PAYLOAD_STAGING"
    psql "$FITMATCH_FIXTURE_DATABASE_URL" \
        -v ON_ERROR_STOP=1 \
        -v fixture_actor_id="$FITMATCH_FIXTURE_ACTOR_ID" \
        -f "$PROJECT_ROOT/supabase/sql/130_fixture_replay_local_transaction.sql" \
        > "$REPORT_ROOT/database-replay.log"
    cat "$REPORT_ROOT/database-replay.log"
}

case "$MODE" in
    fixtures|parser) run_fixture_replay ;;
    closet|compare) run_closet_and_compare ;;
    database) run_database ;;
    all)
        run_fixture_replay
        run_closet_and_compare
        if [[ -n "${FITMATCH_FIXTURE_DATABASE_URL:-}" ]]; then
            run_database
        else
            echo "Database replay SKIP: FITMATCH_FIXTURE_DATABASE_URL is not set."
        fi
        ;;
    *)
        echo "Usage: $0 {fixtures|parser|closet|compare|database|all}" >&2
        exit 2
        ;;
esac

echo "Fixture test artifacts: $REPORT_ROOT"
