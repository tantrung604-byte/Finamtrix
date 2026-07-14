#!/usr/bin/env bash
# Run FinMatrix with the Anthropic (Claude) key injected at build time.
# Reads the key from the ANTHROPIC_API_KEY env var so the secret never lands
# in source control. Extra args are forwarded to `flutter run`.
#
# Usage:
#   export ANTHROPIC_API_KEY='sk-ant-...'
#   ./scripts/run-with-key.sh -d chrome
set -euo pipefail

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ANTHROPIC_API_KEY is not set. Run: export ANTHROPIC_API_KEY='sk-ant-...'" >&2
  exit 1
fi

# cd to project root (parent of this script's dir).
cd "$(dirname "$0")/.."

echo "Launching FinMatrix with Anthropic key (…${ANTHROPIC_API_KEY: -6})"
exec flutter run --dart-define=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" "$@"

