# OpenClaw x md2wechat: WeChat 公众号自动发文集成方案

## 概述

本文档介绍如何将 [md2wechat](https://github.com/user/md2wechat)（Markdown 转微信公众号草稿服务）与 [OpenClaw](https://openclaw.ai)（开源自托管 AI 助手平台）集成，实现通过自然语言指令自动发布微信公众号文章。

### 为什么选择 OpenClaw？

- **多渠道触发**：支持 WhatsApp、Telegram、Slack、Discord、微信等 20+ 聊天平台，用户可从任意渠道发起发文指令
- **自然语言驱动**：无需记忆 API 参数，直接说"发布 article.md 到公众号，用蓝色主题"
- **定时任务**：内置 Cron 调度器，支持定时/周期性发布
- **Webhook 联动**：md2wechat 发布完成后可通过 Webhook 通知 OpenClaw，形成闭环
- **自托管安全**：数据全部在自己的服务器上，不经过第三方 SaaS

## 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                     用户终端                              │
│  (WhatsApp / Telegram / Slack / Web / CLI / ...)         │
└──────────────────────┬──────────────────────────────────┘
                       │ 自然语言消息
                       ▼
┌─────────────────────────────────────────────────────────┐
│                   OpenClaw Gateway                       │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Agent Runtime│  │ Skill Engine │  │ Cron Scheduler│  │
│  │  (LLM Loop) │──│ md2wechat    │  │  定时发布任务   │  │
│  └─────────────┘  │ Skill        │  └───────┬───────┘  │
│                   └──────┬───────┘          │           │
│                          │                  │           │
│  ┌───────────────────────┼──────────────────┤           │
│  │ Webhook Receiver      │                  │           │
│  │ (接收发布结果通知)      │                  │           │
│  └───────────┬───────────┘                  │           │
└──────────────┼──────────────────────────────┼───────────┘
               │                              │
               ▼                              ▼
┌─────────────────────────────────────────────────────────┐
│                   md2wechat Service                      │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐    │
│  │ Fastify   │  │ Pipeline │  │ WeChat API Client  │    │
│  │ API Server│──│ 7-Step   │──│ Token / Upload /   │    │
│  │           │  │ Workflow │  │ Draft Creation     │    │
│  └──────────┘  └──────────┘  └─────────┬──────────┘    │
│                                         │               │
└─────────────────────────────────────────┼───────────────┘
                                          │
                                          ▼
                              ┌──────────────────────┐
                              │  WeChat Official      │
                              │  Account Platform     │
                              │  (微信公众号后台)       │
                              └──────────────────────┘
```

### 数据流

1. **用户** 在任意聊天平台发送指令（如"把 report.md 发到公众号"）
2. **OpenClaw Gateway** 接收消息，路由到 Agent Runtime
3. **Agent Runtime** 识别意图，匹配 md2wechat Skill
4. **Skill** 调用 md2wechat API（`POST /api/publish`）
5. **md2wechat Pipeline** 执行：解析 Markdown → 渲染 HTML → 上传图片 → 生成封面 → 创建草稿
6. **WeChat API** 创建公众号草稿
7. **Webhook** 将发布结果通知回 OpenClaw
8. **OpenClaw** 将结果通过原始聊天渠道回复给用户

## 安装与配置

### 前置条件

- 已部署的 md2wechat 服务实例
- 已安装的 OpenClaw（`npm i openclaw` 或 `pip install openclaw`）
- 微信公众号 AppID 和 AppSecret（在 md2wechat 中配置）

### Step 1: 安装 Skill

将 `wechat-publisher/` 目录复制到 OpenClaw 的 workspace skills 目录：

```bash
# 方式一：直接复制
cp -r wechat-publisher/ ~/.openclaw/skills/wechat-publisher/

# 方式二：如果使用 OpenClaw workspace
cp -r wechat-publisher/ ./skills/wechat-publisher/
```

### Step 2: 配置环境变量

在 OpenClaw 的环境中设置：

```bash
# md2wechat 服务地址
export MD2WECHAT_URL="http://your-server:3000"

# API Key（如果 md2wechat 配置了认证）
export MD2WECHAT_API_KEY="your-api-key"
```

或者在 OpenClaw 的配置文件中添加：

```yaml
# ~/.openclaw/config.yaml
env:
  MD2WECHAT_URL: "http://localhost:3000"
  MD2WECHAT_API_KEY: "your-api-key"
```

### Step 3: 验证连通性

在 OpenClaw 中发送消息：

```
检查一下公众号发文服务是否正常
```

OpenClaw 会自动调用 health check，确认 md2wechat 服务可达。

## 使用方式

### 基本发文

```
发布 ~/articles/my-post.md 到公众号
```

### 指定主题和作者

```
用蓝色主题发布 report.md，作者写"技术团队"
```

### 带封面图片发布

```
发布 article.md 到公众号，用 cover.jpg 作为封面
```

### AI 生成封面

```
发布 article.md，用 AI 生成一个科技感的封面
```

### 查看发布历史

```
看看最近发布了哪些公众号文章
```

### 查看可用主题

```
公众号有哪些可用主题？
```

### 批量发布

```
把 ~/weekly-reports/ 文件夹里所有 md 文件都发到公众号
```

### 定时发布

```
每周一早上 9 点，把 ~/auto-publish/weekly.md 发到公众号
```

OpenClaw 会创建一个 Cron 任务：
```
openclaw cron add "0 9 * * 1" "publish ~/auto-publish/weekly.md to WeChat with blue theme"
```

## Webhook 集成（双向通信）

### md2wechat → OpenClaw

配置 md2wechat 的 Webhook URL 指向 OpenClaw 的 webhook 接收端点，实现发布结果自动通知：

```bash
# 在 md2wechat 的 .env 中配置
WEBHOOK_URL=http://openclaw-server:port/webhook/md2wechat
```

发布完成后，md2wechat 会发送：

```json
{
  "event": "draft.created",
  "timestamp": "2026-03-22T10:30:00.000Z",
  "data": {
    "publishId": "uuid",
    "mediaId": "wx-media-id",
    "title": "Article Title",
    "author": "Author",
    "coverUrl": "https://mmbiz.qpic.cn/...",
    "coverStrategy": "sharp"
  }
}
```

OpenClaw 收到后可以：
- 通过聊天渠道通知用户"文章《XXX》已发布成功"
- 记录到 session 历史中
- 触发后续动作（如发送到其他平台）

### OpenClaw Webhook 接收配置

在 OpenClaw 中注册 webhook handler：

```yaml
# OpenClaw webhook 配置
webhooks:
  md2wechat:
    secret: "your-shared-secret"
    handler: |
      收到公众号发布通知：
      文章「{{data.title}}」已创建草稿
      作者：{{data.author}}
      封面策略：{{data.coverStrategy}}
```

## 辅助脚本说明

`openclaw-skill/` 目录包含以下脚本：

| 脚本 | 用途 | 示例 |
|------|------|------|
| `publish.sh` | 发布单篇文章 | `./publish.sh article.md --theme blue --author "John"` |
| `batch-publish.sh` | 批量发布目录下所有文章 | `./batch-publish.sh ./articles/ --theme green` |
| `history.sh` | 查询发布历史 | `./history.sh --page 1 --size 5 --status draft` |
| `themes.sh` | 列出可用主题 | `./themes.sh` |
| `healthcheck.sh` | 服务健康检查 | `./healthcheck.sh` |

所有脚本都通过环境变量 `MD2WECHAT_URL` 和 `MD2WECHAT_API_KEY` 配置连接信息。

## 扩展方向

### 短期可实现

1. **内容生成 + 发布一体化**
   - 结合 OpenClaw 的 LLM 能力，先生成文章内容，再自动发布
   - 示例："写一篇关于 AI 最新进展的公众号文章并发布"

2. **多公众号管理**
   - 配置多个 md2wechat 实例，每个对应不同公众号
   - 通过 Skill 参数区分目标公众号

3. **发布审批流程**
   - 先生成草稿预览，发送给审批人确认
   - 确认后再触发正式发布

4. **模板化发文**
   - 定义文章模板（周报、日报、产品更新等）
   - 用户只需提供关键数据，自动填充模板后发布

### 中期演进

5. **数据分析集成**
   - 对接公众号阅读数据 API
   - OpenClaw 定期拉取阅读量、点赞数等指标
   - 自然语言查询："上周哪篇文章阅读量最高？"

6. **多平台同步发布**
   - 一篇 Markdown 同时发布到公众号、知乎、掘金等平台
   - 各平台格式自动适配

7. **素材库管理**
   - 管理常用图片、模板、签名等素材
   - "用上次那个蓝色封面发布"

8. **SEO / 标题优化**
   - LLM 分析文章内容，自动生成优化标题和摘要
   - A/B 测试不同标题效果

### 长期愿景

9. **智能排期系统**
   - 基于历史阅读数据分析最佳发布时间
   - 自动调整发布节奏，避免内容堆积

10. **内容工作流引擎**
    - 从选题 → 写作 → 审核 → 发布 → 分析的全链路自动化
    - 多人协作，角色分配

11. **跨平台内容中心**
    - 统一管理所有自媒体平台的内容
    - 一处编辑，多处分发
    - 统一数据看板

## 技术细节

### md2wechat API 概览

| 端点 | 方法 | 功能 |
|------|------|------|
| `/health` | GET | 服务健康检查 |
| `/api/publish` | POST | 发布 Markdown 到公众号草稿 |
| `/api/history` | GET | 查询发布历史记录 |
| `/api/themes` | GET | 列出可用主题 |
| `/api/config` | GET | 获取服务配置信息 |

### 认证方式

通过 `X-API-Key` 请求头传递 API Key（如果服务端配置了 `API_KEY` 环境变量）。

### 发布流程（7 步 Pipeline）

1. **解析 Markdown** — 提取 front matter 元数据
2. **渲染 HTML** — markdown-it 转换 + 主题 CSS 注入
3. **修复 HTML** — 图片上传到微信 CDN + 样式内联
4. **生成封面** — Sharp 本地生成 / AI 生成 / 用户自定义
5. **创建草稿** — 调用微信 API 创建公众号草稿
6. **保存记录** — 写入数据库（SQLite / PostgreSQL）
7. **触发 Webhook** — 异步通知外部系统

### 错误处理

- 网络不可达：提示检查 `MD2WECHAT_URL` 配置
- 认证失败（401）：提示设置 `MD2WECHAT_API_KEY`
- 微信 API 错误（502）：返回微信错误码和详情
- 文件未找到：提示用户确认文件路径

## 安全注意事项

1. **API Key 保护**：不要将 API Key 硬编码在脚本中，使用环境变量
2. **网络隔离**：建议 md2wechat 与 OpenClaw 部署在同一内网
3. **Webhook 验证**：使用共享密钥验证 Webhook 请求来源
4. **权限控制**：OpenClaw 可配置哪些用户有权限触发发布操作
5. **日志审计**：所有发布操作在 md2wechat 数据库中有完整记录

## FAQ

**Q: OpenClaw Skill 和 Plugin 有什么区别？**
A: Skill 是基于自然语言描述的轻量集成，适合 API 调用场景。Plugin 是 TypeScript 代码级集成，适合需要深度定制的场景。对 md2wechat 的集成，Skill 方式最为合适。

**Q: 可以同时管理多个公众号吗？**
A: 可以。部署多个 md2wechat 实例（不同端口），在 OpenClaw Skill 中通过不同的 `MD2WECHAT_URL` 区分即可。

**Q: 发布的是草稿还是直接发布？**
A: md2wechat 创建的是公众号**草稿**，需要在微信公众号后台手动点击"发布"。这是出于安全考虑，避免未经审核的内容直接发布。

**Q: 图片怎么处理？**
A: Markdown 中引用的图片（本地路径或远程 URL）会自动上传到微信 CDN，替换为微信图片链接。无需手动处理。

**Q: 如何调试连接问题？**
A: 运行 `./healthcheck.sh` 确认服务可达，检查 `MD2WECHAT_URL` 和 `MD2WECHAT_API_KEY` 配置是否正确。
