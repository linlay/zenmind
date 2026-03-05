# ZenMind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Repository Type](https://img.shields.io/badge/repo-hub%20portal-blue)](https://github.com/linlay/zenmind)

[默认 (中文)](README.md) | [简体中文独立页](README.zh-CN.md) | [English](README.en.md)

ZenMind 是一个多仓库 Hub，用于统一编排和导航各子项目的部署与运行。

## 当前部署状态（2026-03）

- 当前只保证 macOS 部署链路可用。
- Windows 脚本已改为 fail-fast 占位，防止误用旧拓扑。
- 本轮未更新系统总览图 `docs/media/zenmind-overview.svg`（后续单独同步）。

## 项目组成（5 项）

| 项目 | 状态 | 说明 |
|---|---|---|
| [agent-platform-runner](https://github.com/linlay/agent-platform-runner) | 已接入部署链路 | Agent 运行服务（必选） |
| [agent-platform-admin](https://github.com/linlay/agent-platform-admin) | 占位 | 本轮不实现，不参与 clone/package/start/stop |
| [mcp-server-mock](https://github.com/linlay/mcp-server-mock) | 已接入部署链路 | Go 后端服务（必选） |
| [zenmind-app-server](https://github.com/linlay/zenmind-app-server) | 已接入部署链路 | Go 后端服务（必选） |
| [term-webclient](https://github.com/linlay/term-webclient) | 已接入部署链路 | 非容器启动，Java 直跑（必选） |

## Mac 使用方式

入口脚本：

```bash
./setup-mac.sh
```

常用非交互命令：

```bash
./setup-mac.sh --action precheck
./setup-mac.sh --action first-install
./setup-mac.sh --action update
./setup-mac.sh --action start
./setup-mac.sh --action stop
./setup-mac.sh --action reset-password-hash
```

## 关键行为约束

- CLI action 保持不变：`precheck | first-install | update | start | stop | reset-password-hash`
- `start` 为 4 服务全必选：`zenmind-app-server -> mcp-server-mock -> agent-platform-runner -> term-webclient`
- `stop` 顺序反向：`term-webclient -> agent-platform-runner -> mcp-server-mock -> zenmind-app-server`
- 健康检查统一使用 PID 存活：
- `term-webclient`: `run/backend.pid` + `run/frontend.pid`
- 其他服务：`run/app.pid`
- 任一必选服务失败都会导致 `start` 失败。

## 首次安装与更新

`first-install` / `update` 会：

- 统一 clone 4 个活跃仓库到 `source/<repo>`：
- `term-webclient`
- `zenmind-app-server`
- `agent-platform-runner`
- `mcp-server-mock`
- 执行各仓库 `release-scripts/mac/package*.sh` 打包
- 将打包产物移动到 `release/<repo>`
- 同步配置模板（缺失即失败）：
- `source/term-webclient/.env.example -> release/term-webclient/.env`
- `source/term-webclient/application.example.yml -> release/term-webclient/application.yml`
- `source/zenmind-app-server/.env.example -> release/zenmind-app-server/.env`
- `source/agent-platform-runner/application.example.yml -> release/agent-platform-runner/application.yml`
- `source/mcp-server-mock/.env.example -> release/mcp-server-mock/.env`

密码哈希注入保持不变（仅 term + app）：

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

- Docker/Compose 不再是本拓扑的强依赖。
- `runtime` 模式不再检测 Docker daemon，仅保留可选 nginx 提示。

## Windows 状态

Windows 入口当前为占位保护：

```powershell
.\setup-windows.ps1 -Action precheck
```

会直接 fail-fast 并提示“当前仅支持 mac”。

## License

MIT. See [LICENSE](LICENSE).
