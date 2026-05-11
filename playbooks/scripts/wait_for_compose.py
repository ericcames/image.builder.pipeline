#!/usr/bin/env python3
"""Wait for a Red Hat Image Builder compose to finish.

Replaces the inline `uri:`-based polling in build_cis_image.yml, which
hits an access-token-expiration bug during real (>15 min) RHEL composes
(see issue #4). The Ansible polling task exchanges the offline token
once at the start; access tokens last ~15 minutes; long composes outlive
the token and subsequent polls 401.

This script refreshes the access token on every iteration, polls the
Image Builder API, and exits when the compose reaches a terminal state.
Stdout is a JSON document: {"compose_id", "ami_id", "region", "status"}.

Inputs:
    argv[1]            compose ID (UUID)
    RH_OFFLINE_TOKEN   env var, offline token used to mint access tokens

Exit codes:
    0   compose succeeded; AMI details on stdout
    1   compose failed at Image Builder; reason on stderr
    2   polling timed out without reaching a terminal state
    3   bad input / unrecoverable HTTP error
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SSO_URL = (
    "https://sso.redhat.com/auth/realms/redhat-external/"
    "protocol/openid-connect/token"
)
IMAGE_BUILDER_API = "https://console.redhat.com/api/image-builder/v1"

MAX_ITERATIONS = 60
POLL_INTERVAL_S = 30


def fail(code: int, msg: str) -> "NoReturn":
    print(msg, file=sys.stderr)
    sys.exit(code)


def exchange_token(offline_token: str) -> str:
    body = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "client_id": "cloud-services",
            "refresh_token": offline_token,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        SSO_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as e:
        fail(3, f"SSO token exchange failed: HTTP {e.code} {e.reason}")
    except urllib.error.URLError as e:
        fail(3, f"SSO token exchange failed: {e.reason}")
    token = payload.get("access_token")
    if not token:
        fail(3, "SSO response missing access_token")
    return token


def poll_compose(compose_id: str, access_token: str) -> dict:
    req = urllib.request.Request(
        f"{IMAGE_BUILDER_API}/composes/{compose_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main() -> int:
    if len(sys.argv) != 2:
        fail(3, "usage: wait_for_compose.py <compose-id>")
    compose_id = sys.argv[1]
    offline_token = os.environ.get("RH_OFFLINE_TOKEN", "").strip()
    if not offline_token:
        fail(3, "RH_OFFLINE_TOKEN env var is required")

    for iteration in range(1, MAX_ITERATIONS + 1):
        access_token = exchange_token(offline_token)
        try:
            body = poll_compose(compose_id, access_token)
        except urllib.error.HTTPError as e:
            print(
                f"poll {iteration}/{MAX_ITERATIONS}: HTTP {e.code} {e.reason}",
                file=sys.stderr,
            )
            time.sleep(POLL_INTERVAL_S)
            continue

        status = body.get("image_status", {}).get("status", "unknown")
        print(f"poll {iteration}/{MAX_ITERATIONS}: status={status}", file=sys.stderr)

        if status == "success":
            upload = body["image_status"].get("upload_status", {})
            options = upload.get("options", {})
            ami_id = options.get("ami")
            region = options.get("region")
            if not ami_id:
                fail(3, "compose succeeded but no AMI ID in upload_status")
            print(
                json.dumps(
                    {
                        "compose_id": compose_id,
                        "ami_id": ami_id,
                        "region": region,
                        "status": status,
                    }
                )
            )
            return 0

        if status == "failure":
            fail(1, f"compose failed: {json.dumps(body['image_status'])}")

        time.sleep(POLL_INTERVAL_S)

    return 2


if __name__ == "__main__":
    sys.exit(main())
