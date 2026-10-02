"""Offline session-bootstrap guards; no real credentials or network requests."""
import contextlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_qa_db as db
from test_release_qa_db import token


class SessionSetupTests(unittest.TestCase):
    def setUp(self):
        import release_qa_session
        self.setup = release_qa_session
        self.env = {db.PREFIX + "URL": db.BASE_URL,
                    db.PREFIX + "PUBLIC_KEY": "sb_publishable_offline_fixture",
                    db.PREFIX + "DEDICATED_USERS": "1"}
        self.sessions = []
        self.users = []
        for label in ("A", "B"):
            identity = str(uuid.uuid4())
            for suffix, value in (("ID", identity), ("EMAIL", label + "@example.invalid"),
                                  ("PASSWORD", "offline-secret-" + label)):
                self.env[db.PREFIX + f"USER_{label}_{suffix}"] = value
            user = {"id": identity, "role": "authenticated", "is_anonymous": False}
            self.users.append(user)
            self.sessions.append({"user": user, "token_type": "bearer",
                                  "access_token": token(dict(user, sub=identity,
                                      iss=db.BASE_URL + "/auth/v1", exp=time.time() + 3600)),
                                  "refresh_token": "offline-refresh-" + label})

    def execute(self, responses, env=None, directory=None):
        calls = []
        def respond(request, timeout):
            calls.append(request)
            response = responses.pop(0)
            if isinstance(response, BaseException):
                raise response
            return io.BytesIO(json.dumps(response).encode())
        output = io.StringIO()
        # Preserve OS runtime variables: clearing the entire Darwin environment
        # makes confstr(_CS_DARWIN_USER_TEMP_DIR) itself fail with EIO.
        with patch.dict(os.environ, self.env if env is None else env), \
                patch("urllib.request.OpenerDirector.open", side_effect=respond), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            args = ["--sign-in", "--output-dir", str(directory)]
            code = self.setup.main(args)
        return code, output.getvalue(), calls

    def test_default_is_offline_and_does_not_read_secrets_or_write(self):
        with patch("urllib.request.OpenerDirector.open", side_effect=AssertionError("network")), \
                patch("getpass.getpass", side_effect=AssertionError("prompt")), \
                patch("tempfile.mkdtemp", side_effect=AssertionError("file")), \
                patch.dict(os.environ, {}, clear=True), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.setup.main([]), 0)

    def test_unsafe_project_and_key_block_before_network(self):
        for change in ({"URL": "https://aqhrupgjpmrtnystottx.supabase.co"},
                       {"URL": db.BASE_URL + "@evil.test"},
                       {"URL": db.BASE_URL + "/auth/v1"},
                       {"PUBLIC_KEY": "sb_secret_never-use"},
                       {"PUBLIC_KEY": token({"role": "service_role", "ref": db.PROJECT})},
                       {"DEDICATED_USERS": "0"}):
            with self.subTest(change=list(change)), tempfile.TemporaryDirectory() as directory:
                env = dict(self.env, **{db.PREFIX + k: v for k, v in change.items()})
                code, output, calls = self.execute([], env, directory)
                self.assertEqual(code, 2)
                self.assertEqual(calls, [])
                self.assertEqual(list(Path(directory).iterdir()), [])
                self.assertNotIn(env[db.PREFIX + "PUBLIC_KEY"], output)

    def test_two_expected_owners_must_differ(self):
        env = dict(self.env, **{db.PREFIX + "USER_B_ID": self.users[0]["id"]})
        with tempfile.TemporaryDirectory() as directory:
            code, _, calls = self.execute([], env, directory)
            self.assertEqual((code, calls), (2, []))

    def test_login_failure_leaves_no_file_or_secret_output(self):
        secret = self.env[db.PREFIX + "USER_B_PASSWORD"]
        with tempfile.TemporaryDirectory() as directory:
            code, output, calls = self.execute([self.sessions[0], OSError(secret)], directory=directory)
            self.assertEqual(code, 2)
            self.assertEqual(len(calls), 2)
            self.assertEqual(list(Path(directory).iterdir()), [])
            self.assertNotIn(secret, output)
            self.assertNotIn(self.sessions[0]["access_token"], output)
            self.assertNotIn(self.sessions[0]["refresh_token"], output)

    def test_identity_verification_failure_leaves_no_file(self):
        with tempfile.TemporaryDirectory() as directory:
            code, _, calls = self.execute(self.sessions + [self.users[1]], directory=directory)
            self.assertEqual(code, 2)
            self.assertEqual(len(calls), 3)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_session_must_meet_current_swift_freshness_and_account_type(self):
        for changes in ({"exp": time.time() + 300}, {"exp": float("inf")}, {"is_anonymous": None}):
            session = dict(self.sessions[0])
            session["access_token"] = token(dict(db.jwt_claims(session["access_token"]), **changes))
            with self.subTest(changes=list(changes)), tempfile.TemporaryDirectory() as directory:
                code, _, _ = self.execute([session, self.sessions[1]], directory=directory)
                self.assertEqual(code, 2)
                self.assertEqual(list(Path(directory).iterdir()), [])

    def test_success_private_file_matches_runner_contract_and_omits_passwords(self):
        with tempfile.TemporaryDirectory() as directory:
            code, output, calls = self.execute(self.sessions + self.users, directory=directory)
            self.assertEqual(code, 0)
            path = Path(output.strip())
            self.assertTrue(path.is_file())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            content = path.read_text()
            for label in ("A", "B"):
                self.assertIn(db.PREFIX + f"USER_{label}_REFRESH_TOKEN=", content)
                self.assertNotIn(self.env[db.PREFIX + f"USER_{label}_PASSWORD"], content)
                self.assertNotIn(self.env[db.PREFIX + f"USER_{label}_EMAIL"], content)
            self.assertEqual([r.full_url for r in calls], [db.BASE_URL + "/auth/v1/token?grant_type=password"] * 2
                             + [db.BASE_URL + "/auth/v1/user"] * 2)
            self.assertEqual([r.method for r in calls], ["POST", "POST", "GET", "GET"])
            for session in self.sessions:
                self.assertNotIn(session["access_token"], output)
                self.assertNotIn(session["refresh_token"], output)

    def test_output_inside_any_git_checkout_rejected_before_auth(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / ".git").write_text("gitdir: ignored")
            code, _, calls = self.execute([], directory=directory)
            self.assertEqual((code, calls), (2, []))
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

    def test_output_outside_temporary_storage_rejected(self):
        code, _, calls = self.execute([], directory=Path(__file__).resolve().parents[2])
        self.assertEqual((code, calls), (2, []))

    @unittest.skipUnless(sys.platform == "darwin", "macOS system temporary directory")
    def test_darwin_system_temp_without_python_symbolic_constant(self):
        system_temp = Path(os.confstr(65537)).resolve()
        with patch.dict(os.confstr_names, {}, clear=True):
            self.assertEqual(self.setup.private_temp_parent(system_temp), system_temp)

    def test_symlinked_output_parent_rejected_before_auth(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "actual").mkdir()
            (root / "alias").symlink_to(root / "actual", target_is_directory=True)
            code, _, calls = self.execute([], directory=root / "alias")
            self.assertEqual((code, calls), (2, []))
            self.assertEqual(list((root / "actual").iterdir()), [])

    def test_redirects_cannot_forward_credentials(self):
        self.assertIsNone(db.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid"))


if __name__ == "__main__":
    unittest.main()
