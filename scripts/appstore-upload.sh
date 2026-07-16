#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/CarDashboardApp/AppStoreConnect.local.xcconfig"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC2046
  export $(grep -E '^[A-Z_]+' "$ENV_FILE" | grep -v '^//' | xargs)
fi

: "${ASC_APP_APPLE_ID:=f57dd6a9-2ba0-4ef3-a0c7-82deaf2227b8}"
export ASC_APP_APPLE_ID

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_API_ISSUER_ID:-}" || -z "${ASC_API_KEY_PATH:-}" ]]; then
  echo "Missing App Store Connect API credentials."
  echo "1. Copy CarDashboardApp/AppStoreConnect.local.example.xcconfig → AppStoreConnect.local.xcconfig"
  echo "2. Add ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_KEY_PATH (AuthKey .p8 from App Store Connect)"
  echo "3. Register bundle id com.groo.app in Apple Developer + create app in App Store Connect"
  exit 1
fi

if [[ ! -f "$ASC_API_KEY_PATH" ]]; then
  echo "API key file not found: $ASC_API_KEY_PATH"
  exit 1
fi

export ASC_API_KEY_PATH
export ASC_API_KEY_ID
export ASC_API_ISSUER_ID

bundle check >/dev/null 2>&1 || bundle install
bundle exec fastlane ios release
