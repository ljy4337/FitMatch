#!/usr/bin/env python3
"""Opt-in development RPC smoke test; never reads app sessions or admin secrets.

This tests the deployed HTTP contract, not Swift/UI behavior. See DBPreparation.md.
"""
import argparse
import base64
import datetime as dt
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

PROJECT = "hnkplvyegonlhumlejst"
BASE_URL = f"https://{PROJECT}.supabase.co"
PREFIX = "FITMATCH_QA_DB_"
REQUIRED = ("URL", "PUBLIC_KEY", "DEDICATED_USERS", "USER_A_TOKEN", "USER_A_ID",
            "USER_B_TOKEN", "USER_B_ID")


class Blocked(Exception):
    pass


class Failed(Exception):
    pass


class HTTPFailure(Failed):
    def __init__(self, status):
        self.status = status
        super().__init__(f"HTTP {status}; response body omitted")


def canonical_uuid(value):
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError):
        raise Blocked("An expected identity or run ID is not a UUID") from None


def jwt_claims(token):
    try:
        parts = token.split(".")
        if len(parts) != 3:
            raise ValueError()
        return json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
    except (ValueError, TypeError, UnicodeError):
        raise Blocked("Malformed JWT; credential omitted") from None


def validate_config(env):
    missing = [PREFIX + name for name in REQUIRED if not env.get(PREFIX + name)]
    if missing:
        raise Blocked("Missing environment: " + ", ".join(missing))
    value = env[PREFIX + "URL"]
    try:
        url = urllib.parse.urlsplit(value)
        target_ok = (url.scheme == "https" and url.hostname == PROJECT + ".supabase.co"
                     and url.port is None and url.username is None and url.password is None
                     and url.path in ("", "/") and not url.query and not url.fragment)
    except ValueError:
        target_ok = False
    if not target_ok:
        raise Blocked("Only the exact development HTTPS host is allowed")
    if env[PREFIX + "DEDICATED_USERS"] != "1":
        raise Blocked("DEDICATED_USERS=1 must attest both credentials belong to disposable QA accounts")
    key = env[PREFIX + "PUBLIC_KEY"]
    if key.startswith("sb_publishable_"):
        pass
    elif key.startswith("eyJ"):
        claims = jwt_claims(key)
        if claims.get("role") != "anon" or claims.get("ref") != PROJECT:
            raise Blocked("Legacy key must be this development project's anon key")
    else:
        raise Blocked("Only a publishable or development anon key is allowed")
    users = {}
    for label in ("A", "B"):
        token = env[PREFIX + f"USER_{label}_TOKEN"]
        identity = canonical_uuid(env[PREFIX + f"USER_{label}_ID"])
        claims = jwt_claims(token)
        if (claims.get("iss") != BASE_URL + "/auth/v1"
                or claims.get("role") != "authenticated"
                or claims.get("sub", "").lower() != identity
                or not isinstance(claims.get("exp"), (int, float))
                or claims["exp"] <= time.time() + 120
                or claims.get("is_anonymous") is True):
            raise Blocked("User JWT issuer, role, expected UUID, expiry, or account type rejected")
        users[label] = {"id": identity, "token": token}
    if users["A"]["id"] == users["B"]["id"]:
        raise Blocked("Two distinct dedicated QA identities are required")
    return {"key": key, "users": users}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, config):
        self.config = config
        self.http = urllib.request.build_opener(NoRedirect)
        self.request_count = 0

    def request(self, user, path, body=None):
        # All paths are fixed by this harness; neither URL nor redirect is caller-controlled.
        self.request_count += 1
        request = urllib.request.Request(
            BASE_URL + path,
            data=None if body is None else json.dumps(body, allow_nan=False).encode(),
            headers={"apikey": self.config["key"],
                     "Authorization": "Bearer " + self.config["users"][user]["token"],
                     "Content-Type": "application/json"},
            method="GET" if body is None else "POST")
        try:
            with self.http.open(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise HTTPFailure(error.code) from None
        except (urllib.error.URLError, TimeoutError, OSError, ValueError):
            raise Blocked("Network/JSON response unavailable; reconcile the ledger before retry") from None

    def rpc(self, user, name, payload):
        return self.request(user, "/rest/v1/rpc/fitmatch_vnext_" + name, payload)

    def authenticate(self):
        # Decoding claims above is a guard, not authentication proof. Auth verifies both tokens here.
        for label, user in self.config["users"].items():
            verified = self.request(label, "/auth/v1/user")
            if (not isinstance(verified, dict) or verified.get("id", "").lower() != user["id"]
                    or verified.get("role") != "authenticated" or verified.get("is_anonymous") is True):
                raise Blocked("Auth did not verify the expected dedicated identity")


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    with open(temp, "w", encoding="utf-8") as handle:
        os.chmod(temp, 0o600)
        json.dump(value, handle, indent=2, ensure_ascii=False, allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    temp.replace(path)


def require(condition, message):
    if not condition:
        raise Failed(message)


def list_rows(client, label):
    rows = client.rpc(label, "list_closet_items", {})
    require(isinstance(rows, list), "Closet list contract is not an array")
    return rows


def exact_row(client, label, item_id):
    rows = client.rpc(label, "get_closet_item", {"p_closet_item_id": item_id})
    require(isinstance(rows, list) and len(rows) <= 1, "Exact Closet response cardinality failed")
    if rows:
        require(rows[0].get("id", "").lower() == item_id, "Exact server identity mismatch")
    return rows[0] if rows else None


def owned_row(row, ledger):
    require(row is not None, "Run-owned active row is missing")
    require(row.get("client_item_id", "").lower() == ledger["client_item_id"],
            "Run-owned client identity mismatch")
    require(row.get("notes") == ledger["marker"], "Run marker mismatch; mutation refused")
    require(row.get("product_id") is None and row.get("product_variant_id") is None
            and row.get("product_size_id") is None, "Manual QA fixture unexpectedly linked to catalog")


def cleanup(client, ledger, ledger_path):
    require(ledger.get("project") == PROJECT and ledger.get("version") == 1,
            "Ledger target/version rejected")
    run_id = canonical_uuid(ledger.get("run_id"))
    require(ledger.get("marker") == "fitmatch-release-qa:" + run_id, "Ledger marker rejected")
    canonical_uuid(ledger.get("client_item_id"))
    require(ledger.get("owner_id") == client.config["users"]["A"]["id"]
            and ledger.get("observer_id") == client.config["users"]["B"]["id"],
            "Ledger account pair does not match authenticated QA users")
    rows = list_rows(client, "A")
    matches = [row for row in rows if row.get("client_item_id", "").lower() == ledger["client_item_id"]]
    require(len(matches) <= 1, "Duplicate run client identity; cleanup refused")
    if not matches and not ledger.get("server_item_id"):
        # A timed-out create could still commit after an empty read. Do not turn
        # that one empty read into proof of rollback or completed cleanup.
        ledger["cleanup_status"] = "ambiguous_create_not_observed"
        write_json(ledger_path, ledger)
        raise Blocked("Create outcome unresolved; retain ledger and reconcile later")
    if matches:
        row = matches[0]
        owned_row(row, ledger)
        item_id = canonical_uuid(row.get("id"))
        require(not ledger.get("server_item_id") or ledger["server_item_id"] == item_id,
                "Ledger server identity mismatch; cleanup refused")
        ledger["server_item_id"] = item_id
        ledger["cleanup_status"] = "pending_soft_delete"
        write_json(ledger_path, ledger)
        receipt = client.rpc("A", "delete_closet_item", {"p_closet_item_id": item_id})
        require(receipt.get("closet_item_id", "").lower() == item_id and receipt.get("deleted_at"),
                "Delete receipt lacks exact identity or timestamp")
        require(exact_row(client, "A", item_id) is None, "Deleted item still appears in exact read")
    require(all(row.get("client_item_id", "").lower() != ledger["client_item_id"]
                for row in list_rows(client, "A")), "Run row remains active after cleanup")
    ledger["cleanup_status"] = "no_active_run_rows"
    ledger["physical_rows"] = "soft-delete tombstone and child snapshots may remain; no hard delete authorized"
    write_json(ledger_path, ledger)


def manual_payload(ledger):
    # Fields match the app's VNextClosetMutationPayload. The deployed tuple and
    # active chest_width code were independently checked read-only on 2026-10-02.
    return {"client_item_id": ledger["client_item_id"], "item_name": ledger["marker"],
            "audience_code": "UNISEX", "garment_type_code": "tshirt",
            "sleeve_length_code": "short_sleeve", "fit_preference_code": "regular",
            "notes": ledger["marker"], "satisfaction": 3,
            "measurements": [{"fitmatch_measurement_code": "chest_width", "value": 52,
                              "unit_code": "cm", "raw_label": "chest"}]}


def verify_manual(row, ledger, satisfaction):
    owned_row(row, ledger)
    require(row.get("satisfaction") == satisfaction, "Authoritative metadata read-back mismatch")
    measurements = row.get("measurements")
    require(isinstance(measurements, list) and len(measurements) == 1,
            "Manual measurement count mismatch")
    metric = measurements[0]
    require(metric.get("fitmatch_measurement_code") == "chest_width"
            and metric.get("value") == 52 and metric.get("unit_code") == "cm"
            and metric.get("value_source") == "USER_MANUAL", "Manual canonical read-back mismatch")


def smoke(client, run_id, output, report):
    ledger_path = Path(str(output) + ".ledger.json")
    if ledger_path.exists():
        raise Blocked("This output already has a ledger; run cleanup before creating a new run")
    require(not list_rows(client, "A") and not list_rows(client, "B"),
            "Dedicated accounts must start with empty active Closets; existing rows are never changed")
    ledger = {"version": 1, "project": PROJECT, "run_id": canonical_uuid(run_id),
              "owner_id": client.config["users"]["A"]["id"],
              "observer_id": client.config["users"]["B"]["id"],
              "client_item_id": str(uuid.uuid4()), "server_item_id": None,
              "marker": "fitmatch-release-qa:" + canonical_uuid(run_id),
              "cleanup_status": "create_not_started"}
    report["ledger"] = str(ledger_path)
    # Journal BEFORE the request. Lost create responses can be reconciled by exact
    # client UUID and run marker; never search by latest row or visible label alone.
    ledger["cleanup_status"] = "create_may_commit"
    write_json(ledger_path, ledger)
    try:
        payload = manual_payload(ledger)
        receipt = client.rpc("A", "upsert_closet_item", {"p_request": payload})
        item_id = canonical_uuid(receipt.get("item_id") or receipt.get("closet_item_id"))
        if receipt.get("item_id") and receipt.get("closet_item_id"):
            require(receipt["item_id"] == receipt["closet_item_id"], "Conflicting mutation identities")
        ledger["server_item_id"] = item_id
        write_json(ledger_path, ledger)
        verify_manual(exact_row(client, "A", item_id), ledger, 3)
        report["cases"].append({"id": "DB-CREATE-READ", "status": "PASS"})
        repeat = client.rpc("A", "upsert_closet_item", {"p_request": payload})
        require((repeat.get("item_id") or repeat.get("closet_item_id")) == item_id
                and repeat.get("idempotent") is True, "Same-request retry did not retain exact identity")
        require(len(list_rows(client, "A")) == 1, "Same-request retry created duplicate active rows")
        report["cases"].append({"id": "DB-IDEMPOTENT-RETRY", "status": "PASS"})
        require(exact_row(client, "B", item_id) is None and not list_rows(client, "B"),
                "Other QA user can see the run row")
        report["cases"].append({"id": "DB-OTHER-USER-READ", "status": "PASS"})
        for method, args in [("update_closet_item", {"p_closet_item_id": item_id,
                                                   "p_request": dict(payload, satisfaction=1)}),
                             ("delete_closet_item", {"p_closet_item_id": item_id})]:
            try:
                client.rpc("B", method, args)
            except HTTPFailure as error:
                require(error.status in (400, 403, 404), "Unexpected unauthorized mutation HTTP status")
            else:
                raise Failed("Other QA user's mutation unexpectedly succeeded")
            verify_manual(exact_row(client, "A", item_id), ledger, 3)
        report["cases"].append({"id": "DB-OTHER-USER-MUTATION", "status": "PASS"})
        receipt = client.rpc("A", "update_closet_item",
                             {"p_closet_item_id": item_id, "p_request": dict(payload, satisfaction=4)})
        require((receipt.get("closet_item_id") or receipt.get("item_id")) == item_id,
                "Update receipt identity mismatch")
        verify_manual(exact_row(client, "A", item_id), ledger, 4)
        report["cases"].append({"id": "DB-EDIT-READ", "status": "PASS"})
    finally:
        try:
            cleanup(client, ledger, ledger_path)
            report["cleanup"] = "PASS: no active run rows; soft-deleted storage retained"
        except (Blocked, Failed, OSError) as error:
            report["cleanup"] = "BLOCKED: " + str(error)
            raise Blocked("Cleanup needs retry with the saved ownership ledger") from None
    report["cases"].append({"id": "DB-DELETE-READ", "status": "PASS"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("preflight", "smoke", "cleanup"))
    parser.add_argument("--run-id")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--ledger", type=Path)
    args = parser.parse_args()
    report = {"version": 1, "mode": args.mode, "project": PROJECT,
              "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
              "status": "BLOCKED", "evidence_kind": "authenticated_http_rpc_contract",
              "swift_owner_proof": False, "cases": [], "request_count": 0}
    client = None
    try:
        if args.mode == "smoke" and (not args.run_id or not args.output):
            raise Blocked("smoke requires --run-id UUID and --output PATH")
        if args.mode == "cleanup" and not args.ledger:
            raise Blocked("cleanup requires --ledger PATH")
        if args.run_id:
            canonical_uuid(args.run_id)
        config = validate_config(os.environ)
        client = Client(config)
        client.authenticate()
        if args.mode == "smoke":
            smoke(client, args.run_id, args.output, report)
        elif args.mode == "cleanup":
            cleanup(client, json.loads(args.ledger.read_text()), args.ledger)
            report["cleanup"] = "PASS: no active run rows; soft-deleted storage retained"
        report["status"] = "PASS"
    except Blocked as error:
        report["reason"] = str(error)
    except (Failed, OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        report["status"] = "FAIL"
        # Unknown exception details may contain a credential or response body.
        report["reason"] = str(error) if isinstance(error, Failed) else type(error).__name__
    report["request_count"] = client.request_count if client else 0
    report["real_db_case_count"] = len(report["cases"])
    report["mock_case_count"] = 0
    if args.output:
        write_json(args.output, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return {"PASS": 0, "FAIL": 1, "BLOCKED": 2}[report["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
