#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"
curl --fail --silent --show-error "${BASE_URL}/health"
printf '\n'
curl --fail --silent --show-error "${BASE_URL}/"
printf '\n'
# This checks basic access only. Capture and explain additional deployment,
# replica-replacement, and troubleshooting evidence for your submission.
