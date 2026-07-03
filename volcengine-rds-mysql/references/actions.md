# RDS MySQL Action 速查表（2022-01-01 / rdsmysqlv2）

> 权威来源：`ve rdsmysqlv2 --help` 与 `ve rdsmysqlv2 <Action> --help`。
> 本表由实机导出，请勿凭记忆猜测 Action 名。如与线上不一致，一律以 `./scripts/verds --actions` 及 `--help` 输出为准。
>
> **版本约定：本 Skill 固定使用 2022-01-01 的 `rdsmysqlv2` 服务，禁用 2018-01-01 的老服务 `rds_mysql`。**
> 老服务动作面残缺（`ModifyDBInstance` 只能改规格、无 `SwitchType`、无维护窗口接口），已废弃。
>
> 调用统一走入口脚本：
> ```
> ./scripts/verds <Action> [--Param value ...] [---region <region>] [---profile <profile>]
> ```
> 参数名区分大小写，形如 `--InstanceId mysql-xxx`；固定参数用三横线 `---region` / `---profile` / `---endpoint`。

## v1 → v2 关键改名（老习惯请更正）

| 老（2018-01-01，已禁用） | 新（2022-01-01，rdsmysqlv2） |
|---|---|
| `ListDBInstances` | `DescribeDBInstances` |
| `DescribeDBInstance` | `DescribeDBInstanceDetail` |
| `ListDatabases` | `DescribeDatabases` |
| `ListAccounts` | `DescribeDBAccounts` |
| `ListInstanceParams` | `DescribeDBInstanceParameters` |
| `ListInstanceParamsHistory` | `DescribeDBInstanceParametersLog` |
| `ListBackups` | `DescribeBackups` |
| `ListZones` | `DescribeAvailabilityZones` |
| `CreateAccount` / `DeleteAccount` | `CreateDBAccount` / `DeleteDBAccount` |
| `GrantAccountPrivilege` | `GrantDBAccountPrivilege` |
| `ResetAccountPassword` | `ResetDBAccount` |
| `ModifyInstanceParams` | `ModifyDBInstanceParameters` |
| `ModifyDBInstance`（改规格） | `ModifyDBNodeSpec`（老接口 `ModifyDBInstanceSpec` 已弃用） |
| `ListRegions` | `DescribeRegions` |
| `ListVpcs`（网络资源） | 不在 rdsmysqlv2 内，改用 `ve vpc DescribeVpcs`（另一服务） |

## 风险分级说明

| 级别 | 匹配 | verds 行为 |
|------|------|-----------|
| 只读 | `Describe*`、`List*` | 直接执行 |
| 写 | `Create*`、`Modify*`、`Grant*`、`Revoke*`、`Associate*`、`Sync*`、`Add*`、`Remove*`、`Copy*`、`SaveAs*`、`Download*`、`Get*` | 需 `--confirm` |
| 高危 | `Delete*`、`Restart*`、`Reset*`、`Recovery*`、`Restore*`、`Rebuild*`、`Stop*`、`Disassociate*`、`Switch*`、`Migrate*`、`UpgradeDBInstanceEngineMajorVersion` | 需 `--confirm`，并强提示备份 |

---

## 可维护时间窗口 & 变配执行时机（重点）

v2 支持把变配/重启等放到「可维护时间窗口」执行，这是 v1 完全没有的能力。

### SwitchType（多数变更类 Action 通用）

`ModifyDBNodeSpec` / `ModifyDBInstanceType` / `RestartDBInstance` / `MigrateToOtherZone` / `UpgradeDBInstanceEngineMinorVersion` 等均支持 `--SwitchType`：

| 取值 | 含义 | 配套参数 |
|------|------|---------|
| `Immediate` | 立即执行（默认） | — |
| `MaintainTime` | 在实例的可维护时间段内执行 | 先用 `DescribeDBInstanceDetail` 查当前窗口 |
| `SpecifiedTime` | 在指定 UTC 时间段执行 | 必填 `--SpecifiedSwitchStartTime` `--SpecifiedSwitchEndTime`（格式 `yyyy-MM-ddTHH:mm:ssZ`） |

