# md2wechat

**Markdown → 微信公众号草稿箱** — 开源的一键发布 HTTP 微服务

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://hub.docker.com/r/tenisinfinite/md2wechat)
[![Node.js](https://img.shields.io/badge/node-%3E%3D20-green.svg)](https://nodejs.org)

---

## 这是什么

`md2wechat` 是一个自托管的 HTTP 微服务，接收 Markdown 文件，自动完成格式转换、图片上传、封面生成，并将文章提交到微信公众号草稿箱。

它的设计目标是成为你内容工作流的**最后一环**——无论内容来自 Claude、Notion、飞书还是人工创作，只需统一转换为 Markdown，`md2wechat` 负责后续的一切。

```
你的内容工具（Claude / Notion / 飞书 / 手写）
        ↓  Markdown 文件
  n8n / 脚本 / 任意工具
        ↓  POST /api/publish
     md2wechat
        ↓
  微信公众号草稿箱
        ↓  Webhook 回调
  你的通知渠道（Slack / 企业微信 / n8n）
```

---

## 核心功能

- **Markdown → 微信兼容 HTML**：代码高亮、数学公式、表格、引用块全支持
- **图片自动处理**：本地图片和外链图片统一上传到微信图床，自动替换链接
- **双模式封面生成**
  - `sharp` 模式：背景图 + 标题文字合成，支持自定义背景和额外图层
  - `ai` 模式：接入 NanoBanana Pro 等 AI 生图服务，根据标题自动构建 Prompt
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

# 3. 启动服务
docker-compose up -d

# 4. 验证运行状态
curl http://localhost:3000/health
```

### 发布你的第一篇文章

```bash
curl -X POST http://localhost:3000/api/publish \
  -H "X-API-Key: your-api-key" \
  -F "article=@article.md" \
  -F "author=你的名字" \
  -F "theme=blue"
```

成功后登录微信公众号后台 → 草稿箱，即可看到文章。

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

### AI 封面配置

| 变量名 | 说明 |
|--------|------|
| `NANOBANA_API_URL` | NanoBanana API 端点 |
| `NANOBANA_API_KEY` | NanoBanana API Key |

完整配置项见 [`.env.example`](.env.example)。

### 微信 IP 白名单

微信公众号后台 → 设置与开发 → 开发接口管理 → 基本配置 → IP 白名单，将服务器的公网 IP 添加进去。可通过 `curl https://ip.sb` 查询当前服务器 IP。

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
  # 也可以自定义：-F "coverPrompt=科技感插画，蓝色调，无文字"
```

未配置 `NANOBANA_API_KEY` 时，AI 封面请求会自动降级为 `sharp` 模式。

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
│   ├── routes/         # HTTP 路由
│   └── types/          # TypeScript 类型定义
├── assets/
│   └── backgrounds/    # 内置封面背景图
├── config/             # 用户配置目录（容器挂载）
├── themes/             # 用户自定义主题目录（容器挂载）
├── data/               # SQLite 数据文件目录（容器挂载）
├── docs/
│   └── SPEC.md         # 完整项目规格文档
├── Dockerfile
├── docker-compose.yml
├── docker-compose.prod.yml
└── .env.example
```

---

## 技术实现说明

`md2wechat` 的核心处理能力参照 [`@lyhue1991/wxgzh`](https://github.com/lyhue1991/wxgzh)（MIT License）实现，并在以下方面做了架构改造：

- 微信兼容性 CSS 从硬编码常量改为可配置结构，支持主题包覆盖
- 封面生成改为策略模式，`sharp` 合成和 AI 生图并存
- 微信 API token 缓存从本地文件改为内存管理，适合容器化场景
- 核心函数改为接受字符串输入输出（不依赖文件系统路径），Pipeline 全内存化

---

## 贡献指南

欢迎提交 Issue 和 Pull Request。

**本地开发**：

```bash
git clone https://github.com/tenisinfinite/md2wechat.git
cd md2wechat
npm install
cp .env.example .env   # 填写你的微信凭证
npm run dev            # 启动开发服务器（ts-node，热重载）
```

**提交前请确认**：

- [ ] TypeScript 编译通过：`npm run build`
- [ ] 核心功能测试通过：用测试文件跑通完整 Pipeline

---

## 常见问题

**Q：服务返回"微信接口调用失败：invalid ip"**

A：当前服务器 IP 未加入微信公众号 IP 白名单。前往公众号后台 → 设置与开发 → 开发接口管理 → 基本配置 → IP 白名单添加。

**Q：图片在预览中显示但发布后看不到**

A：图片上传到微信图床需要 AppID 和 AppSecret 正确配置。检查 `/health` 接口中 `wxConfigured` 是否为 `true`。

**Q：AI 封面不生效，自动降级为 sharp**

A：检查 `NANOBANA_API_KEY` 是否配置，以及 `/health` 中 `aiCoverAvailable` 是否为 `true`。

**Q：能否支持定时发布？**

A：微信草稿箱不支持定时发布，需要人工在公众号后台点击发布。定时投递到草稿箱的功能目前不在计划中。

---

## License

MIT © [tenisinfinite](https://github.com/tenisinfinite)

---

*如果这个项目对你有帮助，欢迎 Star ⭐*