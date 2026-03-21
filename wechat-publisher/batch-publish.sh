#!/usr/bin/env bash
# OpenClaw helper: Batch publish all Markdown files in a directory
# Usage: ./batch-publish.sh <directory> [options]
#
# Options are passed through to publish.sh (--author, --theme, etc.)
#
# Environment:
#   MD2WECHAT_URL      Base URL (default: http://localhost:3000)
#   MD2WECHAT_API_KEY  API key for authentication (optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <directory> [publish options...]" >&2
  exit 1
fi

DIR="$1"
shift

if [[ ! -d "$DIR" ]]; then
  echo "Error: Directory not found: $DIR" >&2
  exit 1
fi

# Find all .md files
MD_FILES=()
while IFS= read -r -d '' file; do
  MD_FILES+=("$file")
done < <(find "$DIR" -maxdepth 1 -name "*.md" -type f -print0 | sort -z)

if [[ ${#MD_FILES[@]} -eq 0 ]]; then
  echo "No Markdown files found in: $DIR"
  exit 0
fi

echo "Found ${#MD_FILES[@]} Markdown file(s) to publish:"
printf "  - %s\n" "${MD_FILES[@]}"
echo ""

SUCCESS=0
FAILED=0

for file in "${MD_FILES[@]}"; do
  echo "--- Publishing: $(basename "$file") ---"
  if "${SCRIPT_DIR}/publish.sh" "$file" "$@"; then
    SUCCESS=$((SUCCESS + 1))
  else
    FAILED=$((FAILED + 1))
    echo "FAILED: $file" >&2
  fi
  echo ""
  # Brief pause to avoid rate limiting
  sleep 2
done

echo "=== Batch Complete ==="
echo "Success: $SUCCESS / $((SUCCESS + FAILED))"
[[ $FAILED -gt 0 ]] && echo "Failed: $FAILED" >&2
if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