> 说明：多节点实例的规格变配目前多数仅支持 `Immediate`。指定时间段最短约 2 小时、不支持跨天。

### 设置可维护时间窗口本身

| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 修改可维护时间窗口 | `ModifyDBInstanceMaintenanceWindow` | `--InstanceId` `--MaintenanceTime`（如 `03:00Z-06:00Z`）；可选 `--DayKind` `--DayOfWeek` |

### 变配避坑（实操教训，务必先读）

规格 / 存储变配统一用 **`ModifyDBNodeSpec`**（老接口 `ModifyDBInstanceSpec` 已弃用）。以下是实操中真实踩过的坑：

1. **先干跑，再下单**：`ModifyDBNodeSpec` 支持 `"EstimateOnly":true`——**不下单**，仅校验参数并返回影响与库存。干跑通过（返回 `EstimationResult`，其 `Plans` 如 `RebuildPrimary`/`RebuildSecondary`、`Effects` 如 `ReadWriteConnectionTransientError`；`OrderId` 为空）后，再去掉 `EstimateOnly` 正式提交。**变配前一律先干跑。**
2. **`NodeInfo` 每个节点必须带 `ZoneId`**：否则报 `nodeInfo.ZoneId值无效`。节点的 `NodeId` / `ZoneId` 从 `DescribeDBInstanceDetail` 的 `NodeDetailInfo` 取。主备节点都要列出。
3. **纯扩存储时省略 `NodeInfo`**：只传 `StorageSpace` + `StorageType` 即可；若带上 `NodeInfo` 且规格名格式不符，反而报错。
4. **`SpecStatus: Normal` ≠ 当前可用区有货**：`DescribeDBInstanceSpecs` 返回的 `Normal` 只表示该规格“存在”，不代表目标可用区此刻有资源。真实库存以 `EstimateOnly` 干跑为准——售罄会报 `OperationDenied.ResourceSoldOut`，此时换规格 / 换可用区 / 换地域。
5. **规格族不可跨变**：共享型 `rds.mysql.c.s.*` ↔ 独享型 `rds.mysql.d1.*` / ARM `rds.mysql.d1.n.arm.*` 之间不能互相变配（报 `NodeSpec值无效`），只能在同族内升降配。
6. **存储类型切换受限**：`LocalSSD`（本地盘）、`CloudESSD_FlexPL` 不支持切换存储类型；仅 `CloudESSD_PL0` 可切到 `CloudESSD_FlexPL`。云盘不支持缩容。

```bash
# 完整两步示例见 SKILL.md「变配执行时机」节；查参数用：
./scripts/verds ModifyDBNodeSpec --help
```

---

## 只读（Describe* / List*）— 直接执行

### 实例
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 实例列表 | `DescribeDBInstances` | 可选过滤：`--InstanceId` `--InstanceName` `--InstanceStatus` `--InstanceType` `--PageNumber` `--PageSize` 等 |
| 实例详情 | `DescribeDBInstanceDetail` | `--InstanceId`（必填） |
| 实例属性 | `DescribeDBInstanceAttribute` | `--InstanceId` |
| 实例节点详情 | `DescribeDBInstanceNodes` | `--InstanceId` |
| 连接地址列表 | `DescribeDBInstanceEndpoints` | `--InstanceId` |
| 高可用配置 | `DescribeDBInstanceHAConfig` | `--InstanceId` |
| 支持的规格 | `DescribeDBInstanceSpecs` | 可选过滤 |
| 计费信息 | `DescribeDBInstanceChargeDetail` | `--InstanceId` |
| 资源使用情况 | `DescribeResourceUsage` | `--InstanceId` |
| 主备切换日志 | `DescribeFailoverLogs` | `--InstanceId` |
| 运维事件列表 | `DescribePlannedEvents` | 可选过滤 |
| 已删除实例列表 | `DescribeDeletedDBInstances` | 可选过滤 |

### 数据库 / 账号
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 数据库列表 | `DescribeDatabases` | `--InstanceId` |
| 账号列表 | `DescribeDBAccounts` | `--InstanceId` |
| 表列权限信息 | `DescribeDbAccountTableColumnInfo` | `--InstanceId` `--AccountName` |

