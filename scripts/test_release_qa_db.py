"""Offline safety guards only: these are not authenticated database test evidence."""
import base64
import json
import tempfile
import time
import unittest
import uuid
from pathlib import Path

import release_qa_db as db


def token(claims):
    encoded = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    return "eyJhbGciOiJIUzI1NiJ9." + encoded + ".offline-not-a-real-signature"


class DevelopmentDatabaseSafetyTests(unittest.TestCase):
    def setUp(self):
        self.env = {db.PREFIX + "URL": db.BASE_URL,
                    db.PREFIX + "PUBLIC_KEY": "sb_publishable_offline_fixture",
                    db.PREFIX + "DEDICATED_USERS": "1"}
        for label in ("A", "B"):
            identity = str(uuid.uuid4())
            self.env[db.PREFIX + f"USER_{label}_ID"] = identity
            self.env[db.PREFIX + f"USER_{label}_TOKEN"] = token({
                "iss": db.BASE_URL + "/auth/v1", "role": "authenticated",
                "sub": identity, "exp": time.time() + 3600, "is_anonymous": False})

    def test_exact_dev_fixture_passes_local_guard_only(self):
        self.assertEqual(set(db.validate_config(self.env)["users"]), {"A", "B"})

    def test_production_and_host_confusion_blocked(self):
        for url in ("https://aqhrupgjpmrtnystottx.supabase.co", db.BASE_URL + ".evil.test",
                    db.BASE_URL + "@evil.test", "http://" + db.PROJECT + ".supabase.co",
                    db.BASE_URL + ":443", db.BASE_URL + "/auth/v1", db.BASE_URL + "?x=1"):
            with self.subTest(url=url), self.assertRaises(db.Blocked):
                db.validate_config(dict(self.env, **{db.PREFIX + "URL": url}))

    def test_secret_and_service_role_keys_blocked(self):
        for key in ("sb_secret_offline", token({"role": "service_role", "ref": db.PROJECT})):
            with self.subTest(key_kind=key[:9]), self.assertRaises(db.Blocked):
                db.validate_config(dict(self.env, **{db.PREFIX + "PUBLIC_KEY": key}))

    def test_missing_dedicated_attestation_blocked(self):
        with self.assertRaises(db.Blocked):
            db.validate_config(dict(self.env, **{db.PREFIX + "DEDICATED_USERS": "0"}))

    def test_same_user_pair_blocked(self):
        env = dict(self.env)
        for suffix in ("ID", "TOKEN"):
            env[db.PREFIX + "USER_B_" + suffix] = env[db.PREFIX + "USER_A_" + suffix]
        with self.assertRaises(db.Blocked):
            db.validate_config(env)

    def test_foreign_expired_and_elevated_user_tokens_blocked(self):
        base = db.jwt_claims(self.env[db.PREFIX + "USER_A_TOKEN"])
        changes = ({"iss": "https://aqhrupgjpmrtnystottx.supabase.co/auth/v1"},
                   {"exp": 1}, {"role": "service_role"}, {"sub": str(uuid.uuid4())},
                   {"is_anonymous": True})
        for change in changes:
            with self.subTest(change=list(change)), self.assertRaises(db.Blocked):
                db.validate_config(dict(self.env, **{
                    db.PREFIX + "USER_A_TOKEN": token(dict(base, **change))}))

    def test_cleanup_refuses_foreign_project_or_identity_before_rpc(self):
        config = db.validate_config(self.env)
        class FakeClient:
            def __init__(self):
                self.config = config
            def rpc(self, *args):
                raise AssertionError("Must reject before any RPC")
        run_id = str(uuid.uuid4())
        ledger = {"version": 1, "project": db.PROJECT, "run_id": run_id,
                  "marker": "fitmatch-release-qa:" + run_id, "client_item_id": str(uuid.uuid4()),
                  "owner_id": config["users"]["A"]["id"],
                  "observer_id": config["users"]["B"]["id"]}
        for change in ({"project": "aqhrupgjpmrtnystottx"}, {"owner_id": str(uuid.uuid4())},
                       {"marker": "unrelated"}):
            with self.subTest(change=list(change)), self.assertRaises(db.Failed):
                db.cleanup(FakeClient(), dict(ledger, **change), Path("unused.json"))

    def test_cleanup_refuses_marker_mismatch_before_delete(self):
        config = db.validate_config(self.env)
        run_id, client_id = str(uuid.uuid4()), str(uuid.uuid4())
        ledger = {"version": 1, "project": db.PROJECT, "run_id": run_id,
                  "marker": "fitmatch-release-qa:" + run_id, "client_item_id": client_id,
                  "owner_id": config["users"]["A"]["id"],
                  "observer_id": config["users"]["B"]["id"]}
        class FakeClient:
            def __init__(self):
                self.config = config
            def rpc(self, user, name, payload):
                if name != "list_closet_items":
                    raise AssertionError("No mutation permitted")
                return [{"client_item_id": client_id, "notes": "someone else's row"}]
        with self.assertRaises(db.Failed):
            db.cleanup(FakeClient(), ledger, Path("unused.json"))

    def test_empty_read_does_not_complete_ambiguous_create(self):
        config = db.validate_config(self.env)
        run_id = str(uuid.uuid4())
        ledger = {"version": 1, "project": db.PROJECT, "run_id": run_id,
                  "marker": "fitmatch-release-qa:" + run_id, "client_item_id": str(uuid.uuid4()),
                  "server_item_id": None, "owner_id": config["users"]["A"]["id"],
                  "observer_id": config["users"]["B"]["id"]}
        class FakeClient:
            def __init__(self):
                self.config = config
            def rpc(self, user, name, payload):
                if name != "list_closet_items":
                    raise AssertionError("No mutation permitted")
                return []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ledger.json"
            with self.assertRaises(db.Blocked):
                db.cleanup(FakeClient(), ledger, path)
            self.assertEqual(json.loads(path.read_text())["cleanup_status"],
                             "ambiguous_create_not_observed")


if __name__ == "__main__":
    unittest.main()
