#!/usr/bin/env python3
"""Prepare two existing dedicated development Auth sessions; offline by default."""
import argparse
import getpass
import json
import math
import os
from pathlib import Path
import shlex
import sys
import tempfile
import time
import urllib.error
import urllib.request
import warnings

import release_qa_db as db


def login_inputs(env):
    required = ("URL", "PUBLIC_KEY", "DEDICATED_USERS", "USER_A_ID", "USER_B_ID")
    missing = [db.PREFIX + key for key in required if not env.get(db.PREFIX + key)]
    if missing:
        raise db.Blocked("Missing environment: " + ", ".join(missing))
    if env[db.PREFIX + "URL"] not in (db.BASE_URL, db.BASE_URL + "/"):
        raise db.Blocked("Only the exact development HTTPS URL is allowed")
    if env[db.PREFIX + "DEDICATED_USERS"] != "1":
        raise db.Blocked("DEDICATED_USERS=1 must attest both accounts are dedicated QA accounts")
    key = env[db.PREFIX + "PUBLIC_KEY"]
    if not key.startswith("sb_publishable_"):
        claims = db.jwt_claims(key)
        if not isinstance(claims, dict) or claims.get("role") != "anon" or claims.get("ref") != db.PROJECT:
            raise db.Blocked("Only the development publishable or anon key is allowed")
    values = {db.PREFIX + name: env[db.PREFIX + name] for name in required}
    for label in ("A", "B"):
        name = db.PREFIX + f"USER_{label}_ID"
        values[name] = db.canonical_uuid(values[name])
    if values[db.PREFIX + "USER_A_ID"] == values[db.PREFIX + "USER_B_ID"]:
        raise db.Blocked("Two distinct expected dedicated user UUIDs are required")
    return values


def private_temp_parent(path):
    original = Path(path).expanduser().absolute()
    # macOS system /tmp and /var aliases are expected; arbitrary symlinked paths are not.
    for part in (original, *original.parents):
        if part.is_symlink() and part not in (Path("/tmp"), Path("/var")):
            raise db.Blocked("Symlinked session output paths are forbidden")
    parent = original.resolve(strict=True)
    roots = {Path("/tmp").resolve()}
    if sys.platform == "darwin":
        # Darwin _CS_DARWIN_USER_TEMP_DIR is 65537; Apple's Python 3.9 omits
        # its symbolic confstr_names entry. Ask the OS, never trust TMPDIR here.
        selector = os.confstr_names.get("CS_DARWIN_USER_TEMP_DIR", 65537)
        system_temp = os.confstr(selector)
        if system_temp:
            roots.add(Path(system_temp).resolve())
    if not parent.is_dir() or not any(parent == root or root in parent.parents for root in roots):
        raise db.Blocked("Session output must be in temporary storage outside any Git checkout")
    if any((ancestor / ".git").exists() for ancestor in (parent, *parent.parents)):
        raise db.Blocked("Session output inside a Git checkout is forbidden")
    return parent


def hidden_value(env, name, prompt):
    value = env.get(name)
    if not value:
        # getpass otherwise falls back to echoing on some non-interactive terminals.
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            try:
                value = getpass.getpass(prompt)
            except (getpass.GetPassWarning, EOFError):
                raise db.Blocked("A non-echoing terminal or secure environment input is required") from None
    if not value or "\x00" in value:
        raise db.Blocked("Empty or invalid login input; value omitted")
    return value


def password_sign_in(http, key, email, password):
    request = urllib.request.Request(
        db.BASE_URL + "/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": password}).encode(),
        headers={"apikey": key, "Content-Type": "application/json"}, method="POST")
    try:
        with http.open(request, timeout=30) as response:
            value = json.load(response)
    except urllib.error.HTTPError as error:
        raise db.Blocked(f"Normal sign-in rejected (HTTP {error.code}); response omitted") from None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        raise db.Blocked("Normal sign-in unavailable; response and credentials omitted") from None
    if not isinstance(value, dict):
        raise db.Blocked("Malformed Auth session response; body omitted")
    return value


