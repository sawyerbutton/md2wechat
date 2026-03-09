# md2wechat — 项目规格文档

> 面向 Claude Code 的工程实施文档  
> 项目：`github.com/tenisinfinite/md2wechat`  
> 定位：开源的 Markdown → 微信公众号草稿箱 HTTP 微服务

---

## 一、项目定位与设计原则

### 1.1 一句话定位

`md2wechat` 是一个以 Markdown 为标准输入契约、以微信公众号草稿箱为输出目标的开源 HTTP 微服务。它不关心内容从哪里来，只关心把内容处理好并送达。

### 1.2 核心设计原则

**标准输入契约**：服务只接受 Markdown。上游内容无论来自 Claude、Notion、飞书还是人工编写，统一由上游转换为 Markdown 后再调用本服务。服务本身不承担内容来源适配的职责。

**职责单一**：本服务只做"Markdown 处理 → 微信发布"这一件事，做到最好。

**开箱即用**：默认配置零额外依赖（SQLite），一条 `docker-compose up` 完成部署。

**可插拔扩展**：核心 Pipeline 的每个关键节点都设计了扩展点，不需要 fork 代码即可定制行为。

**开源友好**：配置清晰，文档完整，部署成本低，易于社区贡献。

### 1.3 明确的边界

| 在范围内 | 不在范围内 |
|---------|-----------|
| Markdown → 微信兼容 HTML | Notion / 飞书文档解析 |
| 图片上传到微信图床 | 批量投稿 / 定时发布 |
| 封面生成（sharp 合成 / AI 生图） | 微信发布后的"点击发布"自动化 |
| 发布记录持久化 | 多平台输出（知乎、头条等） |
| Webhook 回调通知 | 内容审核流 |
| 自定义主题包 | — |

---

## 二、架构总览

### 2.1 系统架构图

```
上游（任意来源）
  Claude / n8n / 脚本 / 人工
         │
         │ POST /api/publish
         │ multipart/form-data
         ▼
┌─────────────────────────────────────┐
│           md2wechat Service          │
│                                     │
│  ┌──────────────────────────────┐   │
│  │         HTTP Layer           │   │
│  │  Fastify + @fastify/multipart│   │
│  └────────────┬─────────────────┘   │
│               │                     │
│  ┌────────────▼─────────────────┐   │
│  │       Pipeline Service       │   │
│  │  parse → render → fix →      │   │
│  │  cover → upload → draft      │   │
│  └────────────┬─────────────────┘   │
│               │                     │
│  ┌────────────▼─────────────────┐   │
│  │          Core Layer          │   │
│  │  parser / converter / fixer  │   │
│  │  cover / wechat              │   │
│  └────────────┬─────────────────┘   │
│               │                     │
│  ┌────────────▼─────────────────┐   │
│  │       Database Layer         │   │
│  │  SQLite（默认）/ PostgreSQL  │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
         │                  │
         ▼                  ▼
  微信公众号草稿箱      Webhook 回调
                      （Slack / n8n / 任意）
```

### 2.2 技术选型

| 层次 | 选型 | 理由 |
|------|------|------|
| 运行时 | Node.js 20 LTS | 与依赖栈兼容 |
| HTTP 框架 | Fastify | 性能好，multipart 成熟，Pino 内置 |
| Markdown 渲染 | markdown-it + 插件体系 | 可扩展，生态成熟 |
| 代码高亮 | highlight.js | 与原参考实现一致 |
| CSS 内联 | @css-inline/css-inline | Rust WASM，性能最好 |
| HTML 操作 | cheerio | 轻量，类 jQuery |
| 封面合成 | sharp | 无需 Cairo，Alpine 兼容 |
| AI 封面 | NanoBanana Pro API | 可选，同步返回，与 sharp 并存 |
| 微信 API | 自有 WechatClient | 内存 token 缓存 |
| 数据库（默认） | SQLite via better-sqlite3 | 零依赖，开箱即用 |
| 数据库（可选） | PostgreSQL via pg | 通过 DATABASE_URL 切换 |
| ORM | Kysely | 轻量 query builder，同时支持 SQLite 和 PostgreSQL |
| 容器化 | Docker + docker-compose | 标准化部署 |

