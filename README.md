# mysql-skill

火山引擎 RDS MySQL 智能运维 Agent Skill 的发布仓库。

实际的 Skill 位于 [`volcengine-rds-mysql/`](volcengine-rds-mysql/) —— 一个遵循开放 [Agent Skills](https://agentskills.io) 标准的自包含发布单元，可在 Claude Code、Cursor、Codex CLI 等兼容工具中使用。

- 使用说明、安装、认证、安全与护栏：见 [`volcengine-rds-mysql/README.md`](volcengine-rds-mysql/README.md)
- 意图→Action 速查：见 [`volcengine-rds-mysql/references/actions.md`](volcengine-rds-mysql/references/actions.md)

## 打包发布

```bash
sh tools/pack.sh
# 产物在 dist/：volcengine-rds-mysql-v<VERSION>.{zip,tar.gz} 及 .sha256
```

## License

[Apache-2.0](LICENSE)。`ve` CLI 属火山引擎，遵循其自身许可。
