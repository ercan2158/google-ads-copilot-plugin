#!/usr/bin/env python3
"""bin/test-ga.py — assertions for bin/ga.py's wrapper logic.

Strategy: stub out the google-ads library at sys.modules level BEFORE
importing bin/ga.py. The wrapper logic (yaml loading, workspace walk-up,
customer-id validation, GoogleAdsException → REST-error envelope, proxy
header construction) is then exercised in-process without any network
call or library install.

Runs cleanly in two modes:
  - CI (only PyYAML installed) — stubs cover the rest
  - Local venv (full google-ads installed) — stubs override the real
    library so tests don't hit the network

Usage: bin/test-ga.py
"""

from __future__ import annotations

import importlib
import io
import json
import os
import sys
import tempfile
import types
import unittest.mock
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
BIN_DIR = REPO_DIR / "bin"
sys.path.insert(0, str(BIN_DIR))


# -----------------------------------------------------------------------------
# Stub the google-ads library so bin/ga can import without it being installed.
# -----------------------------------------------------------------------------


class _FakeGoogleAdsException(Exception):
    """Mimics google.ads.googleads.errors.GoogleAdsException's shape."""

    def __init__(self, *, errors, request_id="req-1", code_value=400, code_name="INVALID_ARGUMENT", message="bad"):
        super().__init__(message)
        self.request_id = request_id

        class _ErrorCode:
            def __init__(self, name, value):
                self._name = name
                self._value = value

            class _Wrapper:
                def __init__(self, name, value):
                    self.name = name
                    self.value = value

            def name_obj(self):
                return self._Wrapper(self._name, self._value)

        class _Err:
            def __init__(self, name, value, msg):
                self._name = name
                self._value = value
                self._msg = msg

            def code(self):
                class C:
                    def __init__(self, n, v):
                        self.name = n
                        self.value = v
                return C(self._name, self._value)

            def message(self):
                return self._msg

        class _Failure:
            def __init__(self, errs):
                self.errors = errs

        self.error = _Err(code_name, code_value, message)
        self.failure = _Failure(errors)


def _install_stubs():
    """Inject fake google.ads.googleads.* and protobuf modules so bin/ga
    imports cleanly without the real library."""
    google = types.ModuleType("google")
    google_ads = types.ModuleType("google.ads")
    google_ads_googleads = types.ModuleType("google.ads.googleads")
    google_ads_client = types.ModuleType("google.ads.googleads.client")
    google_ads_errors = types.ModuleType("google.ads.googleads.errors")
    protobuf = types.ModuleType("google.protobuf")
    json_format = types.ModuleType("google.protobuf.json_format")
    google_oauth2 = types.ModuleType("google.oauth2")
    oauth2_credentials = types.ModuleType("google.oauth2.credentials")
    google_auth = types.ModuleType("google.auth")
    auth_transport = types.ModuleType("google.auth.transport")
    auth_requests = types.ModuleType("google.auth.transport.requests")

    # Stub classes — tests will patch attributes on these as needed
    class _StubClient:
        loaded_configs: list[dict] = []

        @classmethod
        def load_from_dict(cls, config, version=None):
            cls.loaded_configs.append(dict(config))
            instance = cls()
            instance._config = config
            instance._version = version
            return instance

        def get_service(self, name):  # pragma: no cover — overridden in tests
            return unittest.mock.MagicMock()

    google_ads_client.GoogleAdsClient = _StubClient
    google_ads_errors.GoogleAdsException = _FakeGoogleAdsException

    def _message_to_dict(msg, **_kwargs):
        # In tests we'll stuff plain dicts in here, marked as already-converted.
        if isinstance(msg, dict):
            return msg
        return {"_unknown": True}

    json_format.MessageToDict = _message_to_dict

    class _StubCredentials:
        def __init__(self, *, token=None, refresh_token=None, client_id=None, client_secret=None, token_uri=None):
            self.token = token or "stub-access-token"
            self.refresh_token = refresh_token
            self.client_id = client_id
            self.client_secret = client_secret
            self.token_uri = token_uri

        def refresh(self, _request):
            self.token = "refreshed-stub-token"

    oauth2_credentials.Credentials = _StubCredentials

    class _StubRequest:
        pass

    auth_requests.Request = _StubRequest

    sys.modules.update(
        {
            "google": google,
            "google.ads": google_ads,
            "google.ads.googleads": google_ads_googleads,
            "google.ads.googleads.client": google_ads_client,
            "google.ads.googleads.errors": google_ads_errors,
            "google.protobuf": protobuf,
            "google.protobuf.json_format": json_format,
            "google.oauth2": google_oauth2,
            "google.oauth2.credentials": oauth2_credentials,
            "google.auth": google_auth,
            "google.auth.transport": auth_transport,
            "google.auth.transport.requests": auth_requests,
        }
    )