---

## 三、可插拔与可配置设计

这是整个架构最重要的章节。每个扩展点都有明确的接口契约，用户不需要修改源码即可定制行为。

### 3.1 Markdown 插件扩展

`markdown-it` 的插件通过配置文件注册，而不是硬编码在源码里。

**插件配置文件**：`config/markdown-plugins.js`（容器内挂载）

```javascript
// config/markdown-plugins.js
// 用户可以在这里注册任意 markdown-it 插件
module.exports = [
  // 示例：注册自定义容器语法
  // [require('markdown-it-container'), 'tip', { /* options */ }],
  // [require('markdown-it-footnote')],
];
```

**加载逻辑**（在 `core/converter.ts` 中）：

```typescript
// 启动时加载插件配置
const pluginConfigPath = path.join(CONFIG_DIR, 'markdown-plugins.js');
if (fs.existsSync(pluginConfigPath)) {
  const plugins = require(pluginConfigPath);
  plugins.forEach(([plugin, ...args]) => md.use(plugin, ...args));
}
```

**Docker 挂载方式**：

```yaml
volumes:
  - ./config:/app/config   # 用户在宿主机的 config/ 目录下放配置文件
```

### 3.2 自定义主题包

主题包是一个目录，包含 CSS 文件和可选的兼容性 CSS 覆盖。用户可以把自己的主题包挂载进容器，无需修改源码。

**主题包结构**：

```
my-theme/
├── theme.css          # 必须：主题样式（对应内置的 blue.css 等）
├── compat.css         # 可选：覆盖微信兼容性 CSS 的某些部分
└── theme.json         # 必须：主题元数据
```

**theme.json 格式**：

```json
{
  "name": "tenisinfinite",
  "displayName": "Tenisinfinite Brand",
  "version": "1.0.0",
  "compatOverrides": {
    "highlight": true,
    "blockquote": false,
    "table": false,
    "codeBlock": false,
    "math": false,
    "layout": false
  }
}
```

`compatOverrides` 中为 `true` 的字段，服务会从 `compat.css` 中读取覆盖内容替换默认兼容性 CSS；为 `false` 的字段则使用内置默认值。

**Docker 挂载方式**：

```yaml
volumes:
  - ./my-theme:/app/themes/my-theme   # 挂载自定义主题
```

**使用方式**：请求时指定 `theme: "my-theme"`，服务优先在 `/app/themes/` 目录下查找，找不到再查内置主题。

**`core/css/compat.ts` 结构**：

```typescript
export interface CompatCssConfig {
  highlight: string;   // 原 HIGHLIGHT_INLINE_CSS
  blockquote: string;  // 原 WECHAT_BLOCKQUOTE_INLINE_CSS
  table: string;       // 原 WECHAT_TABLE_INLINE_CSS
  codeBlock: string;   // 原 WECHAT_CODE_BLOCK_INLINE_CSS
  math: string;        // 原 WECHAT_MATH_INLINE_CSS
  layout: string;      // 原 WECHAT_LAYOUT_INLINE_CSS
}

export function getDefaultCompatCss(): CompatCssConfig
export function loadThemeCompatOverrides(themeName: string): Partial<CompatCssConfig>
export function getCompatCss(overrides?: Partial<CompatCssConfig>): string
```

### 3.3 封面生成策略（Cover Strategy）

封面生成设计为策略模式，`sharp` 合成和 AI 生图并存，由请求参数决定使用哪种策略。

**策略接口**：

```typescript
// core/cover/strategy.ts
export interface CoverStrategy {
  name: string;
  generate(options: CoverGenerateOptions): Promise<Buffer>;
}

export interface CoverGenerateOptions {
  title: string;
  author?: string;
  width: number;
  height: number;
  // sharp 策略额外字段
  backgroundPath?: string;
  presetName?: string;
  overlays?: CoverOverlay[];
  // AI 策略额外字段
  prompt?: string;   // 不提供则自动构建
}
```

