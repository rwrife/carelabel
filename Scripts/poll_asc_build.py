#!/usr/bin/env python3
"""Poll App Store Connect build processing until VALID, using only stdlib/openssl."""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

# App Store Connect's Build.Attributes.processingState terminal success is
# VALID. COMPLETE is retained for compatibility with older/mocked payloads.
SUCCESS_PROCESSING_STATES = {"VALID", "COMPLETE"}
FAILURE_PROCESSING_STATES = {"FAILED", "INVALID"}


def processing_state_result(state: str) -> str:
    """Classify an ASC build processing state as success/failure/pending."""
    if state in SUCCESS_PROCESSING_STATES:
        return "success"
    if state in FAILURE_PROCESSING_STATES:
        return "failure"
    return "pending"



def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def create_token(issuer: str, key_id: str, key_path: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": issuer,
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    encoded_header = b64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    encoded_payload = b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{encoded_header}.{encoded_payload}".encode("ascii")

    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    raw_signature = proc.stdout

    # Convert ASN.1 DER ECDSA signature to IEEE P1363 (64-byte r || s)
    signature_bytes = der_to_raw(raw_signature)
    return f"{encoded_header}.{encoded_payload}.{b64url(signature_bytes)}"


def der_to_raw(der: bytes) -> bytes:
    # Minimal ASN.1 DER sequence parser for two ECDSA integers
    if der[0] != 0x30:
        raise ValueError("Invalid DER signature")
    offset = 2
    if der[1] & 0x80:
        length_bytes = der[1] & 0x7F
        offset = 2 + length_bytes

    def read_int(pos: int) -> tuple[bytes, int]:
        if der[pos] != 0x02:
            raise ValueError("Expected integer tag")
        length = der[pos + 1]
        start = pos + 2
        value = der[start : start + length]
        if len(value) > 32 and value[0] == 0x00:
            value = value[1:]
        value = value.rjust(32, b"\x00")
        return value, start + length

    r, next_pos = read_int(offset)
    s, _ = read_int(next_pos)
    return r + s


def get_json(url: str, token: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "CareLabel-Release/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    key_path = os.environ.get("KEY_PATH") or sys.argv[1]
    issuer = os.environ.get("ASC_ISSUER_ID") or sys.argv[2]
    key_id = os.environ.get("ASC_KEY_ID") or sys.argv[3]
    bundle_id = os.environ.get("APP_BUNDLE_ID", "com.infinityball.carelabel")
    # The CFBundleVersion this workflow set with CURRENT_PROJECT_VERSION.
    # Without this, polling "the latest build" can match a DIFFERENT
    # upload (a concurrent manual upload, or a stale previous run) and
    # falsely report success for a build this run never produced.
    expected_build_number = os.environ.get("BUILD_NUMBER")
    if not expected_build_number:
        print("BUILD_NUMBER not set; refusing to poll without an expected build number", file=sys.stderr)
        return 1

    token = create_token(issuer, key_id, key_path)
    apps = get_json(
        f"https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={bundle_id}",
        token,
    )
    data = apps.get("data", [])
    if not data:
        print(f"No app found in ASC for bundle id {bundle_id}", file=sys.stderr)
        return 1
    app_id = data[0]["id"]
    print(f"Located ASC app {bundle_id} (id={app_id}); expecting build number {expected_build_number}")

    attempts = 20
    sleep_seconds = 30
    for attempt in range(1, attempts + 1):
        # Refresh token periodically if loop runs long
        token = create_token(issuer, key_id, key_path)
        payload = get_json(
            f"https://api.appstoreconnect.apple.com/v1/builds"
            f"?filter[app]={app_id}&filter[version]={expected_build_number}"
            f"&sort=-uploadedDate&limit=1",
            token,
        )
        builds = payload.get("data", [])
        if not builds:
            print(f"Attempt {attempt}/{attempts}: build {expected_build_number} not visible yet")
        else:
            build = builds[0]
            attrs = build.get("attributes", {})
            state = attrs.get("processingState", "UNKNOWN")
            number = attrs.get("version", "?")
            uploaded = attrs.get("uploadedDate", "?")
            if number != expected_build_number:
                # Defense in depth: even if the filter above changes
                # behavior on Apple's side, never accept a mismatched build.
                print(
                    f"Attempt {attempt}/{attempts}: ASC returned build {number}, "
                    f"expected {expected_build_number}; ignoring"
                )
            else:
                print(
                    f"Attempt {attempt}/{attempts}: build {number} (id={build['id']}) "
                    f"state={state} uploaded={uploaded}"
                )
                result = processing_state_result(state)
                if result == "success":
                    print("App Store Connect processing complete.")
                    out_path = os.environ.get("GITHUB_OUTPUT")
                    if out_path:
                        with open(out_path, "a", encoding="utf-8") as handle:
                            handle.write(f"build_id={build['id']}\n")
                            handle.write(f"processing_state={state}\n")
                            handle.write(f"build_number={number}\n")
                    return 0
                if result == "failure":
                    print(f"Build failed processing with state: {state}", file=sys.stderr)
                    return 2
        time.sleep(sleep_seconds)

    print(
        f"Timed out waiting for ASC build {expected_build_number} processing to complete",
        file=sys.stderr,
    )
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
