# Volcengine RDS MySQL — Agent Skill

火山引擎云数据库 MySQL 的智能运维 Agent Skill。遵循开放的 [Agent Skills](https://agentskills.io) 标准（`SKILL.md` + `scripts/` + `references/` 文件夹形态，渐进式披露），可在 Claude Code、Cursor、Codex CLI、Gemini CLI 等兼容工具中使用。

它把自然语言运维意图翻译成对火山官方 `ve` CLI 的实时调用，再对返回结果做解释、诊断与后续建议。

---

## 1. 这是什么

一个"知道怎么正确运维火山 RDS MySQL"的能力包。能力速览：

- **实例**：列表 / 详情 / 创建 / 规格变更 / 重启 / 删除
- **数据库 / 账号**：增删、授权 / 撤权、可访问 IP
- **参数 / 参数模板**：查询、修改、模板管理
- **白名单**：查询、创建、绑定 / 解绑
- **备份与恢复**：备份列表、策略、可恢复时间、恢复到新/已有实例
- **网络 / 资源**：VPC / 子网 / 可用区 / 地域

## 2. 工作原理

所有调用统一经唯一入口脚本 `scripts/verds`，透传到 `ve rdsmysqlv2 <Action>`（2022-01-01 API）：

```
你的自然语言需求
      │
      ▼
scripts/verds <Action> --Param value      ← 唯一入口，带写/高危护栏
      │
      ▼
ve rdsmysqlv2 <Action>                     ← 火山官方 CLI，实时结果
      │
      ▼
JSON 结果 → 解释 / 诊断 / 建议
```

固定使用 `rdsmysqlv2` 服务，一律用官方 Action 名（如 `DescribeDBInstances`）。

## 3. 依赖要求

- **操作系统**：macOS（darwin）/ Linux
- **运行时命令**：`sh`、`curl`、`unzip`、`sha256sum` 或 `shasum`、`awk`、`uname`、`mktemp`（绝大多数系统自带）
- **网络**：**首次**需联网，由 `verds` 自动从火山官方 CDN 下载 `ve` 静态二进制并缓存；之后走缓存离线可用
- **无需**预装 `ve` / Python / Node.js 等任何运行时

## 4. 安装

**方式一：从注册表安装**（若已发布到 skill 注册表）

按所用注册表的安装命令安装 `volcengine-rds-mysql` 即可。

**方式二：解压分发包**

将发布包解压到你的 agent skills 目录，例如：

```bash
unzip volcengine-rds-mysql-v1.0.0.zip -d ~/.claude/skills/
```

**方式三：Git**

```bash
git clone <repo> && cp -r mysql-skill/volcengine-rds-mysql ~/.claude/skills/
```

若脚本执行位丢失，补一句 `chmod +x scripts/verds` 即可。首次运行会自动就绪 `ve`。

## 5. 认证

凭证由 `ve` 自行解析，**本 Skill 从不读取或打印任何凭证**。优先使用不落地明文的登录态：

```bash
ve login                     # 控制台 OAuth 登录，换取可刷新的临时 STS
# 或企业 SSO：
ve configure sso-session --name my-sso --start-url <portal-url>/userportal --region cn-beijing
ve configure sso --profile my-dev --sso-session my-sso
```

仅当环境无法交互登录时，才回退到 AK/SK 环境变量（临时、最小权限，不建议长期持有明文）：

```bash
export VOLCENGINE_ACCESS_KEY=...
export VOLCENGINE_SECRET_KEY=...
export VOLCENGINE_REGION=cn-beijing
```

## 6. 安全与护栏

**二进制来源可信 + 完整性校验（fail-closed）**

`verds` 从火山官方 CDN（`cloudcache.volccdn.com/ve`）下载 `ve` 静态二进制，同时下载官方 `SHA256SUMS` 并**逐档校验 sha256**；校验不通过即**拒绝执行**（fail-closed），绝不运行未经校验的二进制。缓存命中时按基线二次校验。可通过 `VOLCENGINE_CLI_DOWNLOAD_BASE_URL` 指向自有镜像，用于离线 / 内网分发。

**写 / 高危操作强制二次确认**

`verds` 按 Action 名前缀分级：

- 只读（`Describe*` / `List*`）：直接执行
- 写 / 高危（`Create*` / `Modify*` / `Delete*` / `Restart*` / `Reset*` / `Switch*` / `Migrate*` 等）：**必须带 `--confirm`**，否则打印预览并以退出码 2 拒绝
- 删除 / 重启 / 重置 / 恢复等高危操作，额外强提示：**生产环境先备份，或在测试环境验证**

> 护栏边界：这不是内核级沙箱，而是"唯一文档化入口 + 语义规则 + 宿主审批"三层叠加，请勿当作硬隔离。

## 7. 支持范围

分只读 / 写 / 高危三档，完整意图→Action 速查见 [`references/actions.md`](references/actions.md)，或运行：

```bash
./scripts/verds --actions          # 列出全部真实 Action
./scripts/verds <Action> --help    # 查单个 Action 的参数
```

## 8. 可选环境变量

| 变量 | 作用 |
|------|------|
| `VERDS_VE_VERSION` | 覆盖默认下载的 `ve` 版本 |
| `VOLCENGINE_CLI_DOWNLOAD_BASE_URL` | 覆盖二进制下载源（自有镜像 / 内网） |
| `VERDS_SKIP_CACHE_VERIFY` | 跳过缓存命中时的完整性校验（**不推荐**，会削弱安全保证） |

## 9. 免责声明

- 本 Skill 操作的是你**自己账号下的真实云资源**，变更（尤其删除 / 重启 / 恢复）由你自行负责。
- 高危操作请务必**先备份或在测试环境验证**。规格变配前建议先用 `ModifyDBNodeSpec` 的 `EstimateOnly:true` 干跑预校验。
- 按 "AS IS" 提供，不含任何明示或默示担保。

## 10. License

本 Skill 以 [Apache-2.0](LICENSE) 许可发布。

`ve` CLI 是火山引擎的独立产品，遵循其自身许可协议，本 Skill 仅在运行时调用它、不分发其二进制。