**`sharp` 策略**（`core/cover/sharp-strategy.ts`）：

参照 `@lyhue1991/wxgzh/dist/core/cover.js` 实现。合成层顺序：背景图 → 半透明蒙层 → SVG 文字（标题 + 作者）。扩展了 `overlays` 参数支持额外图层（logo、水印、二维码等）。

**AI 策略**（`core/cover/ai-strategy.ts`）：

```typescript
export class AiCoverStrategy implements CoverStrategy {
  name = 'ai';

  private buildPrompt(title: string, author?: string): string {
    // 自动构建 Prompt：微信公众号封面风格 + 文章主题
    return `微信公众号封面图，1000x700像素，简洁现代风格，
            主题：${title}，
            无文字，高质量插画，适合科技内容`;
  }

  async generate(options: CoverGenerateOptions): Promise<Buffer> {
    const prompt = options.prompt ?? this.buildPrompt(options.title, options.author);
    const response = await fetch(process.env.NANOBANA_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.NANOBANA_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        prompt,
        model: 'nano-banana-pro-3.1',
        width: options.width,
        height: options.height,
      }),
    });
    // 同步返回，直接拿 buffer
    const data = await response.json();
    return Buffer.from(data.image, 'base64');
  }
}
```

**策略选择逻辑**（在 `services/pipeline.ts` 中）：

```typescript
// 请求参数 coverStrategy: 'sharp' | 'ai'，默认 'sharp'
// 如果指定 'ai' 但未配置 NANOBANA_API_KEY，降级为 'sharp' 并记录 warning
const strategy = resolveCoverStrategy(options.coverStrategy);
const coverBuffer = await strategy.generate({ title, author, width: 1000, height: 700 });
```

**新增环境变量**：

| 变量名 | 必填 | 说明 |
|--------|------|------|
| `NANOBANA_API_URL` | ❌ | NanoBanana API 端点 |
| `NANOBANA_API_KEY` | ❌ | NanoBanana API Key，不配置则 AI 封面不可用 |

**请求参数新增**：

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `coverStrategy` | `'sharp' \| 'ai'` | 封面生成策略，默认 `sharp` |
| `coverPrompt` | string | AI 策略的自定义 Prompt，不填则自动构建 |

### 3.4 Webhook 回调

发布成功后，服务主动 POST 到配置的回调地址。

**回调 Payload**：

```json
{
  "event": "draft.created",
  "timestamp": "2025-01-01T00:00:00Z",
  "data": {
    "publishId": "uuid",
    "mediaId": "微信 media_id",
    "title": "文章标题",
    "author": "作者名",
    "coverUrl": "封面图 URL",
    "coverStrategy": "sharp"
  }
}
```

**配置方式**：

- 全局 Webhook：通过环境变量 `WEBHOOK_URL` 配置
- 单次覆盖：请求参数 `webhookUrl` 字段

**重试策略**：失败后重试 3 次，间隔 5s / 15s / 30s，全部失败记录到数据库 `webhook_status: 'failed'`。

---

## 四、数据库设计

### 4.1 数据库选择策略

通过 `DATABASE_URL` 环境变量切换：

```bash
# SQLite（默认，不配置即使用）
# 数据文件存在 /app/data/md2wechat.db

# PostgreSQL（生产环境）
DATABASE_URL=postgresql://user:password@host:5432/md2wechat
```

ORM 层使用 **Kysely**，同一套查询代码同时兼容 SQLite 和 PostgreSQL，无需维护两套 SQL。

### 4.2 数据库表结构

**`publish_records` 表**：

