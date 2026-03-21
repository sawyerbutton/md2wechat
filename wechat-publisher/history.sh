#!/usr/bin/env bash
# OpenClaw helper: Query publish history from md2wechat
# Usage: ./history.sh [--page N] [--size N] [--status draft|published]
#
# Environment:
#   MD2WECHAT_URL      Base URL (default: http://localhost:3000)
#   MD2WECHAT_API_KEY  API key for authentication (optional)

set -euo pipefail

BASE_URL="${MD2WECHAT_URL:-http://localhost:3000}"
API_KEY="${MD2WECHAT_API_KEY:-}"

PAGE="1"
SIZE="10"
STATUS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --page)   PAGE="$2"; shift 2 ;;
    --size)   SIZE="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    *)        echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

URL="${BASE_URL}/api/history?page=${PAGE}&pageSize=${SIZE}"
[[ -n "$STATUS" ]] && URL="${URL}&status=${STATUS}"

CURL_ARGS=(-sS "$URL")
[[ -n "$API_KEY" ]] && CURL_ARGS+=(-H "X-API-Key: ${API_KEY}")

if ! RESPONSE=$(curl "${CURL_ARGS[@]}" 2>&1); then
  echo "Error: Failed to connect to md2wechat at ${BASE_URL}" >&2
  echo "curl error: $RESPONSE" >&2
  exit 1
fi

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
