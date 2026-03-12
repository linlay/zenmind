# ZenMind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Repository Type](https://img.shields.io/badge/repo-hub%20portal-blue)](https://github.com/linlay/zenmind)

[默认 (中文)](README.md) | [简体中文独立页](README.zh-CN.md) | [English](README.en.md)

ZenMind 是一个面向 AI Agent 工作流的多仓库 Hub。

## 2026-03 部署基线

- 当前支持 macOS 与 Linux 部署链路。
- Windows 主系统不再直接安装；请进入 WSL 后使用 WSL 入口脚本。
- 系统总览图 `docs/media/zenmind-overview.svg` 本轮不变更。

## 子项目（5 项）

| 项目 | 状态 | 说明 |
|---|---|---|
| [zenmind-gateway](https://github.com/linlay/zenmind-gateway) | 已接入 | 网关服务 |
| [zenmind-app-server](https://github.com/linlay/zenmind-app-server) | 已接入 | 应用后端服务 |
| [mcp-server-mock](https://github.com/linlay/mcp-server-mock) | 已接入 | Mock MCP 服务 |
| [mcp-server-bash](https://github.com/linlay/mcp-server-bash) | 已接入 | Bash MCP 服务 |
| [mcp-server-email](https://github.com/linlay/mcp-server-email) | 已接入 | Email MCP 服务 |

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
./setup-mac.sh --action configure-startup
./setup-mac.sh --action reset-password-hash
```

## Linux 部署入口

```bash
./setup-linux.sh
```

非交互动作：

```bash
./setup-linux.sh --action precheck
./setup-linux.sh --action first-install
./setup-linux.sh --action update
./setup-linux.sh --action start
./setup-linux.sh --action stop
./setup-linux.sh --action configure-startup
./setup-linux.sh --action reset-password-hash
```

## Windows WSL 部署入口

请先进入 WSL 发行版 shell，再执行：

```bash
./setup-win-wsl.sh
```

非交互动作：

```bash
./setup-win-wsl.sh --action precheck
./setup-win-wsl.sh --action first-install
./setup-win-wsl.sh --action update
./setup-win-wsl.sh --action start
./setup-win-wsl.sh --action stop
./setup-win-wsl.sh --action configure-startup
./setup-win-wsl.sh --action reset-password-hash
```

## 启动列表配置

- 启动列表文件：`config/startup-services.conf`
- 文件格式：纯文本，一行一个服务
- 空行和 `#` 注释会被忽略
- 行顺序即启动顺序，停止时自动反向
- 默认顺序：
  - `zenmind-gateway`
  - `zenmind-app-server`
  - `mcp-server-mock`
  - `mcp-server-bash`
  - `mcp-server-email`
- 如果文件缺失，脚本会自动初始化为默认内容

交互菜单新增：

- `6) 配置启动列表`

执行后会逐个询问服务是否启用，并覆盖写回 `config/startup-services.conf`。

## 行为约束

- CLI action：`precheck | first-install | update | start | stop | configure-startup | reset-password-hash`
- `start` 不再固定全启，而是按 `config/startup-services.conf` 中声明的服务和顺序执行
- `stop` 只处理 `config/startup-services.conf` 中启用的服务，顺序自动反向
- 健康检查统一基于 `run/app.pid`
- `startup-services.conf` 中若出现未知服务、重复服务或空列表，脚本会直接报错
- 任一启用服务启动失败都会导致 `start` 失败

## 安装/更新流程

`first-install` / `update` 会执行：

- clone 5 个活跃仓库到 `source/<repo>`
  - `zenmind-gateway`
  - `zenmind-app-server`
  - `mcp-server-mock`
  - `mcp-server-bash`
  - `mcp-server-email`
- `setup-mac.sh` 调用各仓库 `release-scripts/mac/package.sh`
- `setup-linux.sh` / `setup-win-wsl.sh` 调用各仓库 `release-scripts/linux/package.sh`
- 将产物移动到 `release/<repo>`
- 同步当前已定义的配置模板：
  - `source/zenmind-app-server/.env.example -> release/zenmind-app-server/.env`
  - `source/mcp-server-mock/.env.example -> release/mcp-server-mock/.env`
- 若 `config/startup-services.conf` 缺失，则自动生成默认启动列表

密码哈希自动注入：

- `release/zenmind-app-server/.env`
  - `AUTH_ADMIN_PASSWORD_BCRYPT`
  - `AUTH_APP_MASTER_PASSWORD_BCRYPT`

## 环境依赖（mac / linux）

`precheck` install 模式必检：

- `git`
- `go >= 1.26.0`
- `java >= 21`
- `maven >= 3.9`
- `node >= 20`
- `npm`

说明：

- Docker/Compose 不是本仓库 setup 的强依赖。
- `runtime` 模式按环境检查脚本当前定义执行。
- Linux / WSL 的修复提示以 Ubuntu/Debian 为基线。

## Windows 状态

运行以下命令会直接 fail-fast：

```powershell
.\setup-windows.ps1 -Action precheck
```

请先进入 WSL，再执行 `./setup-win-wsl.sh --action precheck`。

## License

MIT. See [LICENSE](LICENSE).