```sql
CREATE TABLE publish_records (
  id            TEXT PRIMARY KEY,          -- UUID
  title         TEXT NOT NULL,
  author        TEXT,
  media_id      TEXT NOT NULL,             -- 微信返回的草稿 media_id
  thumb_media_id TEXT NOT NULL,            -- 封面 media_id
  cover_url     TEXT,                      -- 封面图 URL
  cover_strategy TEXT NOT NULL DEFAULT 'sharp',
  theme         TEXT,
  digest        TEXT,
  enable_comment INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'draft',  -- draft | failed
  error_message TEXT,                      -- 失败时记录错误信息
  webhook_status TEXT DEFAULT NULL,        -- null | sent | failed
  webhook_url   TEXT,
  created_at    TEXT NOT NULL,             -- ISO 8601
  updated_at    TEXT NOT NULL
);
```

### 4.3 数据库初始化

服务启动时自动执行 migration，用户无需手动建表：

```typescript
// 启动时自动 migrate
await db.schema.createTable('publish_records')
  .ifNotExists()
  // ... 字段定义
  .execute();
```

Docker 挂载（SQLite 模式，持久化数据）：

```yaml
volumes:
  - ./data:/app/data   # SQLite 文件持久化
```

---

## 五、项目结构

```
md2wechat/
├── src/
│   ├── index.ts                        # 入口，启动 Fastify
│   ├── config.ts                       # 配置加载与验证
│   │
│   ├── core/                           # 核心处理层（参照 wxgzh 源码自有实现）
│   │   ├── parser.ts                   # Markdown 解析 + Front Matter
│   │   ├── converter.ts                # Markdown → 微信兼容 HTML
│   │   ├── fixer.ts                    # HTML 图片修复 + 上传替换
│   │   ├── wechat.ts                   # 微信 API 客户端
│   │   ├── cover/
│   │   │   ├── strategy.ts             # CoverStrategy 接口定义
│   │   │   ├── sharp-strategy.ts       # sharp 合成实现
│   │   │   └── ai-strategy.ts          # NanoBanana AI 生图实现
│   │   └── css/
│   │       ├── compat.ts               # 微信兼容性 CSS（可配置化）
│   │       └── themes/                 # 内置主题 CSS
│   │           ├── default.css
│   │           ├── blue.css
│   │           └── ...
│   │
│   ├── services/
│   │   ├── pipeline.ts                 # 串联 core 的 Pipeline
│   │   ├── fileManager.ts              # 临时目录生命周期管理
│   │   ├── database.ts                 # DB 初始化 + Kysely 实例
│   │   ├── publishRecord.ts            # 发布记录 CRUD
│   │   └── webhook.ts                  # Webhook 发送 + 重试
│   │
│   ├── routes/
│   │   ├── publish.ts                  # POST /api/publish
│   │   ├── history.ts                  # GET /api/history
│   │   ├── config.ts                   # GET/POST /api/config
│   │   ├── health.ts                   # GET /health
│   │   └── themes.ts                   # GET /api/themes
│   │
│   └── types/
│       └── index.ts                    # 全局类型定义
│
├── assets/
│   └── backgrounds/                    # 内置封面背景图
│
├── config/                             # 用户可覆盖的配置（容器挂载）
│   ├── markdown-plugins.js.example     # Markdown 插件配置示例
│   └── .gitkeep
│
├── themes/                             # 用户自定义主题包目录（容器挂载）
│   └── .gitkeep
│
├── data/                               # SQLite 数据文件目录（容器挂载）
│   └── .gitkeep
│
├── Dockerfile
├── docker-compose.yml
├── docker-compose.prod.yml
├── .env.example
├── tsconfig.json
├── package.json
├── CONTRIBUTING.md
└── README.md
```

---

## 六、API 设计规格

### 6.1 POST /api/publish