### 参数 / 参数模板
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 实例当前参数 | `DescribeDBInstanceParameters` | `--InstanceId` |
| 参数修改历史 | `DescribeDBInstanceParametersLog` | `--InstanceId` |
| 参数模板列表 | `ListParameterTemplates` | 可选分页 |
| 参数模板详情 | `DescribeParameterTemplate` | `--TemplateId` |
| 应用模板的参数变化预览 | `DescribeApplyParameterTemplate` | `--InstanceId` `--TemplateId` |
| 节点参数差异 | `DescribeDBNodeParameterDifferences` | `--InstanceId` |

### 白名单 / 备份 / 恢复
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 白名单列表 | `DescribeAllowLists` | 可选 `---region` |
| 白名单详情 | `DescribeAllowListDetail` | `--AllowListId` |
| 备份列表 | `DescribeBackups` | `--InstanceId` |
| 备份策略 | `DescribeBackupPolicy` | `--InstanceId` |
| Binlog 备份文件 | `DescribeBinlogFiles` | `--InstanceId` |
| 可恢复时间范围 | `DescribeRecoverableTime` | `--InstanceId` |
| 获取备份下载链接 | `GetBackupDownloadLink` | `--InstanceId` `--BackupId` |

### 代理 / 诊断 / 灾备 / 蓝绿
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 代理配置 | `DescribeDBProxy` / `DescribeDBProxyConfig` | `--InstanceId` |
| 连接诊断结果 | `DescribeDiagnosticsInfos` | `--InstanceId` |
| 灾备实例信息 | `DescribeDBDisasterRecoveryInstances` | `--InstanceId` |
| 蓝绿部署信息 | `DescribeDBBlueGreenInstance` | `--InstanceId` |
| 任务列表 / 详情 | `DescribeTasks` / `DescribeTaskDetail` | 可选过滤 |

### 资源 / 地域
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 地域列表 | `DescribeRegions` | — |
| 可用区列表 | `DescribeAvailabilityZones` | `---region` |
| VPC 列表 | （不在本服务）`ve vpc DescribeVpcs ---region <r>` | 直连 vpc 服务，不经 verds |

---

## 写（需 `--confirm`）

