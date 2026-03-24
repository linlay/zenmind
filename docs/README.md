# ZenMind

ZenMind 现在是 sibling repo 形态的总控仓：

- 统一维护 `config/zenmind.profile.local.json`
- 启动前把总配置写入各子仓 `.env/configs`
- 通过根仓 `docker compose` 统一启动容器
- `cloudflared` 继续在宿主机运行，直接转发到 `127.0.0.1:11945`

## 当前纳管服务

| 产品 | 运行形态 | 默认端口 | 说明 |
|---|---|---:|---|
| `gateway` | 镜像 | `11945` | Nginx 网关容器，提供 `/admin` `/pan` `/term` `/api/voice` `/api/ap` `/api/mcp/*` |
| `zenmind-app-server` | 镜像 | `11950` | 管理台入口；backend 仅容器内访问 |
| `zenmind-voice-server` | 镜像 | `11953` | 仅接入 `/api/voice/*`，内部调用容器内 runner |
| `pan-webclient` | 镜像 | `11946` | `/pan/*` 与随服务启用的 `/apppan/*` |
| `term-webclient` | 镜像 | `11947` | `/term/*` 与随服务启用的 `/appterm/*` |
| `mcp-server-imagine` | 镜像 | `11962` | 容器内 `/mcp`，宿主机端口可关 |
| `mcp-server-mock` | 镜像 | `11969` | 容器内 `/mcp`，宿主机端口可关 |
| `agent-platform-runner` | 镜像 | `11949` | 由根仓 `docker compose` 管理，网关反代 `/api/ap/*` 到容器内 `8080` |
| `agent-container-hub` | 宿主机程序 | `11960` | 从 sibling repo 以 `go run ./cmd/agent-container-hub` 启动，供 runner 通过 `host.docker.internal` 访问 |

当前不由 setup 纳管的产品：

- `mini-app-server`
- `mcp-server-bash`
- `mcp-server-email`

## 配置文件

- 示例模板：[`config/zenmind.profile.example.json`](/Users/linlay/Project/zenmind/zenmind/config/zenmind.profile.example.json)
- 本地真实配置：`config/zenmind.profile.local.json`
- 配置编辑页：[`config/editor/index.html`](/Users/linlay/Project/zenmind/zenmind/config/editor/index.html)
- 启动列表：[`config/startup-services.conf`](/Users/linlay/Project/zenmind/zenmind/config/startup-services.conf)

`config/zenmind.profile.local.json` 是唯一主维护配置源。各 sibling repo 的 `.env`、`configs/*.yml`、根仓 `generated/` 下文件都是由 `apply-config` 生成的，不建议手工长期维护。

密码在编辑页中以明文输入，但保存到 JSON 时只写入对应的 bcrypt 字段，不会写入 `plain`。
镜像仓库与 tag 也写进总 JSON；启动时会按 `${images.registry}/{service}:${images.tag}` 规则拉取远程镜像。

安装方式和升级状态不写进 profile，而是单独记录在 monorepo 根目录：

- 安装状态：`../.zenmind/install-state.json`
- release 安装目录：`../release/<version>/`
- release manifest：`dist/<version>/release-manifest.json`

## 使用方式

macOS:

```bash
./setup-mac.sh --action check
./setup-mac.sh --action configure --web
./setup-mac.sh --action configure --cli
./setup-mac.sh --action configure --sync-only
./setup-mac.sh --action install --source --manifest ./dist/v0.1
./setup-mac.sh --action install --release --manifest ./dist/v0.1
./setup-mac.sh --action upgrade --source --manifest ./dist/v0.1
./setup-mac.sh --action upgrade --release --manifest ./dist/v0.1
./setup-mac.sh --action start
./setup-mac.sh --action view
./setup-mac.sh --action view --logs gateway --tail 200
./setup-mac.sh --action view --logs agent-container-hub --tail 200
./setup-mac.sh --action stop
```

Linux:

```bash
./setup-linux.sh --action check
./setup-linux.sh --action configure --web
./setup-linux.sh --action configure --cli
./setup-linux.sh --action configure --sync-only
./setup-linux.sh --action install --source --manifest ./dist/v0.1
./setup-linux.sh --action install --release --manifest ./dist/v0.1
./setup-linux.sh --action upgrade --source --manifest ./dist/v0.1
./setup-linux.sh --action upgrade --release --manifest ./dist/v0.1
./setup-linux.sh --action start
./setup-linux.sh --action view
./setup-linux.sh --action stop
```

交互菜单会按当前目录 install state 自适应：

- 未安装态：`环境检查 / 用户配置 / 安装 / 查看状态`
- 已安装态：`启动 / 停止 / 修改用户配置 / 查看状态 / 升级`

如果 setup 检测到当前目录已有安装信息，还会先静默检查一次升级；有新版本时，菜单会直接显示 `升级到 vX.Y.Z`。

## 动作说明