**请求格式**：`multipart/form-data`

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `article` | File (.md) | ✅ | Markdown 文章文件 |
| `images[]` | File[] | ❌ | 文章中引用的本地图片（可多个） |
| `cover` | File (.jpg/.png) | ❌ | 自定义封面图，优先级最高 |
| `author` | string | ❌ | 作者名，覆盖 Front Matter 和默认配置 |
| `theme` | string | ❌ | 主题名，先查 `/app/themes/`，再查内置 |
| `digest` | string | ❌ | 摘要，不填则自动提取 |
| `enableComment` | boolean | ❌ | 是否开启评论，默认 false |
| `coverStrategy` | `'sharp' \| 'ai'` | ❌ | 封面生成策略，默认 `sharp` |
| `coverPrompt` | string | ❌ | AI 封面的自定义 Prompt |
| `webhookUrl` | string | ❌ | 本次发布的 Webhook 回调地址（覆盖全局配置） |

**成功响应** `200 OK`：

```json
{
  "success": true,
  "data": {
    "publishId": "uuid",
    "mediaId": "微信返回的草稿 media_id",
    "title": "文章标题",
    "author": "作者名",
    "coverUrl": "封面图微信 URL",
    "coverStrategy": "sharp",
    "publishedAt": "2025-01-01T00:00:00Z"
  }
}
```

**失败响应** `4xx / 5xx`：

```json
{
  "success": false,
  "error": {
    "code": "COVER_ERROR",
    "message": "AI 封面生成失败，已降级为 sharp 策略但仍失败：...",
    "step": "cover"
  }
}
```

**错误码枚举**：

| code | step | 含义 |
|------|------|------|
| `INVALID_FILE` | upload | 文件格式不支持或缺失 |
| `CONFIG_MISSING` | — | AppID / AppSecret 未配置 |
| `PARSE_ERROR` | parse | Markdown 解析失败 |
| `RENDER_ERROR` | render | HTML 渲染失败 |
| `FIX_ERROR` | fix | 图片上传替换失败 |
| `COVER_ERROR` | cover | 封面生成或上传失败 |
| `WXAPI_ERROR` | publish | 微信草稿 API 调用失败 |
| `DB_ERROR` | record | 发布记录写入失败（不影响微信发布） |
| `FILE_TOO_LARGE` | upload | 文件超出大小限制 |

---

### 6.2 GET /api/history

**功能**：查询发布历史记录

**Query 参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `page` | number | 页码，默认 1 |
| `pageSize` | number | 每页数量，默认 20，最大 100 |
| `status` | `draft \| failed` | 按状态筛选 |

**响应** `200 OK`：

```json
{
  "total": 42,
  "page": 1,
  "pageSize": 20,
  "items": [
    {
      "publishId": "uuid",
      "title": "文章标题",
      "author": "作者名",
      "mediaId": "微信 media_id",
      "coverUrl": "封面图 URL",
      "coverStrategy": "ai",
      "theme": "blue",
      "status": "draft",
      "webhookStatus": "sent",
      "createdAt": "2025-01-01T00:00:00Z"
    }
  ]
}
```

---

### 6.3 GET /health

```json
{
  "status": "ok",
  "version": "1.0.0",
  "wxConfigured": true,
  "tokenCached": true,
  "dbConnected": true,
  "aiCoverAvailable": false
}
```

### 6.4 GET /api/themes

```json
{
  "builtin": ["default", "blue", "green", "red", "yellow", "brown", "black", "orange"],
  "custom": ["tenisinfinite"]
}
```

### 6.5 GET /api/config（脱敏）

```json
{
  "appid": "wx1234****5678",
  "defaultAuthor": "tenisinfinite",
  "defaultTheme": "blue",
  "defaultCoverStrategy": "sharp",
  "aiCoverConfigured": false,
  "webhookConfigured": true
}
```

### 6.6 POST /api/config

```json
{
  "appid": "your_appid",
  "appsecret": "your_appsecret",
  "defaultAuthor": "tenisinfinite",
  "defaultTheme": "blue",
  "defaultCoverStrategy": "sharp",
  "webhookUrl": "https://your-webhook.com/callback"
}
```

---

## 七、配置管理规格

### 7.1 配置优先级（高→低）

```
请求参数（multipart 字段）
  ↓
Markdown Front Matter
  ↓
环境变量
  ↓
默认值
```