### 实例规格 / 节点 / 类型（含 SwitchType）
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| **变更节点规格 / 存储（主推）** | `ModifyDBNodeSpec` | `--InstanceId` `--NodeInfo`(array，每节点含 `NodeId`/`NodeType`/`NodeSpec`/`NodeOperateType`/**`ZoneId`**) `--StorageSpace` `--StorageType` `--SwitchType` `--EstimateOnly`（干跑预校验，见下节） |
| ~~变更实例配置（规格/存储）~~ | ~~`ModifyDBInstanceSpec`~~ **已弃用** | 官方已弃用，不认云盘规格名 `rds.mysql.c.s.*`（报 `NodeInfo.NodeSpec值无效`）。请改用 `ModifyDBNodeSpec` |
| 临时升配 | `ModifyDBNodeTemporarySpec` | `--InstanceId` `--NodeInfo` |
| 修改实例类型（单/双/多节点） | `ModifyDBInstanceType` | `--InstanceId` `--NodeInfo` `--TypeConvertPath`；`--SwitchType` |
| 增加节点 | `CreateDBNodes` | `--InstanceId` `--NodeInfo` |
| 修改实例名称 | `ModifyDBInstanceName` | `--InstanceId` `--InstanceName` |
| 修改可维护时间窗口 | `ModifyDBInstanceMaintenanceWindow` | `--InstanceId` `--MaintenanceTime` |
| 修改计费方式 | `ModifyDBInstanceChargeType` | `--InstanceId` |
| 设置删除保护 | `ModifyDBInstanceDeletionProtectionPolicy` | `--InstanceId` |
| 全局只读开关 | `ModifyDBInstanceGlobalReadOnly` | `--InstanceId` |
| 数据同步方式 | `ModifyDBInstanceSyncMode` | `--InstanceId` |
| 创建实例 | `CreateDBInstance` | 规格/网络/计费等，详见 `--help` |

### 数据库 / 账号
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 创建数据库 | `CreateDatabase` | `--InstanceId` `--DBName`；可选 `--CharacterSetName` `--DBDesc` |
| 创建账号 | `CreateDBAccount` | `--InstanceId` `--AccountName` `--AccountPassword`；可选 `--AccountType` `--Host` |
| 授予账号权限 | `GrantDBAccountPrivilege` | `--InstanceId` `--AccountName` `--AccountPrivileges` |
| 撤销账号权限 | `RevokeDBAccountPrivilege` | `--InstanceId` `--AccountName` |
| 修改账号可访问 IP | `ModifyDBAccountHost` | `--InstanceId` `--AccountName` `--Host` |

### 参数 / 模板 / 备份 / 白名单
| 中文意图 | Action | 关键参数 |
|---------|--------|---------|
| 修改实例参数 | `ModifyDBInstanceParameters` | `--InstanceId` + 参数键值；可选 `--ScheduleType MaintainTime` |
| 创建备份 | `CreateBackup` | `--InstanceId`；可选 `--BackupType` `--BackupMethod` |
| 修改备份策略 | `ModifyBackupPolicy` | `--InstanceId` |
| 创建白名单 | `CreateAllowList` | `--AllowListName` `--AllowList` |
| 修改白名单 | `ModifyAllowList` | `--AllowListId` + 变更项 |
| 绑定白名单到实例 | `AssociateAllowList` | `--AllowListIds` `--InstanceIds` |
| 创建/修改参数模板 | `CreateParameterTemplate` / `ModifyParameterTemplate` | 模板定义 / `--TemplateId` |
| 存为参数模板 | `SaveAsParameterTemplate` | `--InstanceId` |

---

## 高危（需 `--confirm`，务必先备份）

| 中文意图 | Action | 关键参数 | 风险 |
|---------|--------|---------|------|
| 删除实例 | `DeleteDBInstance` | `--InstanceId`；可选 `--DataKeepPolicy` `--DataKeepDays` | 实例及数据释放 |
| 重启实例 | `RestartDBInstance` | `--InstanceId`；`--SwitchType` 可延后到窗口 | 连接中断 |
| 暂停 / 启动实例 | `StopDBInstance` / `StartDBInstance` | `--InstanceId` | 服务中断 |
| 重置账号密码 | `ResetDBAccount` | `--InstanceId` `--AccountName` `--AccountPassword` | 旧密码即时失效 |
| 删除数据库 | `DeleteDatabase` | `--InstanceId` `--DBName` | 库数据丢失 |
| 删除账号 | `DeleteDBAccount` | `--InstanceId` `--AccountName` | 账号失效 |
| 恢复到新/已有实例 | `RestoreToNewInstance` / `RestoreToExistedInstance` | `--InstanceId` 等 | 数据覆盖风险 |
| 跨地域备份恢复 | `RestoreToCrossRegionInstance` | 详见 `--help` | 数据覆盖风险 |
| 通过备份重建实例 | `RebuildDBInstance` | 详见 `--help` | 数据覆盖风险 |
| 主备切换 | `SwitchDBInstanceHA` | `--InstanceId` | 触发主备切换、闪断 |
| 蓝绿切换 | `SwitchDBBlueGreen` | 详见 `--help` | 流量切换 |
| 灾备升主 | `SwitchDrInstanceToMaster` | 详见 `--help` | 拓扑变更 |
| 迁移可用区 | `MigrateToOtherZone` | `--InstanceId` `--NodeInfo`；`--SwitchType` | 节点迁移、闪断 |
| 升级大版本 | `UpgradeDBInstanceEngineMajorVersion` | 详见 `--help`；建议先 `...Precheck` | 大版本升级不可逆 |
| 删除白名单 | `DeleteAllowList` | `--AllowListId` | 关联实例访问受影响 |
| 解绑白名单 | `DisassociateAllowList` | `--AllowListIds` `--InstanceIds` | 访问策略变更 |

---

## 查询单个 Action 的完整参数

任何拿不准的参数，直接查实机帮助（不要猜）：
```
./scripts/verds <Action> --help
# 例如
./scripts/verds ModifyDBNodeSpec --help
```
`ContentType` 为 `application/json` 的接口也支持 `--body '{...}'` 整体传入。
