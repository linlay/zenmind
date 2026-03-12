# ZenMind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Repository Type](https://img.shields.io/badge/repo-hub%20portal-blue)](https://github.com/linlay/zenmind)

[默认 (中文)](README.md) | [简体中文独立页](README.zh-CN.md) | [English](README.en.md)

ZenMind 是一个多仓库 Hub，用于统一编排和导航各子项目的部署与运行。

## 当前部署状态（2026-03）

- 当前支持 macOS 与 Linux 部署链路。
- Windows 主系统不再直接安装；请进入 WSL 后使用 WSL 入口脚本。
- 本轮未更新系统总览图 `docs/media/zenmind-overview.svg`。

## 项目组成（5 项）

| 项目 | 状态 | 说明 |
|---|---|---|
| [zenmind-gateway](https://github.com/linlay/zenmind-gateway) | 已接入部署链路 | 网关服务 |
| [zenmind-app-server](https://github.com/linlay/zenmind-app-server) | 已接入部署链路 | 应用后端服务 |
| [mcp-server-mock](https://github.com/linlay/mcp-server-mock) | 已接入部署链路 | Mock MCP 服务 |
| [mcp-server-bash](https://github.com/linlay/mcp-server-bash) | 已接入部署链路 | Bash MCP 服务 |
| [mcp-server-email](https://github.com/linlay/mcp-server-email) | 已接入部署链路 | Email MCP 服务 |

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
./setup-mac.sh --action configure-startup
./setup-mac.sh --action reset-password-hash
```

## Linux 使用方式

入口脚本：

```bash
./setup-linux.sh
```

常用非交互命令：

```bash
./setup-linux.sh --action precheck
./setup-linux.sh --action first-install
./setup-linux.sh --action update
./setup-linux.sh --action start
./setup-linux.sh --action stop
./setup-linux.sh --action configure-startup
./setup-linux.sh --action reset-password-hash
```

## Windows + WSL 使用方式

请先进入 WSL 发行版 shell，再执行：

```bash
./setup-win-wsl.sh
```

常用非交互命令：

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

- 启动列表文件固定为 `config/startup-services.conf`
- 文件格式为纯文本，一行一个服务
- 空行和 `#` 注释会被忽略
- 文件中的行序就是启动顺序，`stop` 自动按反向顺序执行
- 默认内容为：
  - `zenmind-gateway`
  - `zenmind-app-server`
  - `mcp-server-mock`
  - `mcp-server-bash`
  - `mcp-server-email`
- 若文件缺失，`setup-mac.sh` 会自动按默认顺序初始化

交互菜单新增：

- `6) 配置启动列表`

该动作会逐个询问是否启用服务，并覆盖写入 `config/startup-services.conf`。

## 关键行为约束

- CLI action：`precheck | first-install | update | start | stop | configure-startup | reset-password-hash`
- `start` 不再固定全启；它只读取 `config/startup-services.conf` 中声明的服务并按顺序启动
- `stop` 只停止 `config/startup-services.conf` 中启用的服务，并按反向顺序执行
- 健康检查统一使用 `run/app.pid`
- `startup-services.conf` 中存在未知服务名、重复服务名、空服务列表时，脚本会报错并终止
- 任一启用服务启动失败都会导致 `start` 失败

## 首次安装与更新

`first-install` / `update` 会：

- 统一 clone 5 个活跃仓库到 `source/<repo>`：
  - `zenmind-gateway`
  - `zenmind-app-server`
  - `mcp-server-mock`
  - `mcp-server-bash`
  - `mcp-server-email`
- `setup-mac.sh` 执行各仓库 `release-scripts/mac/package.sh`
- `setup-linux.sh` / `setup-win-wsl.sh` 执行各仓库 `release-scripts/linux/package.sh`
- 将打包产物移动到 `release/<repo>`
- 同步当前已定义的配置模板（缺失即失败）：
  - `source/zenmind-app-server/.env.example -> release/zenmind-app-server/.env`
  - `source/mcp-server-mock/.env.example -> release/mcp-server-mock/.env`
- 若 `config/startup-services.conf` 不存在，则自动写入默认启动列表

密码哈希注入：

- `release/zenmind-app-server/.env`:
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

- Docker/Compose 仍不是本仓库 setup 的强依赖。
- `runtime` 模式仅执行环境检查脚本当前定义的运行时校验。
- Linux / WSL 的修复提示以 Ubuntu/Debian 为基线。

## Windows 状态

Windows PowerShell 入口当前仍为占位保护：

```powershell
.\setup-windows.ps1 -Action precheck
```

会直接 fail-fast，并提示你先进入 WSL 后运行 `./setup-win-wsl.sh --action precheck`。

## License

MIT. See [LICENSE](LICENSE).
