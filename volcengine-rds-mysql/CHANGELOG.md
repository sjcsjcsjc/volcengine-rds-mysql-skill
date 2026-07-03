# Changelog

本项目所有值得记录的变更都记录在此文件中。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.0] - 2026-07-03

首个对外发布版本。

### Added
- 唯一执行入口 `scripts/verds`：自举下载 `ve` CLI（带 sha256 fail-closed 校验）、写/高危操作二次确认护栏、透传 `ve rdsmysqlv2 <Action>`。
- 意图→Action 速查表 `references/actions.md`，按只读/写/高危分级。
- `SKILL.md`「变配执行时机」节，含 `ModifyDBNodeSpec` + `EstimateOnly` 干跑预校验的完整两步示例。
- 发布物：`README.md`、`LICENSE`（Apache-2.0）、`VERSION`、`.gitignore`。

### Fixed
- 规格/存储变配改用 `ModifyDBNodeSpec`：老接口 `ModifyDBInstanceSpec` 已被火山官方弃用，不认云盘规格名 `rds.mysql.c.s.*`（报 `NodeInfo.NodeSpec值无效`）。
- `verds` 护栏放行 `<Action> --help`：查帮助是只读意图，不再被写护栏以退出码 2 拦截。

### Notes
- 本版本 pins `ve` CLI 版本 `1.0.48`（`verds` 内 `VE_VERSION`，属依赖，非本 Skill 版本）。
- 新增变配避坑说明：`SpecStatus: Normal` ≠ 可用区有货（以 `EstimateOnly` 干跑为准）、`ZoneId` 每节点必填、规格族不可跨变、存储类型切换限制。

[1.0.0]: https://www.volcengine.com/product/rds-mysql
