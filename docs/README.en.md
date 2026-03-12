# ZenMind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Repository Type](https://img.shields.io/badge/repo-hub%20portal-blue)](https://github.com/linlay/zenmind)

[Default (Chinese)](README.md) | [Chinese Standalone](README.zh-CN.md) | [English](README.en.md)

ZenMind is a multi-repository hub for AI agent workflow services.

## Deployment Baseline (2026-03)

- macOS and Linux are the supported deployment paths in this phase.
- Direct installation on the Windows host is no longer supported; use WSL instead.
- `docs/media/zenmind-overview.svg` is not updated in this round.

## Projects (5)

| Project | Status | Description |
|---|---|---|
| [zenmind-gateway](https://github.com/linlay/zenmind-gateway) | Integrated | Gateway service |
| [zenmind-app-server](https://github.com/linlay/zenmind-app-server) | Integrated | Application backend service |
| [mcp-server-mock](https://github.com/linlay/mcp-server-mock) | Integrated | Mock MCP service |
| [mcp-server-bash](https://github.com/linlay/mcp-server-bash) | Integrated | Bash MCP service |
| [mcp-server-email](https://github.com/linlay/mcp-server-email) | Integrated | Email MCP service |

## Mac Entry

```bash
./setup-mac.sh
```

Non-interactive actions:

```bash
./setup-mac.sh --action precheck
./setup-mac.sh --action first-install
./setup-mac.sh --action update
./setup-mac.sh --action start
./setup-mac.sh --action stop
./setup-mac.sh --action configure-startup
./setup-mac.sh --action reset-password-hash
```

## Linux Entry

```bash
./setup-linux.sh
```

Non-interactive actions:

```bash
./setup-linux.sh --action precheck
./setup-linux.sh --action first-install
./setup-linux.sh --action update
./setup-linux.sh --action start
./setup-linux.sh --action stop
./setup-linux.sh --action configure-startup
./setup-linux.sh --action reset-password-hash
```

## Windows via WSL

Open your WSL distro shell first, then run:

```bash
./setup-win-wsl.sh
```

Non-interactive actions:

```bash
./setup-win-wsl.sh --action precheck
./setup-win-wsl.sh --action first-install
./setup-win-wsl.sh --action update
./setup-win-wsl.sh --action start
./setup-win-wsl.sh --action stop
./setup-win-wsl.sh --action configure-startup
./setup-win-wsl.sh --action reset-password-hash
```

## Startup List Configuration

- Startup list file: `config/startup-services.conf`
- Format: plain text, one service per line
- Blank lines and `#` comments are ignored
- Line order defines startup order; stop order is the reverse automatically
- Default order:
  - `zenmind-gateway`
  - `zenmind-app-server`
  - `mcp-server-mock`
  - `mcp-server-bash`
  - `mcp-server-email`
- If the file is missing, `setup-mac.sh` initializes it automatically with the default order

New interactive menu item:

- `6) Configure startup list`

This action prompts whether each service should be enabled and rewrites `config/startup-services.conf`.

## Runtime Contract

- CLI actions: `precheck | first-install | update | start | stop | configure-startup | reset-password-hash`
- `start` no longer always starts every managed service; it reads and starts only the services listed in `config/startup-services.conf`
- `stop` stops only the enabled services from `config/startup-services.conf`, in reverse order
- Health checks rely on `run/app.pid`
- The script fails fast when `startup-services.conf` contains an unknown service, a duplicate service, or no enabled services
- Any enabled service failure causes `start` to fail

## Install / Update Flow

`first-install` and `update` now:

- clone 5 active repositories into `source/<repo>`
  - `zenmind-gateway`
  - `zenmind-app-server`
  - `mcp-server-mock`
  - `mcp-server-bash`
  - `mcp-server-email`
- `setup-mac.sh` executes each repo `release-scripts/mac/package.sh`
- `setup-linux.sh` and `setup-win-wsl.sh` execute each repo `release-scripts/linux/package.sh`
- move packaged outputs into `release/<repo>`
- copy the currently defined required config examples:
  - `source/zenmind-app-server/.env.example -> release/zenmind-app-server/.env`
  - `source/mcp-server-mock/.env.example -> release/mcp-server-mock/.env`
- auto-create `config/startup-services.conf` with the default list if it does not exist

Password hash injection remains for:

- `release/zenmind-app-server/.env`
  - `AUTH_ADMIN_PASSWORD_BCRYPT`
  - `AUTH_APP_MASTER_PASSWORD_BCRYPT`

## macOS / Linux Requirements

`precheck` install mode requires:

- `git`
- `go >= 1.26.0`
- `java >= 21`
- `maven >= 3.9`
- `node >= 20`
- `npm`

Notes:

- Docker/Compose is still not a mandatory dependency for this setup repo.
- Runtime mode follows whatever runtime checks are defined in the environment check script.
- Linux / WSL fix hints are written against an Ubuntu/Debian baseline.

## Windows Placeholder

The following PowerShell command is still expected to fail-fast:

```powershell
.\setup-windows.ps1 -Action precheck
```

Enter WSL first, then use `./setup-win-wsl.sh --action precheck`.

## License

MIT. See [LICENSE](LICENSE).
