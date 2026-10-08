#!/usr/bin/env python3
"""Read App Store submission readiness without publishing reviewer credentials."""

import json
import os
import subprocess
from pathlib import Path


APP_ID = os.environ["ASC_APP_ID"]
BUILD_ID = "3a3bddd5-f1ff-4c98-a5de-4a55c9764eb0"


def redact(value):
    if isinstance(value, dict):
        return {
            key: ({"configured": bool(item)} if any(
                marker in key.lower() for marker in (
                    "password", "demoaccountname", "contactphone", "contactfirstname",
                    "contactlastname", "reviewnotes", "notes",
                )
            ) else redact(item))
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def read(*args):
    result = subprocess.run(
        ["asc", *args, "--output", "json"],
        capture_output=True, text=True, timeout=120,
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        # Keep unexpected output out of the public report and logs.
        payload = {"responseUnavailable": True}
    return {"exitCode": result.returncode, "response": redact(payload)}


def main():
    report = {
        "appId": APP_ID,
        "targetVersion": "1.0",
        "targetBuildId": BUILD_ID,
        "build": read("builds", "info", "--build-id", BUILD_ID),
        "version": read("versions", "view", "--app", APP_ID, "--version", "1.0",
                        "--platform", "IOS", "--include", "build,appStoreReviewDetail"),
        "validation": read("validate", "--app", APP_ID, "--version", "1.0",
                           "--platform", "IOS", "--check-urls"),
        "localizations": read("localizations", "list", "--app", APP_ID,
                              "--version", "1.0", "--platform", "IOS", "--paginate"),
        "screenshots": read("screenshots", "list", "--app", APP_ID,
                            "--version", "1.0"),
        "availability": read("pricing", "availability", "territory-availabilities",
                             "--availability", APP_ID, "--paginate"),
        "pricing": read("pricing", "current", "--app", APP_ID, "--all-territories"),
    }
    output = Path("build/app-store-review-readiness.json")
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    for key, item in report.items():
        if isinstance(item, dict) and "exitCode" in item:
            print(f"{key}: command exit code {item['exitCode']}; sanitized report saved")


if __name__ == "__main__":
    main()
