#!/usr/bin/env python3
"""Stream stdin to stdout with configured secret values replaced."""

from __future__ import annotations

import os
import sys

SECRET_NAMES = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8", "ASC_TEAM_ID")
secrets = [os.environ.get(name, "") for name in SECRET_NAMES]
secrets = sorted((value for value in secrets if value), key=len, reverse=True)

for line in sys.stdin:
    for value in secrets:
        line = line.replace(value, "[REDACTED]")
    sys.stdout.write(line)
    sys.stdout.flush()
