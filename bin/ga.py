#!/usr/bin/env python3
"""bin/ga.py — Google Ads API helper.

Reimplements the bash bin/ga's two subcommands on top of the official
google-ads-python client. Same CLI surface, same JSON output shape on
success, same {"error": {...}} shape on failure — so skills, bin/apply,
and the agent persona don't change.

Subcommands:
  ga query "<GAQL>"
      → uses GoogleAdsService.search_stream, accumulates rows across
        all batches, emits {"results": [...]} as JSON.

  ga proxy <METHOD> <PATH> [<JSON-BODY>]
      → REST call with auto-refreshed auth headers. The library
        credentials handle OAuth refresh; we attach the developer-token
        and login-customer-id headers from the yaml config.

Auth comes from ~/.config/google-ads-copilot/google-ads.yaml (override
with GOOGLE_ADS_COPILOT_CREDENTIALS_FILE). The yaml is the library's
native format — see Google's docs for the schema.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

# These imports fail loudly if the venv isn't set up — bin/ga the bash
# wrapper catches this case before we get here, but defense in depth.
try:
    import yaml  # type: ignore[import-untyped]
    from google.ads.googleads.client import GoogleAdsClient
    from google.ads.googleads.errors import GoogleAdsException
    from google.protobuf.json_format import MessageToDict
except ModuleNotFoundError as e:
    sys.stderr.write(
        f"ga.py: missing dependency ({e.name}). Run `bin/setup` to "
        "create the venv and install google-ads.\n"
    )
    sys.exit(1)


CREDENTIALS_FILE = Path(
    os.environ.get(
        "GOOGLE_ADS_COPILOT_CREDENTIALS_FILE",
        Path.home() / ".config/google-ads-copilot/google-ads.yaml",
    )
)
API_VERSION = os.environ.get("GOOGLEADS_API_VERSION", "v23")
API_BASE = os.environ.get(
    "GOOGLEADS_API_BASE", "https://googleads.googleapis.com"
)


# ----- workspace + creds glue ------------------------------------------------


def find_workspace() -> Path | None:
    """Walk up from cwd looking for workspace.json. Up to 5 levels."""
    d = Path.cwd().resolve()
    for _ in range(5):
        candidate = d / "workspace.json"
        if candidate.is_file():
            return candidate
        if d.parent == d:
            break
        d = d.parent
    return None


def load_credentials() -> dict[str, Any]:
    """Load yaml credentials. Env vars override individual fields.

    Priority for each field:
      1. GOOGLE_ADS_<UPPER_KEY> env var
      2. yaml file at CREDENTIALS_FILE
      3. error
    """
    creds: dict[str, Any] = {}
    if CREDENTIALS_FILE.is_file():
        try:
            creds = yaml.safe_load(CREDENTIALS_FILE.read_text()) or {}
        except yaml.YAMLError as e:
            die(f"credentials file at {CREDENTIALS_FILE} is not valid yaml: {e}")
    for key in (
        "developer_token",
        "client_id",
        "client_secret",
        "refresh_token",
        "login_customer_id",
    ):
        env_val = os.environ.get(f"GOOGLE_ADS_{key.upper()}")
        if env_val:
            creds[key] = env_val
    creds.setdefault("use_proto_plus", True)
    return creds


def resolve_customer_id(creds: dict[str, Any]) -> tuple[str, str | None]:
    """Returns (customer_id, login_customer_id_for_mcc).

    Resolution order:
      1. workspace.json (.account.customer_id, .account.manager_customer_id)
         — runs bin/validate-workspace first to surface malformed schemas
      2. GA_CUSTOMER_ID / GA_MANAGER_CUSTOMER_ID env vars
      3. login_customer_id from credentials (only used as login header,
         not as the target customer_id)
    """
    ws = find_workspace()
    if ws is not None:
        # Schema-validate first — runs bin/validate-workspace if available.
        # Failures there are clearer than mid-pipeline KeyErrors.
        validator = Path(__file__).parent / "validate-workspace"
        if validator.is_file():
            import subprocess

            result = subprocess.run(
                [sys.executable, str(validator), str(ws)],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                sys.stderr.write(result.stderr)
                sys.exit(1)
        try:
            data = json.loads(ws.read_text())
            customer_id = str(data["account"]["customer_id"])
            mgr = data["account"].get("manager_customer_id") or None
            if mgr:
                mgr = str(mgr)
            return validate_id(customer_id, "customer_id"), (
                validate_id(mgr, "manager_customer_id") if mgr else None
            )
        except (KeyError, json.JSONDecodeError) as e:
            die(f"workspace.json at {ws} is malformed: {e}")
    customer_id = os.environ.get("GA_CUSTOMER_ID", "").strip()
    mgr = os.environ.get("GA_MANAGER_CUSTOMER_ID", "").strip() or None
    if customer_id:
        return validate_id(customer_id, "customer_id"), (
            validate_id(mgr, "manager_customer_id") if mgr else None
        )
    return "", (validate_id(mgr, "manager_customer_id") if mgr else None)


def validate_id(value: str, label: str) -> str:
    """Customer IDs are 10-digit numeric strings (with or without dashes).

    Defense in depth: a value containing CRLF could inject curl headers;
    one containing / could alter URL paths.
    """
    cleaned = value.replace("-", "")
    if not cleaned.isdigit():
        die(f"invalid {label} (must be numeric): {value}")
    return cleaned


def build_client(creds: dict[str, Any], login_customer_id: str | None):
    """Construct a GoogleAdsClient from the merged credentials dict.

    Sets login_customer_id on the client only if provided — for solo
    accounts (no MCC) this header must be absent.
    """
    config = dict(creds)
    if login_customer_id:
        config["login_customer_id"] = login_customer_id
    elif "login_customer_id" in config and not config["login_customer_id"]:
        del config["login_customer_id"]
    for required in ("developer_token", "client_id", "client_secret", "refresh_token"):
        if not config.get(required):
            die(
                f"missing credential: {required}. Set in {CREDENTIALS_FILE} "
                f"or via GOOGLE_ADS_{required.upper()}."
            )
    try:
        return GoogleAdsClient.load_from_dict(config, version=API_VERSION)
    except Exception as e:  # noqa: BLE001 — surface library construction errors
        die(f"failed to construct GoogleAdsClient: {e}")


# ----- error formatting ------------------------------------------------------


def google_ads_exception_to_dict(ex: GoogleAdsException) -> dict[str, Any]:
    """Render a GoogleAdsException in the same shape Google's REST API
    would return on error, so existing .error consumers (skills, bin/apply)
    don't need to change."""
    errors = []
    for err in ex.failure.errors:
        d: dict[str, Any] = {"message": err.message}
        # The error_code is a oneof — find which code is set
        which = err.error_code.WhichOneof("error_code")
        if which:
            d["errorCode"] = {which: getattr(err.error_code, which).name}
        if err.location and err.location.field_path_elements:
            d["location"] = {
                "fieldPathElements": [
                    {"fieldName": p.field_name, **({"index": p.index} if p.index else {})}
                    for p in err.location.field_path_elements
                ]
            }
        errors.append(d)
    return {
        "error": {
            "code": ex.error.code().value if hasattr(ex.error, "code") else 0,
            "message": ex.error.message() if hasattr(ex.error, "message") else str(ex),
            "status": ex.error.code().name if hasattr(ex.error, "code") else "UNKNOWN",
            "details": [
                {
                    "@type": "type.googleapis.com/google.ads.googleads."
                    + f"{API_VERSION}.errors.GoogleAdsFailure",
                    "errors": errors,
                    "requestId": ex.request_id,
                }
            ],
        }
    }


