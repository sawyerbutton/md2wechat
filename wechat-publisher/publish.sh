#!/usr/bin/env bash
# OpenClaw helper: Publish a Markdown article to WeChat via md2wechat
# Usage: ./publish.sh <article.md> [options]
#
# Options:
#   --author <name>          Author name
#   --theme <name>           Theme name (default, blue, black, etc.)
#   --digest <text>          Article summary (max 120 chars)
#   --cover <file>           Cover image file path
#   --cover-strategy <type>  Cover strategy: sharp (default) or ai
#   --cover-prompt <text>    AI cover generation prompt
#   --enable-comment         Enable comments on the article
#   --images <file1,file2>   Comma-separated image file paths
#   --webhook-url <url>      Custom webhook URL for this publish
#
# Environment:
#   MD2WECHAT_URL      Base URL (default: http://localhost:3000)
#   MD2WECHAT_API_KEY  API key for authentication (optional)

set -euo pipefail

BASE_URL="${MD2WECHAT_URL:-http://localhost:3000}"
API_KEY="${MD2WECHAT_API_KEY:-}"

# Parse arguments
ARTICLE=""
AUTHOR=""
THEME=""
DIGEST=""
COVER=""
COVER_STRATEGY=""
COVER_PROMPT=""
ENABLE_COMMENT=""
IMAGES=""
WEBHOOK_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --author)       AUTHOR="$2"; shift 2 ;;
    --theme)        THEME="$2"; shift 2 ;;
    --digest)       DIGEST="$2"; shift 2 ;;
    --cover)        COVER="$2"; shift 2 ;;
    --cover-strategy) COVER_STRATEGY="$2"; shift 2 ;;
    --cover-prompt) COVER_PROMPT="$2"; shift 2 ;;
    --enable-comment) ENABLE_COMMENT="true"; shift ;;
    --images)       IMAGES="$2"; shift 2 ;;
    --webhook-url)  WEBHOOK_URL="$2"; shift 2 ;;
    -*)             echo "Unknown option: $1" >&2; exit 1 ;;
    *)              ARTICLE="$1"; shift ;;
  esac
done

if [[ -z "$ARTICLE" ]]; then
  echo "Error: Article file path is required" >&2
  echo "Usage: $0 <article.md> [options]" >&2
  exit 1
fi

if [[ ! -f "$ARTICLE" ]]; then
  echo "Error: File not found: $ARTICLE" >&2
  exit 1
fi

# Build curl command
CURL_ARGS=(-X POST "${BASE_URL}/api/publish")

if [[ -n "$API_KEY" ]]; then
  CURL_ARGS+=(-H "X-API-Key: ${API_KEY}")
fi

CURL_ARGS+=(-F "article=@${ARTICLE}")

[[ -n "$AUTHOR" ]]         && CURL_ARGS+=(-F "author=${AUTHOR}")
[[ -n "$THEME" ]]          && CURL_ARGS+=(-F "theme=${THEME}")
[[ -n "$DIGEST" ]]         && CURL_ARGS+=(-F "digest=${DIGEST}")
[[ -n "$COVER_STRATEGY" ]] && CURL_ARGS+=(-F "coverStrategy=${COVER_STRATEGY}")
[[ -n "$COVER_PROMPT" ]]   && CURL_ARGS+=(-F "coverPrompt=${COVER_PROMPT}")
[[ -n "$ENABLE_COMMENT" ]] && CURL_ARGS+=(-F "enableComment=true")
[[ -n "$WEBHOOK_URL" ]]    && CURL_ARGS+=(-F "webhookUrl=${WEBHOOK_URL}")

if [[ -n "$COVER" ]]; then
  if [[ ! -f "$COVER" ]]; then
    echo "Error: Cover file not found: $COVER" >&2
    exit 1
  fi
  CURL_ARGS+=(-F "cover=@${COVER}")
fi

if [[ -n "$IMAGES" ]]; then
  IFS=',' read -ra IMG_ARRAY <<< "$IMAGES"
  for img in "${IMG_ARRAY[@]}"; do
    img=$(echo "$img" | xargs)  # trim whitespace
    if [[ ! -f "$img" ]]; then
      echo "Warning: Image file not found, skipping: $img" >&2
      continue
    fi
    CURL_ARGS+=(-F "images[]=@${img}")
  done
fi

# Execute (-sS: silent but show errors)
if ! RESPONSE=$(curl -sS "${CURL_ARGS[@]}" 2>&1); then
  echo "Error: Failed to connect to md2wechat at ${BASE_URL}" >&2
  echo "curl error: $RESPONSE" >&2
  echo "Make sure the service is running and MD2WECHAT_URL is correct." >&2
  exit 1
fi

# Output response
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