### 7.2 完整环境变量清单

| 变量名 | 必填 | 默认值 | 说明 |
|--------|------|--------|------|
| `WXGZH_APPID` | ✅ | — | 微信公众号 AppID |
| `WXGZH_APPSECRET` | ✅ | — | 微信公众号 AppSecret |
| `WXGZH_DEFAULT_AUTHOR` | ❌ | `tenisinfinite` | 默认作者名 |
| `WXGZH_DEFAULT_THEME` | ❌ | `default` | 默认主题 |
| `WXGZH_DEFAULT_COVER_STRATEGY` | ❌ | `sharp` | 默认封面策略 |
| `NANOBANA_API_URL` | ❌ | — | NanoBanana API 端点 |
| `NANOBANA_API_KEY` | ❌ | — | NanoBanana API Key |
| `DATABASE_URL` | ❌ | SQLite | PostgreSQL 连接串，不填用 SQLite |
| `WEBHOOK_URL` | ❌ | — | 全局 Webhook 回调地址 |
| `API_KEY` | ❌ | — | 接口鉴权 Key，不填则不鉴权 |
| `PORT` | ❌ | `3000` | 服务端口 |
| `MAX_FILE_SIZE_MB` | ❌ | `10` | 单文件大小上限（MB） |
| `TEMP_DIR` | ❌ | `/tmp` | 临时文件目录 |
| `LOG_LEVEL` | ❌ | `info` | 日志级别 |
| `DATA_DIR` | ❌ | `/app/data` | SQLite 数据文件目录 |
| `THEMES_DIR` | ❌ | `/app/themes` | 自定义主题包目录 |
| `CONFIG_DIR` | ❌ | `/app/config` | 用户配置文件目录 |

### 7.3 .env.example

```env
# 必填：微信公众号凭证
WXGZH_APPID=your_appid_here
WXGZH_APPSECRET=your_appsecret_here

# 默认行为
WXGZH_DEFAULT_AUTHOR=tenisinfinite
WXGZH_DEFAULT_THEME=default
WXGZH_DEFAULT_COVER_STRATEGY=sharp

# AI 封面（可选）
NANOBANA_API_URL=https://api.nanobana.ai/v1/images/generate
NANOBANA_API_KEY=

# 数据库（不填则用 SQLite）
DATABASE_URL=

# Webhook（可选）
WEBHOOK_URL=

# 服务配置
API_KEY=
PORT=3000
MAX_FILE_SIZE_MB=10
LOG_LEVEL=info
```

---

## 八、Docker 配置规格

### 8.1 Dockerfile

```dockerfile
FROM node:20-alpine

# sharp 需要的原生依赖（vips，不需要 Cairo/Pango）
RUN apk add --no-cache vips-dev python3 make g++

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY dist/ ./dist/
COPY src/core/css/themes/ ./dist/core/css/themes/
COPY assets/ ./assets/

# 挂载点说明
# /app/config  — 用户 Markdown 插件配置
# /app/themes  — 用户自定义主题包
# /app/data    — SQLite 数据文件（SQLite 模式）
VOLUME ["/app/config", "/app/themes", "/app/data"]

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/index.js"]
```

### 8.2 docker-compose.yml（开发 / 快速启动）

```yaml
version: '3.8'

services:
  md2wechat:
    build: .
    ports:
      - "3000:3000"
    env_file:
      - .env
    environment:
      - LOG_LEVEL=debug
    volumes:
      - ./config:/app/config
      - ./themes:/app/themes
      - ./data:/app/data
    restart: unless-stopped
```

### 8.3 docker-compose.prod.yml（PostgreSQL 生产环境）

```yaml
version: '3.8'

services:
  md2wechat:
    image: ghcr.io/tenisinfinite/md2wechat:latest
    ports:
      - "127.0.0.1:3000:3000"
    env_file:
      - .env.prod
    volumes:
      - ./config:/app/config
      - ./themes:/app/themes
    depends_on:
      postgres:
        condition: service_healthy
    restart: always
    deploy:
      resources:
        limits:
          memory: 512M

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: md2wechat
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: always

volumes:
  pgdata:
```

