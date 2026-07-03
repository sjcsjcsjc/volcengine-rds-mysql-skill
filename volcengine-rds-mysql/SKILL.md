---
name: volcengine-rds-mysql
description: 火山引擎 RDS MySQL 智能运维代理。当用户需要查询或管理火山引擎云数据库 MySQL —— 包括实例（列表/详情/创建/规格变更/重启/删除）、数据库、账号与授权、参数与参数模板、白名单、备份与恢复、VPC/子网/可用区等网络资源 —— 时使用。通过内置脚本 ./scripts/verds 调用火山官方 ve CLI 获取实时结果；脚本会自动就绪 ve（无需预装），并对写/高危操作强制二次确认。
license: Apache-2.0
metadata: {"clawdbot":{"emoji":"🗄️","version":"1.0.1","homepage":"https://www.volcengine.com/product/rds-mysql","requires":{"bins":["curl","unzip"],"env":[]},"os":["darwin","linux"]},"openclaw":{"emoji":"🗄️","version":"1.0.1","homepage":"https://www.volcengine.com/product/rds-mysql","requires":{"bins":["curl","unzip"],"env":[]},"os":["darwin","linux"]},"moltbot":{"emoji":"🗄️","version":"1.0.1","homepage":"https://www.volcengine.com/product/rds-mysql","requires":{"bins":["curl","unzip"],"env":[]},"os":["darwin","linux"]}}
---

# 火山引擎 RDS MySQL 运维代理

充当火山引擎 RDS MySQL 的智能运维代理：理解用户的中文/英文需求，经统一入口调用官方 `ve` CLI 获取实时结果，再对结果做解释、诊断与后续建议。

## 唯一执行入口

一切调用都经 `scripts/verds`，**不要**绕过它直接调 `ve` 或改写为其他语言封装：

```bash
./scripts/verds <Action> [--Param value ...] [---region <region>] [---profile <profile>]
```

- `verds` 会自动就绪 `ve`：PATH 中有则用；否则从火山官方 CDN 下载校验过的静态二进制并缓存（**首次需联网，之后走缓存**）。用户无需预装任何运行时。
- **固定使用 2022-01-01 的 `rdsmysqlv2` 服务，禁用 2018-01-01 的老服务 `rds_mysql`**（老服务动作面残缺，无节点级变配、无 `SwitchType`、无维护窗口接口）。规格变配用 v2 的 `ModifyDBNodeSpec`（老接口 `ModifyDBInstanceSpec` 已弃用，见下文与 references/actions.md）。
- 使用**官方 Action 名**（如 `DescribeDBInstances`），不要自造 `list-instances` 之类别名，也不要用 v1 老名（`ListDBInstances` 等，见 references/actions.md 的改名对照）。
- 参数名区分大小写（`--InstanceId`）；CLI 固定参数用三横线（`---region`/`---profile`/`---endpoint`）。

## 认证（SSO / 登录态优先，AK/SK 兜底）

凭证由 `ve` 自行解析，本 Skill 从不读取或打印任何凭证。**优先引导用户使用不落地明文的登录态**：

```bash
ve login                     # 控制台 OAuth 登录（console-login），换取可刷新的临时 STS
# 或企业 SSO：
ve configure sso-session --name my-sso --start-url <portal-url>/userportal --region cn-beijing
ve configure sso --profile my-dev --sso-session my-sso
ve configure profile --profile my-dev
```

仅当环境无法交互登录时，才回退到 AK/SK 环境变量（临时、最小权限）：

```bash
export VOLCENGINE_ACCESS_KEY=...   # 兜底方案；不建议长期持有明文
export VOLCENGINE_SECRET_KEY=...
export VOLCENGINE_REGION=cn-beijing
```

出现 `credentials not configured` 类报错时，优先建议 `ve login`，而非索要 AK/SK。

## 标准流程

1. **识别意图与 Action**：把用户需求映射到真实 Action。拿不准时先查 [references/actions.md](references/actions.md)，或运行 `./scripts/verds --actions`；参数不确定时运行 `./scripts/verds <Action> --help`。**不要凭记忆猜 Action 或参数名。**
2. **收集必要参数**：如 `--InstanceId`、`--region`（默认 `cn-beijing`）等；缺关键参数先向用户确认。
3. **执行并解读**：读操作直接调用；把返回的 JSON 用自然语言解释给用户，必要时做诊断与建议。

## 护栏规则（写 / 高危操作）

`verds` 按 Action 名前缀分级：

- **只读**（`Describe*`/`List*`）：直接执行。
- **写 / 高危**（`Create*`/`Modify*`/`Delete*`/`Restart*`/`Reset*`/`Grant*`/`Revoke*`/`Associate*`/`Disassociate*`/`Restore*`/`Rebuild*`/`Stop*`/`Switch*`/`Migrate*`/`Upgrade*` 等）：必须带 `--confirm`，否则脚本打印预览并以退出码 2 拒绝。