_install_stubs()

# Now import the module under test (this is the second time test-ga is
# loaded — once via shebang, once via importlib for fresh state).
spec = importlib.util.spec_from_file_location("ga_under_test", BIN_DIR / "ga.py")
ga = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ga)


# -----------------------------------------------------------------------------
# Test harness
# -----------------------------------------------------------------------------

FAIL = 0
PASS_COUNT = 0


def assert_eq(name, expected, actual):
    global FAIL, PASS_COUNT
    if expected == actual:
        print(f"  PASS {name}")
        PASS_COUNT += 1
    else:
        print(f"  FAIL {name}\n    expected: {expected!r}\n    actual:   {actual!r}")
        FAIL += 1


def assert_in(name, needle, haystack):
    global FAIL, PASS_COUNT
    if needle in haystack:
        print(f"  PASS {name}")
        PASS_COUNT += 1
    else:
        print(f"  FAIL {name}\n    needle:   {needle!r}\n    haystack: {haystack!r}")
        FAIL += 1


def assert_raises(name, exc_type, fn):
    global FAIL, PASS_COUNT
    try:
        fn()
    except exc_type:
        print(f"  PASS {name}")
        PASS_COUNT += 1
        return
    except BaseException as e:  # noqa: BLE001
        print(f"  FAIL {name}\n    expected {exc_type.__name__}, got {type(e).__name__}: {e}")
        FAIL += 1
        return
    print(f"  FAIL {name}\n    expected {exc_type.__name__}, function returned cleanly")
    FAIL += 1


print("test-ga.py")

# -----------------------------------------------------------------------------
# Section A: configuration loading
# -----------------------------------------------------------------------------

print("\n[config]")

with tempfile.TemporaryDirectory() as td:
    yaml_path = Path(td) / "google-ads.yaml"
    yaml_path.write_text(
        "developer_token: dev-tok\n"
        "client_id: cid\n"
        "client_secret: csec\n"
        "refresh_token: rtok\n"
        "use_proto_plus: true\n"
    )
    with unittest.mock.patch.object(ga, "CREDENTIALS_FILE", yaml_path):
        creds = ga.load_credentials()
    assert_eq("load_credentials reads developer_token", "dev-tok", creds.get("developer_token"))
    assert_eq("load_credentials reads refresh_token", "rtok", creds.get("refresh_token"))
    assert_eq("load_credentials sets use_proto_plus default", True, creds.get("use_proto_plus"))

# Env-var override
with tempfile.TemporaryDirectory() as td:
    yaml_path = Path(td) / "google-ads.yaml"
    yaml_path.write_text(
        "developer_token: yaml-tok\nclient_id: y\nclient_secret: y\nrefresh_token: y\n"
    )
    with unittest.mock.patch.object(ga, "CREDENTIALS_FILE", yaml_path), \
         unittest.mock.patch.dict(os.environ, {"GOOGLE_ADS_DEVELOPER_TOKEN": "env-tok"}):
        creds = ga.load_credentials()
    assert_eq("env var overrides yaml field", "env-tok", creds.get("developer_token"))

