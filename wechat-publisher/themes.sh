#!/usr/bin/env bash
# OpenClaw helper: List available themes from md2wechat
# Usage: ./themes.sh
#
# Environment:
#   MD2WECHAT_URL      Base URL (default: http://localhost:3000)
#   MD2WECHAT_API_KEY  API key for authentication (optional)

set -euo pipefail

BASE_URL="${MD2WECHAT_URL:-http://localhost:3000}"
API_KEY="${MD2WECHAT_API_KEY:-}"

CURL_ARGS=(-sS "${BASE_URL}/api/themes")
[[ -n "$API_KEY" ]] && CURL_ARGS+=(-H "X-API-Key: ${API_KEY}")

if ! RESPONSE=$(curl "${CURL_ARGS[@]}" 2>&1); then
  echo "Error: Failed to connect to md2wechat at ${BASE_URL}" >&2
  echo "curl error: $RESPONSE" >&2
  exit 1
fi

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
