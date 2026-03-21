#!/usr/bin/env bash
# OpenClaw helper: Check md2wechat service health
# Usage: ./healthcheck.sh
#
# Environment:
#   MD2WECHAT_URL  Base URL (default: http://localhost:3000)

set -euo pipefail

BASE_URL="${MD2WECHAT_URL:-http://localhost:3000}"

if ! RESPONSE=$(curl -sS --max-time 5 "${BASE_URL}/health" 2>&1); then
  echo '{"status": "unreachable", "error": "Cannot connect to md2wechat at '"${BASE_URL}"': '"${RESPONSE}"'"}'
  exit 1
fi

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