- `check`：输出 mac/Linux 环境检测报告，分 Required / Optional / Runtime / Next Steps 展示，并给出安装命令
- `configure --web`：打开本地单页 HTML 编辑器，只维护总 JSON
- `configure --cli`：通过命令行向导维护总 JSON
- `configure --sync-only`：将总 JSON 写入 sibling repo 的 `.env/configs`，同时生成根仓 compose env、override 和 gateway `nginx.conf`
- `install --source`：按 sibling repo 目录 clone/同步源码仓库，切到 manifest 指定的稳定 tag，执行 `apply-config`，并写入 install state
- `install --release`：按 manifest 准备 `../release/<version>/` 工作区，抽取 bundle、初始化缺失配置、保留已有 live config，并写入 install state
- `upgrade --source`：检查源码仓 dirty 状态，切到新的稳定 tag，重新同步配置；失败时回滚到升级前 refs
- `upgrade --release`：先准备新版本工作区，再停旧栈、启新栈、做健康检查；失败时恢复旧版本并保留上一版本目录
- `start`：根据 `install-state.json` 分流。`source` 模式继续走根仓 compose + host program；`release` 模式启动 `../release/<version>/deploy` 下整栈 bundle
- `stop`：根据当前 install mode 分流停止 source 或 release 栈
- `view`：根据当前 install mode 分流查看状态；无 install state 时显示未安装状态、profile 是否存在、manifest 是否可读；已安装时继续显示 source/release 运行状态
- `download-all`：已废弃，当前等价于 `install --source`

`check-update` 仍保留给 CLI 兼容使用，但不再出现在交互菜单。

## 路由契约

- `/admin/*`：`zenmind-app-server`
- `/api/auth` `/api/app` `/oauth2` `/openid`：`zenmind-app-server backend`
- `/api/voice/*`：`zenmind-voice-server`
- `/pan/*`：浏览器网盘入口，可关闭
- `/apppan/*`：App 网盘入口，随网盘服务启用
- `/term/*`：浏览器终端入口，可关闭
- `/appterm/*`：App 终端入口，随终端服务启用
- `/api/ap/*`：容器内 `agent-platform-runner`
- `/api/mcp/mock|imagine`：对应 MCP 容器 `/mcp`

访问关闭策略统一由网关返回 `404`。

## Cloudflare Tunnel

当前方案不容器化 `cloudflared`。

推荐流程：

1. 启动网关容器，确认 `http://127.0.0.1:11945/healthz` 可访问
2. 运行 `./setup-mac.sh --action setup-cf-tunnel` 或 Linux 对应动作
3. 在 `~/.cloudflared/config.yml` 中将 hostname 指向 `http://127.0.0.1:11945`

## Deploy 脚本

- zenmind data 打包入口：`./scripts/deploy/package-zenmind-data.sh`
- 兼容入口：`./scripts/package.sh`
- monorepo dist 收集入口：`./scripts/deploy/collect-dist.sh <version>`
- `collect-dist.sh` 的输入固定为精确 patch 版本 `vX.Y.Z`
- `collect-dist.sh` 默认会生成：
  - `./dist/vX.Y/patches/vX.Y.Z/`
  - `./dist/vX.Y/release-manifest.json`
  - `./dist/manifest.json`
- `./dist/index.json`
- patch 目录内仍会生成 `release-manifest.json` 与 `SHA256SUMS`
- `zenmind` 的发布版本单一来源是根目录 `VERSION`，格式固定为 `vX.Y.Z`
- `package-zenmind-data.sh` 优先读取环境变量 `VERSION`，否则读取根目录 `VERSION`
- `package-zenmind-data.sh` 从根仓 `.zenmind/registries.example/` 与 `.zenmind/owner.example/` 读取示例数据，并把归档写到 `.zenmind/dist/<version>/zenmind-data-<version>.tar.gz`
- zenmind data 包内部结构统一包含 `agents/`、`chats/`、`owner/`、`registries/`、`root/`、`schedules/`、`skills-market/`、`teams/`；release 解包后的部署态 `.zenmind` 目录会同步落地这些目录
- `agents/`、`skills-market/` 只打包正常目录和 `*.example`，不打包 `*.demo`
- `chats/` 只打包 `*.example.jsonl` 与 `*.example/`
- `root/` 只打包顶层 basename 带 `.example` 的文件和目录
- `schedules/`、`teams/` 只打包正常文件与 `*.example.yml|*.example.yaml`，不打包 `*.demo.yml|*.demo.yaml`
- `tools/` 不打包
- `collect-dist.sh` 会从 monorepo 各项目的 `dist/` 中收集匹配版本的 tarball，也会从根仓 `.zenmind/dist/` 收集 `zenmind-data` 包

## 生成结果

根仓 `apply-config` 后会生成：

- [`generated/docker-compose.env`](/Users/linlay/Project/zenmind/zenmind/generated/docker-compose.env)
- [`generated/docker-compose.override.yml`](/Users/linlay/Project/zenmind/zenmind/generated/docker-compose.override.yml)
- [`generated/gateway/nginx.conf`](/Users/linlay/Project/zenmind/zenmind/generated/gateway/nginx.conf)

这些文件不提交 Git。