---

## 九、安全设计

### 9.1 文件上传安全

- 允许类型：`.md` / `.jpg` / `.jpeg` / `.png` / `.gif` / `.webp`
- 单文件大小：默认 10MB（`MAX_FILE_SIZE_MB`）
- 单次请求总大小：50MB
- 文件名 sanitization：只保留 `[a-zA-Z0-9._-]`，防路径穿越

### 9.2 API 鉴权

请求头带 `X-API-Key`，通过 `API_KEY` 环境变量验证。未配置 `API_KEY` 则跳过鉴权（适合内网部署场景）。

### 9.3 密钥保护

- `WXGZH_APPSECRET` / `NANOBANA_API_KEY` 不出现在任何日志
- `GET /api/config` 返回脱敏 appid（`wx1234****5678`），不返回 secret
- Fastify request log 中屏蔽敏感字段

---

## 十、集成示例

### 10.1 n8n 工作流

```
HTTP Request 节点：
  Method: POST
  URL: http://your-server:3000/api/publish
  Headers:
    X-API-Key: your-key
  Body (multipart/form-data):
    article  → {{ $binary.article }}
    author   → tenisinfinite
    theme    → blue
    coverStrategy → ai
    webhookUrl → https://your-n8n/webhook/wechat-callback
```

### 10.2 完整自动化链路

```
Claude 生成 Markdown（含图片引用）
    ↓
n8n：保存 md 和图片为二进制
    ↓
n8n：POST /api/publish（携带所有文件）
    ↓
md2wechat 处理（~5-15s，含 AI 生图）
    ↓
返回 { publishId, mediaId, title }
    ↓
md2wechat 异步发送 Webhook
    ↓
n8n Webhook 节点接收 → 发送通知
    ↓
"草稿『{title}』已就绪，请前往公众号后台发布"
```

---

## 十一、实施步骤（Claude Code 执行顺序）

### Phase 1：项目初始化（约 0.5h）

1. `npm init`，配置 `tsconfig.json`（`strict: true`, `target: ES2022`, `module: Node16`）
2. 安装全部依赖：

```bash
# 核心处理
npm install gray-matter markdown-it markdown-it-mathjax3 highlight.js \
            @css-inline/css-inline cheerio sharp axios form-data

# HTTP 服务
npm install fastify @fastify/multipart @fastify/cors uuid

# 数据库
npm install better-sqlite3 pg kysely

# 工具
npm install -D typescript @types/node @types/better-sqlite3 @types/pg ts-node
```

### Phase 2：实现 core/ 模块（约 4h）

参照 `@lyhue1991/wxgzh` 源码实现，安装原包辅助参考：`npm install @lyhue1991/wxgzh --no-save`

3. **`core/wechat.ts`** — 参照 `dist/core/wechat.js`，token 改内存缓存
4. **`core/parser.ts`** — 参照 `dist/core/parser.js`，逻辑不变
5. **`core/css/compat.ts`** — 将 `dist/core/converter.js` 中 6 段硬编码 CSS 常量提取为 `CompatCssConfig`
6. **`core/css/themes/`** — 从原包 `styles/` 目录复制全部 CSS 文件
7. **`core/converter.ts`** — 参照 `dist/core/converter.js`，CSS 层改用 `compat.ts`，支持外部主题和 Markdown 插件
8. **`core/fixer.ts`** — 参照 `dist/core/fixer.js`，改为接受 HTML 字符串（不是文件路径）
9. **`core/cover/strategy.ts`** — 定义 `CoverStrategy` 接口
10. **`core/cover/sharp-strategy.ts`** — 参照 `dist/core/cover.js`，加 `overlays` 扩展点
11. **`core/cover/ai-strategy.ts`** — NanoBanana API 调用，自动构建 Prompt
12. **`assets/backgrounds/`** — 从原包 `assets/backgrounds/` 复制全部背景图