# -----------------------------------------------------------------------------
# Section B: customer ID validation + workspace walk-up
# -----------------------------------------------------------------------------

print("\n[validate_id + workspace]")

assert_eq("validate_id strips dashes", "8191097521", ga.validate_id("819-109-7521", "test"))
assert_eq("validate_id passes plain numeric", "1234567890", ga.validate_id("1234567890", "test"))
assert_raises("validate_id rejects non-numeric (CRLF injection)", SystemExit,
              lambda: ga.validate_id("123\r\nX-Inject: y", "test"))
assert_raises("validate_id rejects path-injection-like value", SystemExit,
              lambda: ga.validate_id("123/../../etc/passwd", "test"))
assert_raises("validate_id rejects letters", SystemExit,
              lambda: ga.validate_id("abc", "test"))

# workspace.json walk-up
with tempfile.TemporaryDirectory() as td:
    deep = Path(td) / "a" / "b" / "c"
    deep.mkdir(parents=True)
    (Path(td) / "a" / "workspace.json").write_text(json.dumps({
        "account": {"customer_id": "1234567890", "manager_customer_id": "9999999999"}
    }))
    cwd = os.getcwd()
    try:
        os.chdir(deep)
        ws = ga.find_workspace()
        assert_eq("find_workspace walks up to find workspace.json", "1234567890",
                  json.loads(ws.read_text())["account"]["customer_id"])
        cust, mgr = ga.resolve_customer_id({})
        assert_eq("resolve_customer_id returns customer_id from workspace", "1234567890", cust)
        assert_eq("resolve_customer_id returns manager_customer_id from workspace", "9999999999", mgr)
    finally:
        os.chdir(cwd)

# -----------------------------------------------------------------------------
# Section C: GoogleAdsException → REST error envelope shape
# -----------------------------------------------------------------------------

print("\n[error envelope shape]")

class _Loc:
    def __init__(self, elements):
        self.field_path_elements = elements

class _Element:
    def __init__(self, name, idx=0):
        self.field_name = name
        self.index = idx

class _ErrorCode:
    def __init__(self, kind, name):
        self._kind = kind
        setattr(self, kind, types.SimpleNamespace(name=name))

    def WhichOneof(self, _name):
        return self._kind

class _GoogleAdsErr:
    def __init__(self, message, kind="authentication_error", name="OAUTH_TOKEN_EXPIRED"):
        self.message = message
        self.error_code = _ErrorCode(kind, name)
        self.location = _Loc([_Element("operations", 2), _Element("create.amount_micros")])

ex = ga.GoogleAdsException(errors=[_GoogleAdsErr("token expired")], code_value=401, code_name="UNAUTHENTICATED", message="auth failure")
envelope = ga.google_ads_exception_to_dict(ex)

assert_eq("error envelope has top-level .error", True, "error" in envelope)
assert_eq("error envelope code", 401, envelope["error"]["code"])
assert_eq("error envelope status", "UNAUTHENTICATED", envelope["error"]["status"])
assert_eq("error envelope details preserves request_id", "req-1",
          envelope["error"]["details"][0]["requestId"])
assert_in("error envelope captures error_code kind", "authentication_error",
          json.dumps(envelope))
assert_in("error envelope captures error name", "OAUTH_TOKEN_EXPIRED",
          json.dumps(envelope))
assert_in("error envelope preserves location.fieldPathElements",
          "operations", json.dumps(envelope))

# -----------------------------------------------------------------------------
# Section D: cmd_query end-to-end (with mocked search_stream)
# -----------------------------------------------------------------------------

print("\n[cmd_query]")


def _make_batch(rows):
    """Mimic SearchGoogleAdsStreamResponse with .results having ._pb on each row."""
    class Row:
        def __init__(self, d):
            self._pb = d
    class Batch:
        def __init__(self, rs):
            self.results = [Row(r) for r in rs]
    return Batch(rows)


