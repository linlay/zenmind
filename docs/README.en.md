# ZenMind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Repository Type](https://img.shields.io/badge/repo-hub%20portal-blue)](https://github.com/linlay/zenmind)

[Default (Chinese)](README.md) | [Chinese Standalone](README.zh-CN.md) | [English](README.en.md)

ZenMind is a multi-repository hub for AI agent workflow services.

## Deployment Baseline (2026-03)

- macOS is the only supported deployment path in this phase.
- Windows setup is intentionally fail-fast as a placeholder.
- `docs/media/zenmind-overview.svg` is not updated in this round.

## Projects (5)

| Project | Status | Description |
|---|---|---|
| [agent-platform-runner](https://github.com/linlay/agent-platform-runner) | Integrated | Agent runtime service (required) |
| [agent-platform-admin](https://github.com/linlay/agent-platform-admin) | Placeholder | Not implemented in this round |
| [mcp-server-mock](https://github.com/linlay/mcp-server-mock) | Integrated | Go backend service (required) |
| [zenmind-app-server](https://github.com/linlay/zenmind-app-server) | Integrated | Go backend service (required) |
| [term-webclient](https://github.com/linlay/term-webclient) | Integrated | Non-container startup, Java process (required) |

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
./setup-mac.sh --action reset-password-hash
```

## Runtime Contract

- CLI actions remain unchanged: `precheck | first-install | update | start | stop | reset-password-hash`
- Required start order: `zenmind-app-server -> mcp-server-mock -> agent-platform-runner -> term-webclient`
- Stop order is reversed: `term-webclient -> agent-platform-runner -> mcp-server-mock -> zenmind-app-server`
- Health checks rely on PID liveness:
- `term-webclient`: `run/backend.pid` + `run/frontend.pid`
- Other services: `run/app.pid`
- Any required service failure causes `start` to fail.

## Install / Update Flow

`first-install` and `update` now:

- clone 4 active repositories into `source/<repo>`
- execute each repo `release-scripts/mac/package*.sh`
- move packaged outputs into `release/<repo>`
- copy required config examples (missing file = failure):
- `source/term-webclient/.env.example -> release/term-webclient/.env`
- `source/term-webclient/application.example.yml -> release/term-webclient/application.yml`
- `source/zenmind-app-server/.env.example -> release/zenmind-app-server/.env`
- `source/agent-platform-runner/application.example.yml -> release/agent-platform-runner/application.yml`
- `source/mcp-server-mock/.env.example -> release/mcp-server-mock/.env`

Password-hash injection is preserved for term + app:

- `release/term-webclient/.env`: `AUTH_PASSWORD_HASH_BCRYPT`
- `release/zenmind-app-server/.env`: `AUTH_ADMIN_PASSWORD_BCRYPT`, `AUTH_APP_MASTER_PASSWORD_BCRYPT`

## macOS Requirements

`precheck` install mode requires:

- `git`
- `go >= 1.26.0`
- `java >= 21`
- `maven >= 3.9`
- `node >= 20`
- `npm`

Notes:

- Docker/Compose is no longer a mandatory dependency for this topology.
- Runtime mode no longer checks Docker daemon; nginx remains optional.

## Windows Placeholder

The following command is expected to fail-fast:

```powershell
.\setup-windows.ps1 -Action precheck
```

Use mac setup commands instead.

## License

MIT. See [LICENSE](LICENSE).
