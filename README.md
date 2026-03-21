# md2wechat

**Markdown → 微信公众号草稿箱** — 开源的一键发布 HTTP 微服务，附带 Web 管理面板

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://hub.docker.com/r/tenisinfinite/md2wechat)
[![Node.js](https://img.shields.io/badge/node-%3E%3D20-green.svg)](https://nodejs.org)

---

## 这是什么

`md2wechat` 是一个自托管的 HTTP 微服务，接收 Markdown 文件，自动完成格式转换、图片上传、封面生成，并将文章提交到微信公众号草稿箱。

它的设计目标是成为你内容工作流的**最后一环**——无论内容来自 Claude、Notion、飞书还是人工创作，只需统一转换为 Markdown，`md2wechat` 负责后续的一切。

你可以通过**内置 Web 管理面板**直接在浏览器中操作，也可以通过 **REST API** 集成到任何自动化工作流中。

```
你的内容工具（Claude / Notion / 飞书 / 手写）
        ↓  Markdown 文件
  n8n / 脚本 / Web 面板
        ↓  POST /api/publish
     md2wechat
        ↓
  微信公众号草稿箱
        ↓  Webhook 回调
  你的通知渠道（Slack / 企业微信 / n8n）
```

---

## 核心功能

- **Web 管理面板**：浏览器内发布文章、查看历史、管理配置，开箱即用
- **Markdown → 微信兼容 HTML**：代码高亮、数学公式、表格、引用块全支持
- **图片自动处理**：本地图片和外链图片统一上传到微信图床，自动替换链接
- **双模式封面生成**
  - `sharp` 模式：背景图 + 标题文字合成，支持自定义背景和额外图层
  - `ai` 模式：接入 Google Imagen 4 AI 生图，根据标题自动构建 Prompt
- **自定义主题包**：支持挂载完整主题包（CSS + 兼容性覆盖），无需修改源码
- **Markdown 插件扩展**：通过配置文件注册任意 `markdown-it` 插件
- **发布历史持久化**：默认 SQLite，可切换为 PostgreSQL
- **Webhook 回调**：发布成功后主动通知，支持全局配置和单次覆盖
- **标准 REST API**：任何工具都能调用，天然适配 n8n、Make、自定义脚本

---

## 快速开始

### 前置要求

- Docker & Docker Compose
- 微信公众号 AppID 和 AppSecret（需已认证，并将服务器 IP 加入白名单）

### 一分钟启动

```bash
# 1. 克隆项目
git clone https://github.com/tenisinfinite/md2wechat.git
cd md2wechat

# 2. 配置环境变量
cp .env.example .env
# 编辑 .env，至少填写 WXGZH_APPID 和 WXGZH_APPSECRET

# 3. 构建并启动服务
npm run build
docker-compose up -d

# 4. 打开 Web 管理面板
open http://localhost:3000
```

### Web 管理面板

启动后访问 `http://localhost:3000` 即可使用 Web 管理面板：

- **仪表盘**：服务状态一览（微信配置、数据库、AI 封面、Token 缓存）
- **发布文章**：拖拽整个文件夹或选择文件，自动识别 Markdown 和图片，选择主题和封面策略，一键发布
- **发布历史**：分页查看所有发布记录，筛选状态，预览封面
- **系统设置**：查看当前配置和可用主题

### 通过 API 发布

```bash
curl -X POST http://localhost:3000/api/publish \
  -H "X-API-Key: your-api-key" \
  -F "article=@article.md" \
  -F "author=你的名字" \
  -F "theme=blue"
```

附带图片的发布：

```bash
curl -X POST http://localhost:3000/api/publish \
  -H "X-API-Key: your-api-key" \
  -F "article=@output/article.md" \
  -F "images[]=@output/images/img1.png" \
  -F "images[]=@output/images/img2.png" \
  -F "author=你的名字"
```

成功后登录微信公众号后台 → 草稿箱，即可看到文章。

> **Web 面板提示**：你可以直接将包含 `.md` 文件和 `images/` 目录的整个文件夹拖入发布页面，系统会自动识别文章和图片文件。

---

## 配置说明

### 必填配置

| 变量名 | 说明 |
|--------|------|
| `WXGZH_APPID` | 微信公众号 AppID |
| `WXGZH_APPSECRET` | 微信公众号 AppSecret |

### 常用可选配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `WXGZH_DEFAULT_AUTHOR` | `tenisinfinite` | 默认作者名 |
| `WXGZH_DEFAULT_THEME` | `default` | 默认主题 |
| `WXGZH_DEFAULT_COVER_STRATEGY` | `sharp` | 默认封面策略（`sharp` / `ai`） |
| `API_KEY` | 空（不鉴权） | 接口鉴权 Key |
| `WEBHOOK_URL` | — | 全局 Webhook 回调地址 |
| `DATABASE_URL` | SQLite | PostgreSQL 连接串，不填用 SQLite |

### AI 封面配置（Google Imagen 4）

通过 Gemini API 调用 Google Imagen 4 生成封面图。

| 变量名 | 说明 |
|--------|------|
| `IMAGEN_API_KEY` | Gemini API Key（[获取地址](https://aistudio.google.com/apikey)） |
| `IMAGEN_MODEL` | 模型名，默认 `imagen-4.0-fast-generate-001` |

可选模型：

| 模型 | 特点 | 价格 |
|------|------|------|
| `imagen-4.0-fast-generate-001` | 快速生成（默认） | $0.02/张 |
| `imagen-4.0-generate-001` | 标准质量 | $0.04/张 |
| `imagen-4.0-ultra-generate-001` | 最高质量 | $0.06/张 |

未配置 `IMAGEN_API_KEY` 时，AI 封面请求会自动降级为 `sharp` 模式。

完整配置项见 [`.env.example`](.env.example)。

### 微信 IP 白名单

微信公众号后台 → 设置与开发 → 开发接口管理 → 基本配置 → IP 白名单，将服务器的公网 IP 添加进去。

> 注意：如果使用 Docker 部署，容器的出口 IP 可能与宿主机不同。可通过 `docker exec <容器名> wget -qO- https://ip.sb` 查询容器实际出口 IP。

---

## API 接口

### POST /api/publish

发布文章到草稿箱。

**请求**：`multipart/form-data`

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `article` | File (.md) | ✅ | Markdown 文章文件 |
| `images[]` | File[] | — | 文章引用的本地图片（可多个） |
| `cover` | File | — | 自定义封面图，优先级最高 |
| `author` | string | — | 覆盖默认作者名 |
| `theme` | string | — | 主题名（内置或自定义） |
| `digest` | string | — | 文章摘要，不填则自动提取 |
| `enableComment` | boolean | — | 是否开启评论 |
| `coverStrategy` | `sharp` / `ai` | — | 封面生成策略 |
| `coverPrompt` | string | — | AI 封面的自定义 Prompt |
| `webhookUrl` | string | — | 本次发布的回调地址 |

**成功响应**：

```json
{
  "success": true,
  "data": {
    "publishId": "uuid",
    "mediaId": "草稿 media_id",
    "title": "文章标题",
    "author": "作者名",
    "coverUrl": "封面图 URL",
    "coverStrategy": "sharp",
    "publishedAt": "2025-01-01T00:00:00Z"
  }
}
```

### GET /api/history

查询发布历史。支持 `page`、`pageSize`、`status` 参数。

### GET /api/themes

列出所有可用主题（内置 + 自定义）。

### GET /api/config

查看当前配置（脱敏）。

### GET /health

服务健康状态，包含微信配置、数据库连接、AI 封面可用性。

---

## 进阶用法

### 自定义主题包

在宿主机创建主题目录，然后挂载到容器：

```
my-theme/
├── theme.css       # 主题样式
├── compat.css      # 可选：覆盖微信兼容性 CSS
└── theme.json      # 主题元数据
```

**theme.json**：

```json
{
  "name": "my-theme",
  "displayName": "我的主题",
  "version": "1.0.0",
  "compatOverrides": {
    "highlight": true
  }
}
```

**docker-compose.yml** 中添加挂载：

```yaml
volumes:
  - ./my-theme:/app/themes/my-theme
```

发布时指定 `theme=my-theme` 即可使用。

---

### 自定义 Markdown 插件

在 `config/` 目录下创建 `markdown-plugins.js`：

```javascript
// config/markdown-plugins.js
module.exports = [
  [require('markdown-it-footnote')],
  [require('markdown-it-container'), 'tip', {
    render: (tokens, idx) =>
      tokens[idx].nesting === 1 ? '<div class="tip">' : '</div>'
  }],
];
```

服务启动时自动加载，无需重新构建镜像。

---

### 在 Markdown 中使用 Front Matter

```markdown
---
title: 文章标题
author: 作者名
digest: 这是文章摘要
theme: blue
enableComment: true
---

# 文章标题

正文内容...
```

Front Matter 中的字段优先级高于服务默认配置，但低于请求参数。

---

### 使用 AI 封面

```bash
curl -X POST http://localhost:3000/api/publish \
  -F "article=@article.md" \
  -F "coverStrategy=ai"
  # Prompt 根据文章标题自动构建
  # 也可以自定义：-F "coverPrompt=tech illustration, blue tone, no text"
```

未配置 `IMAGEN_API_KEY` 时，AI 封面请求会自动降级为 `sharp` 模式。

---

### 接入 OpenClaw（AI 助手自动发文）

[OpenClaw](https://openclaw.ai) 是一个开源自托管 AI 助手平台，支持 20+ 聊天渠道。通过内置的 `wechat-publisher` Skill，可以用自然语言指令发布公众号文章。

```bash
# 安装 Skill
cp -r wechat-publisher/ ~/.openclaw/skills/wechat-publisher/

# 设置环境变量
export MD2WECHAT_URL="http://your-server:3000"
export MD2WECHAT_API_KEY="your-api-key"
```

然后在任意聊天渠道对 OpenClaw 说：

- "发布 report.md 到公众号，用蓝色主题"
- "看看最近发布了哪些文章"
- "每周一早上 9 点自动发布 weekly.md"

详见 [OpenClaw 集成文档](docs/openclaw-integration.md)。

---

### 接入 n8n

在 n8n 中使用 **HTTP Request** 节点：

```
Method: POST
URL: http://your-server:3000/api/publish
Headers:
  X-API-Key: your-key
Body (Form-Data):
  article  → Binary file from previous node
  author   → tenisinfinite
  theme    → blue
  webhookUrl → https://your-n8n/webhook/wechat-notify
```

---

### 生产环境部署（PostgreSQL）

```bash
# 使用 prod compose 文件
docker-compose -f docker-compose.prod.yml up -d
```

`docker-compose.prod.yml` 包含 PostgreSQL 服务，数据持久化到 Docker volume。

---

## 内置主题

| 主题名 | 风格 |
|--------|------|
| `default` | 简洁黑白 |
| `blue` | 蓝色系 |
| `green` | 绿色系 |
| `red` | 红色系 |
| `yellow` | 黄色系 |
| `brown` | 棕色系 |
| `black` | 深色 |
| `orange` | 橙色系 |

---

## 项目目录结构

```
md2wechat/
├── src/
│   ├── core/           # 核心处理层（parser / converter / fixer / cover / wechat）
│   ├── services/       # Pipeline、数据库、Webhook
│   ├── routes/         # HTTP 路由 + 静态文件服务
│   └── types/          # TypeScript 类型定义
├── public/
│   └── index.html      # Web 管理面板（单文件 SPA）
├── assets/
│   └── backgrounds/    # 内置封面背景图
├── wechat-publisher/   # OpenClaw Skill（可复制到其他项目使用）
├── docs/               # 集成文档
├── config/             # 用户配置目录（容器挂载）
├── themes/             # 用户自定义主题目录（容器挂载）
├── data/               # SQLite 数据文件目录（容器挂载）
├── Dockerfile
├── docker-compose.yml
├── docker-compose.prod.yml
└── .env.example
```

---

## 技术实现说明

`md2wechat` 的核心处理能力参照 [`@lyhue1991/wxgzh`](https://github.com/lyhue1991/wxgzh)（MIT License）实现，并在以下方面做了架构改造：

- 微信兼容性 CSS 从硬编码常量改为可配置结构，支持主题包覆盖
- 封面生成改为策略模式，`sharp` 合成和 Google Imagen 4 AI 生图并存
- 微信 API token 缓存从本地文件改为内存管理，适合容器化场景
- 核心函数改为接受字符串输入输出（不依赖文件系统路径），Pipeline 全内存化
- 内置 Web 管理面板，零额外依赖

---

## 贡献指南

欢迎提交 Issue 和 Pull Request。

**本地开发**：

```bash
git clone https://github.com/tenisinfinite/md2wechat.git
cd md2wechat
npm install
cp .env.example .env   # 填写你的微信凭证
npm run build
node dist/index.js     # 启动服务
```

**提交前请确认**：

- [ ] TypeScript 编译通过：`npm run build`
- [ ] 核心功能测试通过：用测试文件跑通完整 Pipeline

---

## 常见问题

**Q：服务返回"微信接口调用失败：invalid ip"**

A：当前服务器 IP 未加入微信公众号 IP 白名单。前往公众号后台 → 设置与开发 → 开发接口管理 → 基本配置 → IP 白名单添加。Docker 环境下请检查容器的实际出口 IP。

**Q：图片在预览中显示但发布后看不到**

A：图片上传到微信图床需要 AppID 和 AppSecret 正确配置。检查 `/health` 接口中 `wxConfigured` 是否为 `true`。

**Q：AI 封面不生效，自动降级为 sharp**

A：检查 `IMAGEN_API_KEY` 是否配置，以及 `/health` 中 `aiCoverAvailable` 是否为 `true`。API Key 可在 [Google AI Studio](https://aistudio.google.com/apikey) 获取。

**Q：发布时报错 "description size out of limit (45004)"**

A：微信限制摘要（digest）最长 120 个字符。v1.0.0+ 版本已自动截断超长摘要，如仍遇到此问题请更新到最新版本。

**Q：能否支持定时发布？**

A：微信草稿箱不支持定时发布，最终仍需在公众号后台点击发布。但可以通过 [OpenClaw](https://openclaw.ai) 的 Cron 功能定时投递草稿到草稿箱，详见 [OpenClaw 集成文档](docs/openclaw-integration.md)。

---

## License

MIT © [tenisinfinite](https://github.com/tenisinfinite)

---

*如果这个项目对你有帮助，欢迎 Star*