with tempfile.TemporaryDirectory() as td:
    yaml_path = Path(td) / "google-ads.yaml"
    yaml_path.write_text(
        "developer_token: dt\nclient_id: ci\nclient_secret: cs\nrefresh_token: rt\nuse_proto_plus: true\n"
    )
    workspace_dir = Path(td) / "ws"
    workspace_dir.mkdir()
    (workspace_dir / "workspace.json").write_text(json.dumps({
        "account": {"customer_id": "1234567890", "manager_customer_id": "9999999999"}
    }))

    fake_service = unittest.mock.MagicMock()
    fake_service.search_stream.return_value = iter([
        _make_batch([{"campaign": {"id": "1"}}, {"campaign": {"id": "2"}}]),
        _make_batch([{"campaign": {"id": "3"}}]),
    ])
    fake_client = unittest.mock.MagicMock()
    fake_client.get_service.return_value = fake_service

    cwd = os.getcwd()
    buf_out = io.StringIO()
    try:
        os.chdir(workspace_dir)
        with unittest.mock.patch.object(ga, "CREDENTIALS_FILE", yaml_path), \
             unittest.mock.patch.object(ga, "build_client", return_value=fake_client), \
             redirect_stdout(buf_out):
            ga.cmd_query("SELECT campaign.id FROM campaign")
    finally:
        os.chdir(cwd)

    out = json.loads(buf_out.getvalue())
    assert_eq("cmd_query merges multi-batch results", 3, len(out["results"]))
    assert_eq("cmd_query first row", "1", out["results"][0]["campaign"]["id"])
    assert_eq("cmd_query third row", "3", out["results"][2]["campaign"]["id"])

    # Verify the service was called with the right customer_id + query
    call_kwargs = fake_service.search_stream.call_args.kwargs
    assert_eq("cmd_query passes correct customer_id", "1234567890", call_kwargs["customer_id"])
    assert_eq("cmd_query passes the GAQL query", "SELECT campaign.id FROM campaign",
              call_kwargs["query"])

# Query with no customer_id → should fail clearly
with tempfile.TemporaryDirectory() as td:
    yaml_path = Path(td) / "google-ads.yaml"
    yaml_path.write_text(
        "developer_token: dt\nclient_id: ci\nclient_secret: cs\nrefresh_token: rt\n"
    )
    cwd = os.getcwd()
    try:
        os.chdir(td)
        with unittest.mock.patch.object(ga, "CREDENTIALS_FILE", yaml_path):
            try:
                ga.cmd_query("SELECT campaign.id FROM campaign")
                FAIL += 1
                print("  FAIL cmd_query without customer_id should exit non-zero")
            except SystemExit as e:
                assert_eq("cmd_query exits non-zero without customer_id", 1, e.code)
    finally:
        os.chdir(cwd)

# Query catches GoogleAdsException and emits {"error": ...}
with tempfile.TemporaryDirectory() as td:
    yaml_path = Path(td) / "google-ads.yaml"
    yaml_path.write_text(
        "developer_token: dt\nclient_id: ci\nclient_secret: cs\nrefresh_token: rt\n"
    )
    workspace_dir = Path(td) / "ws"
    workspace_dir.mkdir()
    (workspace_dir / "workspace.json").write_text(json.dumps({
        "account": {"customer_id": "1234567890"}
    }))

    fake_service = unittest.mock.MagicMock()
    raise_ex = ga.GoogleAdsException(
        errors=[_GoogleAdsErr("INVALID_FIELD: foo")],
        code_value=400, code_name="INVALID_ARGUMENT", message="invalid"
    )
    fake_service.search_stream.side_effect = raise_ex
    fake_client = unittest.mock.MagicMock()
    fake_client.get_service.return_value = fake_service

    buf = io.StringIO()
    cwd = os.getcwd()
    try:
        os.chdir(workspace_dir)
        with unittest.mock.patch.object(ga, "CREDENTIALS_FILE", yaml_path), \
             unittest.mock.patch.object(ga, "build_client", return_value=fake_client), \
             redirect_stdout(buf):
            ga.cmd_query("SELECT bad_field FROM campaign")
    finally:
        os.chdir(cwd)
    out = json.loads(buf.getvalue())
    assert_eq("cmd_query surfaces GoogleAdsException as .error envelope", True, "error" in out)
    assert_eq("cmd_query error envelope code", 400, out["error"]["code"])