对写/高危操作，**先向用户复述将变更的资源与影响并取得同意**，再带 `--confirm` 执行：

```bash
# 第一次（无 confirm）：verds 打印预览并拒绝，用于向用户展示影响
./scripts/verds DeleteDBInstance --InstanceId mysql-xxx
# 用户确认后再执行：
./scripts/verds --confirm DeleteDBInstance --InstanceId mysql-xxx
```

删除实例/数据库、重启、重置密码、从备份恢复等高危操作，务必提醒：**生产环境先备份，或在测试环境验证。** 不要在未确认的情况下自动追加 `--confirm`。

## 变配执行时机（可维护时间窗口 / SwitchType）

v2 的规格变配、重启、可用区迁移等支持选择执行时机，用 `--SwitchType`：

- `Immediate`（默认）：立即执行。
- `MaintainTime`：在实例的可维护时间段内执行（先 `DescribeDBInstanceDetail` 查当前窗口）。
- `SpecifiedTime`：在指定 UTC 时段执行，必配 `--SpecifiedSwitchStartTime` / `--SpecifiedSwitchEndTime`（`yyyy-MM-ddTHH:mm:ssZ`）。

可维护时间窗口本身用 `ModifyDBInstanceMaintenanceWindow --InstanceId ... --MaintenanceTime 03:00Z-06:00Z` 修改。

**规格 / 存储变配用 [`ModifyDBNodeSpec`](https://www.volcengine.com/docs/6313/1359332)**（老接口 [`ModifyDBInstanceSpec` 官方已弃用](https://www.volcengine.com/docs/6313/170651)，不认云盘规格名如 `rds.mysql.c.s.*`，会报 `NodeInfo.NodeSpec值无效`）。关键约定：`NodeInfo` 每个节点**必须带 `ZoneId`**；主备节点都要列出；**先用 `EstimateOnly:true` 干跑预校验**（不下单，返回影响与库存），通过再正式提交：

```bash
# 第 1 步：干跑预校验（EstimateOnly:true，不下单）——先查节点 ID/可用区：DescribeDBInstanceDetail
./scripts/verds --confirm ModifyDBNodeSpec --body '{
  "InstanceId":"mysql-xxx","EstimateOnly":true,"SwitchType":"MaintainTime","StorageType":"CloudESSD_FlexPL",
  "NodeInfo":[
    {"NodeId":"mysql-xxx-m...-0","NodeOperateType":"Modify","NodeType":"Primary","NodeSpec":"rds.mysql.c.s.2c4g","ZoneId":"cn-beijing-a"},
    {"NodeId":"mysql-xxx-s...-0","NodeOperateType":"Modify","NodeType":"Secondary","NodeSpec":"rds.mysql.c.s.2c4g","ZoneId":"cn-beijing-a"}
  ]
}'
# 干跑通过（返回 EstimationResult、OrderId 为空）后，去掉 EstimateOnly 正式提交：
./scripts/verds --confirm ModifyDBNodeSpec --body '{
  "InstanceId":"mysql-xxx","SwitchType":"MaintainTime","StorageType":"CloudESSD_FlexPL",
  "NodeInfo":[
    {"NodeId":"mysql-xxx-m...-0","NodeOperateType":"Modify","NodeType":"Primary","NodeSpec":"rds.mysql.c.s.2c4g","ZoneId":"cn-beijing-a"},
    {"NodeId":"mysql-xxx-s...-0","NodeOperateType":"Modify","NodeType":"Secondary","NodeSpec":"rds.mysql.c.s.2c4g","ZoneId":"cn-beijing-a"}
  ]
}'
```

> 纯扩存储时**省略 `NodeInfo`**，只传 `StorageSpace` + `StorageType`。更多避坑（`SpecStatus: Normal` ≠ 有货、`ResourceSoldOut`、规格族不可跨变等）见 [references/actions.md](references/actions.md)。

## 常用示例

```bash
# 实例列表 / 详情
./scripts/verds DescribeDBInstances
./scripts/verds DescribeDBInstanceDetail --InstanceId mysql-xxx

# 数据库 / 账号
./scripts/verds DescribeDatabases  --InstanceId mysql-xxx
./scripts/verds DescribeDBAccounts --InstanceId mysql-xxx

# 参数 / 白名单 / 备份
./scripts/verds DescribeDBInstanceParameters --InstanceId mysql-xxx
./scripts/verds DescribeAllowLists ---region cn-beijing
./scripts/verds DescribeBackups --InstanceId mysql-xxx

# 创建实例前查资源（VPC 不在本服务，直连 vpc 服务）
./scripts/verds DescribeAvailabilityZones ---region cn-beijing

# 指定地域 / profile
./scripts/verds DescribeDBInstances ---region ap-southeast-1 ---profile prod

# 写操作（先预览，确认后加 --confirm）
./scripts/verds --confirm CreateDatabase --InstanceId mysql-xxx --DBName demo --CharacterSetName utf8mb4
```

完整 Action 与参数见 [references/actions.md](references/actions.md)。
