# wechat-publisher

Publish Markdown articles to WeChat Official Account (微信公众号) via the [md2wechat](https://github.com/tenisinfinite/md2wechat) API service.

## Prerequisites

- A running md2wechat instance (e.g., `http://localhost:3000`)
- Set environment variables before using this skill:
  - `MD2WECHAT_URL`: Base URL of the md2wechat service (default: `http://localhost:3000`)
  - `MD2WECHAT_API_KEY`: API key for authentication (optional, depends on server config)

## Tools

### publish_article

Publish a Markdown file to WeChat Official Account as a draft.

**When to use**: When the user asks to publish an article, post to WeChat, send a markdown file to their WeChat account, or create a WeChat draft.

**How to use**:

```bash
# Basic publish
curl -X POST "${MD2WECHAT_URL}/api/publish" \
  -H "X-API-Key: ${MD2WECHAT_API_KEY}" \
  -F "article=@/path/to/article.md"

# Full publish with all options
curl -X POST "${MD2WECHAT_URL}/api/publish" \
  -H "X-API-Key: ${MD2WECHAT_API_KEY}" \
  -F "article=@/path/to/article.md" \
  -F "author=AuthorName" \
  -F "theme=blue" \
  -F "digest=Article summary text" \
  -F "enableComment=true" \
  -F "coverStrategy=sharp" \
  -F "cover=@/path/to/cover.jpg" \
  -F "images[]=@/path/to/image1.png" \
  -F "images[]=@/path/to/image2.png"
```

**Parameters**:
- `article` (file, required): The Markdown (.md) file to publish
- `author` (string, optional): Author name
- `theme` (string, optional): Theme name — use `list_themes` to see available options
- `digest` (string, optional): Article summary for WeChat (max 120 characters)
- `enableComment` (string, optional): "true" or "false" to enable comments
- `coverStrategy` (string, optional): "sharp" (generated) or "ai" (AI-generated cover)
- `coverPrompt` (string, optional): Custom prompt for AI cover generation
- `cover` (file, optional): Custom cover image file
- `images[]` (files, optional): Additional image files referenced in the article

**Success response**:
```json
{
  "success": true,
  "data": {
    "publishId": "uuid",
    "mediaId": "weixin-media-id",
    "title": "Article Title",
    "author": "Author",
    "coverUrl": "https://mmbiz.qpic.cn/...",
    "coverStrategy": "sharp",
    "publishedAt": "2026-03-22T10:30:00.000Z"
  }
}
```

**Error response**:
```json
{
  "success": false,
  "error": { "message": "Error description", "code": "ERROR_CODE", "step": "step_name" }
}
```

### list_themes

List all available CSS themes for article rendering.

**When to use**: When the user asks what themes are available, wants to see styling options, or before publishing if no theme is specified.

```bash
curl -s "${MD2WECHAT_URL}/api/themes" \
  -H "X-API-Key: ${MD2WECHAT_API_KEY}"
```

**Response**: Array of theme names, e.g., `["default", "black", "blue", "brown", "green", "orange", "red", "yellow"]`

### get_history

Query publish history records.

**When to use**: When the user asks about past publications, wants to check publish status, or review what has been published.

```bash
# List recent publishes (page 1, 10 per page)
curl -s "${MD2WECHAT_URL}/api/history?page=1&pageSize=10" \
  -H "X-API-Key: ${MD2WECHAT_API_KEY}"

# Filter by status
curl -s "${MD2WECHAT_URL}/api/history?status=draft" \
  -H "X-API-Key: ${MD2WECHAT_API_KEY}"
```

**Parameters**:
- `page` (number, optional): Page number (default: 1)
- `pageSize` (number, optional): Records per page (default: 20)
- `status` (string, optional): Filter by status — "draft" or "published"

**Response**:
```json
{
  "items": [
    {
      "id": "uuid",
      "title": "Article Title",
      "author": "Author",
      "status": "draft",
      "theme": "blue",
      "cover_strategy": "sharp",
      "created_at": "2026-03-22T10:30:00.000Z"
    }
  ],
  "total": 42,
  "page": 1,
  "pageSize": 20
}
```

### get_config

Get current md2wechat service configuration.

**When to use**: When the user wants to check the service status, verify configuration, or troubleshoot connectivity.

```bash
curl -s "${MD2WECHAT_URL}/api/config" \
  -H "X-API-Key: ${MD2WECHAT_API_KEY}"
```

**Response**:
```json
{
  "appid": "****abcd",
  "defaultAuthor": "tenisinfinite",
  "defaultTheme": "default",
  "defaultCoverStrategy": "sharp",
  "aiCoverConfigured": false,
  "webhookConfigured": true
}
```

### check_health

Check if the md2wechat service is running and healthy.

**When to use**: Before publishing, or when diagnosing connectivity issues.

```bash
curl -s "${MD2WECHAT_URL}/health"
```

**Response**:
```json
{
  "status": "ok",
  "version": "1.0.0",
  "wxConfigured": true,
  "tokenCached": false,
  "dbConnected": true,
  "aiCoverAvailable": false
}
```

## Markdown Front Matter

Articles can include YAML front matter for metadata:

```markdown
---
title: My Article Title
author: Author Name
digest: A brief summary of the article
theme: blue
cover: https://example.com/cover.jpg
enableComment: true
---

# Article Content Here

Your markdown content...
```

Front matter values are used as defaults but can be overridden by the publish request parameters.

## Common Workflows

### Quick Publish
User says: "publish my-article.md to WeChat"
1. Call `check_health` to verify service is up
2. Call `publish_article` with the file

### Publish with Theme Selection
User says: "publish article.md with a nice blue theme"
1. Call `publish_article` with `theme=blue`

### Review and Publish
User says: "what articles have I published recently?"
1. Call `get_history` to show recent records

### Batch Publish
User says: "publish all markdown files in this folder"
1. Find all .md files in the specified folder
2. Call `publish_article` for each file sequentially
3. Report results summary

### Scheduled Publish
User says: "publish this article every Monday at 9am"
1. Set up an OpenClaw cron job: `openclaw cron add "0 9 * * 1" "publish /path/to/article.md to WeChat"`

## Error Handling

- If health check fails: inform user the md2wechat service may be down
- If publish fails with auth error: remind user to set `MD2WECHAT_API_KEY`
- If publish fails with WeChat API error: show the error details from the response
- If file not found: ask user to provide the correct file path

## Tips

- The digest (summary) is auto-generated from H2 headings if not provided
- Cover images are auto-generated using the Sharp strategy if not provided
- Images referenced in the markdown are automatically uploaded to WeChat
- The service creates WeChat **drafts** — the user still needs to manually publish from the WeChat admin panel