# -----------------------------------------------------------------------------
# Section E: cmd_proxy header construction + body forwarding
# -----------------------------------------------------------------------------

print("\n[cmd_proxy]")


class _CapturingResponse:
    def __init__(self, payload=b'{"ok":true}'):
        self._payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_a):
        return False

    def read(self):
        return self._payload


with tempfile.TemporaryDirectory() as td:
    yaml_path = Path(td) / "google-ads.yaml"
    yaml_path.write_text(
        "developer_token: my-dev-tok\nclient_id: ci\nclient_secret: cs\n"
        "refresh_token: rt\nuse_proto_plus: true\n"
    )
    workspace_dir = Path(td) / "ws"
    workspace_dir.mkdir()
    (workspace_dir / "workspace.json").write_text(json.dumps({
        "account": {"customer_id": "1234567890", "manager_customer_id": "9999999999"}
    }))

    captured = {}

    def fake_urlopen(req, timeout=None):
        captured["url"] = req.full_url
        captured["method"] = req.get_method()
        captured["headers"] = dict(req.header_items())
        captured["data"] = req.data
        return _CapturingResponse()

    cwd = os.getcwd()
    buf = io.StringIO()
    try:
        os.chdir(workspace_dir)
        with unittest.mock.patch.object(ga, "CREDENTIALS_FILE", yaml_path), \
             unittest.mock.patch.object(ga.urllib.request, "urlopen", fake_urlopen), \
             redirect_stdout(buf):
            ga.cmd_proxy("POST", "/v23/customers/1234567890/campaignCriteria:mutate", '{"operations":[]}')
    finally:
        os.chdir(cwd)

    assert_eq("cmd_proxy uses correct URL",
              "https://googleads.googleapis.com/v23/customers/1234567890/campaignCriteria:mutate",
              captured["url"])
    assert_eq("cmd_proxy uses given method", "POST", captured["method"])
    assert_in("cmd_proxy attaches developer-token header",
              "my-dev-tok", json.dumps({k.lower(): v for k, v in captured["headers"].items()}))
    assert_in("cmd_proxy attaches login-customer-id from workspace",
              "9999999999", json.dumps({k.lower(): v for k, v in captured["headers"].items()}))
    headers_lower = {k.lower(): v for k, v in captured["headers"].items()}
    assert_in("cmd_proxy attaches Authorization Bearer token",
              "Bearer", headers_lower.get("authorization", ""))
    assert_eq("cmd_proxy forwards JSON body", b'{"operations":[]}', captured["data"])
    assert_in("cmd_proxy emits response body to stdout", '"ok":true', buf.getvalue())

# Proxy refuses paths not starting with /
with tempfile.TemporaryDirectory() as td:
    yaml_path = Path(td) / "google-ads.yaml"
    yaml_path.write_text(
        "developer_token: dt\nclient_id: ci\nclient_secret: cs\nrefresh_token: rt\n"
    )
    cwd = os.getcwd()
    try:
        os.chdir(td)
        with unittest.mock.patch.object(ga, "CREDENTIALS_FILE", yaml_path):
            try:
                ga.cmd_proxy("GET", "v23/customers:listAccessibleCustomers", None)
                FAIL += 1
                print("  FAIL cmd_proxy should reject path without leading /")
            except SystemExit:
                print("  PASS cmd_proxy rejects path without leading /")
                PASS_COUNT += 1
    finally:
        os.chdir(cwd)

# -----------------------------------------------------------------------------

print()
if FAIL:
    print(f"{FAIL} test(s) failed; {PASS_COUNT} passed")
    sys.exit(1)
print(f"all {PASS_COUNT} tests passed")
