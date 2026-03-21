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

## 使用方式

macOS:

```bash
./setup-mac.sh --action check
./setup-mac.sh --action download-all
./setup-mac.sh --action configure --web
./setup-mac.sh --action configure --cli
./setup-mac.sh --action configure --sync-only
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
./setup-linux.sh --action start
./setup-linux.sh --action view
./setup-linux.sh --action stop
```

## 动作说明

- `check`：输出 mac/Linux 环境检测报告，分 Required / Optional / Runtime / Next Steps 展示，并给出安装命令
- `download-all`：仅 macOS 可用；按 sibling repo 目录批量 clone/同步源码仓库。缺失仓库执行 `git clone`，已有干净仓库执行 `git pull --ff-only`，有未提交改动或非 Git 目录则跳过并提示 warning。这一动作只处理源码仓库，不会下载 Docker 镜像
- `configure --web`：打开本地单页 HTML 编辑器，只维护总 JSON
- `configure --cli`：通过命令行向导维护总 JSON
- `configure --sync-only`：将总 JSON 写入 sibling repo 的 `.env/configs`，同时生成根仓 compose env、override 和 gateway `nginx.conf`
- `start`：先执行 `configure --sync-only`，再先启动 startup list 中的宿主机程序，然后检查镜像、缺失则 `docker pull`，最后启动镜像产品容器
- `stop`：先停止 startup list 中的镜像容器，再停止 ZenMind 管理的宿主机程序
- `view`：分组查看镜像产品状态、宿主机程序状态、gateway `healthz`、cloudflared 安装/配置/运行状态；可用 `--logs` 查看容器日志或 `agent-container-hub` 宿主机日志

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

## 生成结果

根仓 `apply-config` 后会生成：

- [`generated/docker-compose.env`](/Users/linlay-macmini/Project/zenmind/zenmind/generated/docker-compose.env)
- [`generated/docker-compose.override.yml`](/Users/linlay/Project/zenmind/zenmind/generated/docker-compose.override.yml)
- [`generated/gateway/nginx.conf`](/Users/linlay/Project/zenmind/zenmind/generated/gateway/nginx.conf)

这些文件不提交 Git。