def establish_sessions(values, env):
    http = urllib.request.build_opener(db.NoRedirect)
    credentials = {}
    # Collect both inputs first so a cancelled second prompt creates no session.
    for label in ("A", "B"):
        prefix = db.PREFIX + f"USER_{label}_"
        credentials[label] = (
            hidden_value(env, prefix + "EMAIL", f"Dedicated account {label} email (hidden): "),
            hidden_value(env, prefix + "PASSWORD", f"Dedicated account {label} password (hidden): "))
    for label in ("A", "B"):
        session = password_sign_in(http, values[db.PREFIX + "PUBLIC_KEY"], *credentials.pop(label))
        user = session.get("user")
        prefix = db.PREFIX + f"USER_{label}_"
        if (not isinstance(user, dict) or db.canonical_uuid(user.get("id")) != values[prefix + "ID"]
                or user.get("role") != "authenticated" or user.get("is_anonymous") is not False
                or session.get("token_type", "").lower() != "bearer"):
            raise db.Blocked("Sign-in did not return the expected normal dedicated identity")
        for source, target in (("access_token", "TOKEN"), ("refresh_token", "REFRESH_TOKEN")):
            value = session.get(source)
            if not isinstance(value, str) or not value.strip() or any(c.isspace() for c in value) or "\0" in value:
                raise db.Blocked("Missing or malformed session token; value omitted")
            values[prefix + target] = value
    # Reuse the deployed-RPC harness guard, then the stricter current Swift SDK guard.
    config = db.validate_config(values)
    for user in config["users"].values():
        claims = db.jwt_claims(user["token"])
        expiry = claims.get("exp")
        if (not isinstance(expiry, (float, int)) or not math.isfinite(expiry)
                or expiry <= time.time() + 600 or claims.get("is_anonymous") is not False):
            raise db.Blocked("Normal sessions with more than 600 seconds remaining are required")
    client = db.Client(config)
    # Server verification is required; decoding JWT claims is not authentication proof.
    for label, user in config["users"].items():
        verified = client.request(label, "/auth/v1/user")
        if (not isinstance(verified, dict) or db.canonical_uuid(verified.get("id")) != user["id"]
                or verified.get("role") != "authenticated" or verified.get("is_anonymous") is not False):
            raise db.Blocked("Auth did not verify the expected normal dedicated identity")
    return values


def save_sessions(parent, values):
    # Fresh private directory and exclusive file creation; never overwrite another run.
    directory = Path(tempfile.mkdtemp(prefix="fitmatch-qa-session-", dir=parent))
    path = directory / "sessions.env"
    try:
        os.chmod(directory, 0o700)
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            os.fchmod(handle.fileno(), 0o600)
            for name, value in sorted(values.items()):
                handle.write("export " + name + "=" + shlex.quote(value) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
    except BaseException:
        path.unlink(missing_ok=True)
        directory.rmdir()
        raise
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sign-in", action="store_true", help="explicitly perform two normal password sign-ins")
    parser.add_argument("--output-dir", type=Path, default=Path(tempfile.gettempdir()),
                        help="temporary parent directory outside any Git checkout")
    args = parser.parse_args(argv)
    if not args.sign_in:
        print("PREPARED: no credential reads, network requests, sessions, or files created.\n"
              "See Docs/QA/ReleasePreparation20261002/SessionSetup.md.\n"
              "Normal login requires --sign-in plus the exact development URL, public key,\n"
              "DEDICATED_USERS=1 and both expected UUIDs. Email/password use hidden prompts\n"
              "or secure FITMATCH_QA_DB_USER_{A,B}_{EMAIL,PASSWORD} environment values.")
        return 0
    try:
        values = login_inputs(os.environ)
        parent = private_temp_parent(args.output_dir)
        values = establish_sessions(values, os.environ)
        path = save_sessions(parent, values)
    except (db.Blocked, db.HTTPFailure) as error:
        print("BLOCKED: " + str(error))
        return 2
    except KeyboardInterrupt:
        print("BLOCKED: cancelled; no credential file saved. Auth sessions may already exist.")
        return 2
    except Exception:
        # Unexpected exceptions may embed request bodies, credentials, or server responses.
        print("BLOCKED: session setup failed; details omitted; no credential file saved.")
        return 2
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