### Phase 3：实现服务层（约 2h）

13. **`services/database.ts`** — Kysely 初始化，根据 `DATABASE_URL` 自动选择 SQLite 或 PostgreSQL，启动时 auto-migrate
14. **`services/publishRecord.ts`** — 发布记录的 insert / query / update
15. **`services/webhook.ts`** — Webhook 发送，3 次重试（5s / 15s / 30s），失败更新 DB 状态
16. **`services/fileManager.ts`** — 临时目录 UUID 生命周期
17. **`services/pipeline.ts`** — 串联所有 core 步骤，每步错误包装为带 `step` 字段的结构化错误
18. **`config.ts`** — 环境变量加载与校验，`WechatClient` 单例，Cover Strategy 初始化

### Phase 4：实现路由层（约 1.5h）

19. **`routes/health.ts`**
20. **`routes/themes.ts`** — 扫描内置 + `/app/themes/` 目录
21. **`routes/config.ts`**
22. **`routes/history.ts`** — 分页查询发布记录
23. **`routes/publish.ts`** — 文件上传 + 类型校验 + 调 pipeline + 触发 webhook

### Phase 5：容器化与测试（约 1h）

24. **`index.ts`** — 启动 Fastify，注册插件和路由，graceful shutdown
25. **`Dockerfile`** — 确认 sharp 在 Alpine 上能正常编译
26. **`docker-compose.yml`** / **`docker-compose.prod.yml`**
27. **端到端测试** — 用原包仓库的 `test_article1.md` 跑通完整流程，分别测试 sharp 封面和 AI 封面
28. **`README.md`** — 快速启动、配置说明、主题包制作指南、Markdown 插件配置说明

---

## 十二、验收标准

### 核心功能
- [ ] `POST /api/publish` 成功将 Markdown + 图片发布到微信草稿箱
- [ ] `coverStrategy: 'sharp'` 和 `coverStrategy: 'ai'` 均可正常工作
- [ ] AI 封面未配置时自动降级为 sharp，并在响应中说明

### 可扩展性
- [ ] 挂载自定义主题包后，`GET /api/themes` 能返回该主题，发布时能正确应用
- [ ] 挂载 `markdown-plugins.js` 后，自定义插件能在渲染中生效
- [ ] 修改 `core/css/compat.ts` 中任意 CSS 段后，渲染结果正确反映

### 数据持久化
- [ ] 每次发布后，`GET /api/history` 能查到记录
- [ ] `DATABASE_URL` 切换为 PostgreSQL 后，服务正常运行，记录正确写入
- [ ] Webhook 发送失败后，`history` 中 `webhookStatus` 为 `failed`

### 工程质量
- [ ] 临时目录在请求结束后无残留
- [ ] 服务异常时返回结构化错误（含 `step` 字段），不暴露内部堆栈
- [ ] `AppSecret` / `NANOBANA_API_KEY` 不出现在任何日志或 API 响应
- [ ] Docker 镜像构建无报错，大小 < 400MB
- [ ] `GET /health` 正确反映各组件状态（wx / db / ai）

---

## 十三、后续扩展方向（v2 及以后）

以下不在当前交付范围，但架构已预留扩展点：

- **品牌封面**：在 sharp 策略的 `overlays` 中加入 tenisinfinite logo 层，无需修改核心代码
- **更多 AI 图像服务**：实现 `CoverStrategy` 接口即可接入任意 AI 生图服务
- **多账号支持**：请求参数加 `accountId`，路由到不同 `WechatClient` 实例
- **发布历史 UI**：基于 `GET /api/history` 做一个简单的 Web 管理界面

---

*文档版本：v3.0 | 项目：tenisinfinite/md2wechat*  
*v3.0 更新：完整设计可插拔架构（主题包 / Markdown 插件 / 封面策略），引入数据库层（SQLite / PostgreSQL），Webhook 回调，发布历史，确立标准输入契约*