def die(msg: str) -> "None":
    sys.stderr.write(f"ga: {msg}\n")
    sys.exit(1)


# ----- query -----------------------------------------------------------------


def cmd_query(query: str) -> None:
    """Run a GAQL query via search_stream, accumulate all batches into a
    single {"results": [...]} JSON object on stdout."""
    if not query:
        die("query: missing GAQL string")

    creds = load_credentials()
    customer_id, login_customer_id = resolve_customer_id(creds)
    if not customer_id:
        die("query: customer_id required — cd into a workspace, or set GA_CUSTOMER_ID=<id>")

    client = build_client(creds, login_customer_id)
    ga_service = client.get_service("GoogleAdsService")

    rows: list[dict[str, Any]] = []
    try:
        stream = ga_service.search_stream(customer_id=customer_id, query=query)
        for batch in stream:
            for row in batch.results:
                rows.append(MessageToDict(row._pb, preserving_proto_field_name=True))
    except GoogleAdsException as ex:
        sys.stdout.write(json.dumps(google_ads_exception_to_dict(ex)))
        sys.stdout.write("\n")
        return

    sys.stdout.write(json.dumps({"results": rows}))
    sys.stdout.write("\n")


# ----- proxy -----------------------------------------------------------------


def cmd_proxy(method: str, path: str, body: str | None) -> None:
    """Send an arbitrary REST call to the Google Ads API.

    Uses the library's credentials to obtain an access token (auto-refreshed),
    attaches developer-token + login-customer-id headers from the config,
    sends the request, and emits the raw response on stdout.
    """
    if not method or not path:
        die("proxy: need METHOD and PATH")
    if not path.startswith("/"):
        die(f"proxy: PATH must start with / (got: {path})")

    creds = load_credentials()
    _, login_customer_id = resolve_customer_id(creds)

    # Use google.oauth2.credentials directly so we don't need a customer_id
    # for proxy calls (e.g. /v23/customers:listAccessibleCustomers needs no id).
    try:
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import Request
    except ModuleNotFoundError as e:
        die(f"proxy: missing google-auth ({e.name}). Re-run bin/setup.")

    oauth_creds = Credentials(
        token=None,
        refresh_token=creds["refresh_token"],
        client_id=creds["client_id"],
        client_secret=creds["client_secret"],
        token_uri="https://oauth2.googleapis.com/token",
    )
    oauth_creds.refresh(Request())

    headers = {
        "Authorization": f"Bearer {oauth_creds.token}",
        "developer-token": creds["developer_token"],
        "Content-Type": "application/json",
    }
    if login_customer_id:
        headers["login-customer-id"] = login_customer_id

    url = f"{API_BASE}{path}"
    data = body.encode("utf-8") if body and body != "null" else None
    req = urllib.request.Request(url=url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310 — google-only
            sys.stdout.write(resp.read().decode("utf-8"))
            sys.stdout.write("\n")
    except urllib.error.HTTPError as e:
        # Surface the body so the caller's .error consumers see Google's payload.
        sys.stdout.write(e.read().decode("utf-8", errors="replace"))
        sys.stdout.write("\n")
    except urllib.error.URLError as e:
        die(f"proxy: network error: {e}")


# ----- main ------------------------------------------------------------------


USAGE = """\
Usage: ga <subcommand> [args]

Subcommands:
  query "<GAQL>"                        Run a GAQL search against the bound workspace
  proxy <METHOD> <PATH> [<JSON-BODY>]   Arbitrary REST call (PATH starts with /)

Examples:
  ga query "SELECT campaign.id, campaign.name FROM campaign LIMIT 5"
  ga proxy GET /v23/customers:listAccessibleCustomers
  ga proxy POST /v23/customers/8191097521/campaignCriteria:mutate '{"operations":[...]}'
"""


def main(argv: list[str]) -> None:
    if len(argv) < 2 or argv[1] in ("-h", "--help", "help", ""):
        sys.stderr.write(USAGE)
        sys.exit(64)
    sub = argv[1]
    if sub == "query":
        cmd_query(argv[2] if len(argv) > 2 else "")
    elif sub == "proxy":
        cmd_proxy(
            argv[2] if len(argv) > 2 else "",
            argv[3] if len(argv) > 3 else "",
            argv[4] if len(argv) > 4 else None,
        )
    else:
        sys.stderr.write(f"ga: unknown subcommand: {sub}\n")
        sys.stderr.write(USAGE)
        sys.exit(64)


if __name__ == "__main__":
    main(sys.argv)
