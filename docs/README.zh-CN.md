# ZenMind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Repository Type](https://img.shields.io/badge/repo-hub%20portal-blue)](https://github.com/linlay/zenmind)

[默认 (中文)](README.md) | [简体中文独立页](README.zh-CN.md) | [English](README.en.md)

ZenMind 是一个面向 AI Agent 工作流的多仓库 Hub。

## 2026-03 部署基线

- 当前仅保证 macOS 可用。
- Windows setup 已改为 fail-fast 占位。
- 系统总览图 `docs/media/zenmind-overview.svg` 本轮不变更。

## 子项目（5 项）

| 项目 | 状态 | 说明 |
|---|---|---|
| [agent-platform-runner](https://github.com/linlay/agent-platform-runner) | 已接入 | Agent 运行服务（必选） |
| [agent-platform-admin](https://github.com/linlay/agent-platform-admin) | 占位 | 本轮不实现，不参与部署动作 |
| [mcp-server-mock](https://github.com/linlay/mcp-server-mock) | 已接入 | Go 后端服务（必选） |
| [zenmind-app-server](https://github.com/linlay/zenmind-app-server) | 已接入 | Go 后端服务（必选） |
| [term-webclient](https://github.com/linlay/term-webclient) | 已接入 | 非容器启动，Java 直跑（必选） |

## Mac 部署入口

```bash
./setup-mac.sh
```

非交互动作：

```bash
./setup-mac.sh --action precheck
./setup-mac.sh --action first-install
./setup-mac.sh --action update
./setup-mac.sh --action start
./setup-mac.sh --action stop
./setup-mac.sh --action reset-password-hash
```

## 行为约束

- CLI action 不变：`precheck | first-install | update | start | stop | reset-password-hash`
- 启动顺序（全必选）：`zenmind-app-server -> mcp-server-mock -> agent-platform-runner -> term-webclient`
- 停止顺序（反向）：`term-webclient -> agent-platform-runner -> mcp-server-mock -> zenmind-app-server`
- 健康检查统一基于 PID：
- `term-webclient`: `run/backend.pid` + `run/frontend.pid`
- 其他服务：`run/app.pid`
- 任一必选服务失败会导致 `start` 失败。

## 安装/更新流程

`first-install` / `update` 会执行：

- clone 4 个活跃仓库到 `source/<repo>`
- 调用各仓库 `release-scripts/mac/package*.sh`
- 将产物移动到 `release/<repo>`
- 同步配置模板（缺失即失败）：
- `source/term-webclient/.env.example -> release/term-webclient/.env`
- `source/term-webclient/application.example.yml -> release/term-webclient/application.yml`
- `source/zenmind-app-server/.env.example -> release/zenmind-app-server/.env`
- `source/agent-platform-runner/application.example.yml -> release/agent-platform-runner/application.yml`
- `source/mcp-server-mock/.env.example -> release/mcp-server-mock/.env`

密码哈希自动注入保留：

- `release/term-webclient/.env`: `AUTH_PASSWORD_HASH_BCRYPT`
- `release/zenmind-app-server/.env`: `AUTH_ADMIN_PASSWORD_BCRYPT`、`AUTH_APP_MASTER_PASSWORD_BCRYPT`

## 环境依赖（mac）

`precheck` install 模式必检：

- `git`
- `go >= 1.26.0`
- `java >= 21`
- `maven >= 3.9`
- `node >= 20`
- `npm`

说明：

- Docker/Compose 不再是强依赖。
- runtime 模式不再检查 Docker daemon，仅保留 nginx 可选提示。

## Windows 占位说明

运行以下命令会直接 fail-fast：

```powershell
.\setup-windows.ps1 -Action precheck
```

请改用 mac 入口执行部署。

## License

MIT. See [LICENSE](LICENSE).
