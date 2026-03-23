# ZenMind Setup

ZenMind 现在是一个 sibling repo 形态的总控仓，`setup` 负责三件事：

- 维护唯一用户配置源 `config/zenmind.profile.local.json`
- 把总配置同步到各 sibling repo 的 `.env` / `configs`
- 按安装方式统一做安装、升级、启动、停止和版本检查

当前 `setup` 支持两种安装路径：

- `source`：源码安装，适合开发和跟 tag 升级
- `release`：镜像 / 可执行 bundle 安装，适合交付和整栈升级

## 主菜单

交互菜单会按“当前目录对应的 install state”自适应。

未安装态：

```text
1) 环境检测
2) 用户配置
3) 安装
4) 查看状态
0) 退出
```

已安装态：

```text
1) 启动
2) 停止
3) 修改用户配置
4) 查看状态
5) 升级 / 升级到 vX.Y.Z
0) 退出
```

如果当前目录没有安装信息，会先显示一个三步走提示：

- 第一步环境检查
- 第二步用户配置
- 第三步安装

CLI 动作为：

- `check`
- `configure`
- `install`
- `upgrade`
- `start`
- `stop`
- `view`
- `check-update`（兼容 CLI，交互菜单不再显示）

## 关键规则

### 1. 配置规则

- 唯一主配置文件是 `config/zenmind.profile.local.json`
- 安装方式不写入 profile
- 升级状态和当前安装模式不写入 profile
- `configure --sync-only` 只负责把 profile 同步成派生文件

`apply-config` 后会生成：

- `generated/docker-compose.env`
- `generated/docker-compose.override.yml`
- `generated/gateway/nginx.conf`
- `config/startup-services.conf`

### 2. 安装状态规则

安装状态单独记录在 monorepo 根目录：

- `../.zenmind/install-state.json`

这个文件记录：

- 当前安装模式：`source | release`
- 当前版本和上一个版本
- manifest 来源
- 上次安装 / 升级时间
- source 模式下的 repo refs
- release 模式下的活动版本目录

交互菜单只按当前目录是否存在 install state 判断是否已安装，不扫描其他目录，不导入历史部署。
兼容 direct CLI 时，如果当前目录已经是现有 sibling repo 源码布局，`setup` 仍可补写一个 `source` 状态。

### 3. Release 规则

release 模式默认使用 monorepo 根目录：

- 安装根目录：`../release/<version>/`
- 工作区目录：`../release/<version>/deploy/`

每个发布版本目录应包含：

- bundle tarball
- `release-manifest.json`
- `SHA256SUMS`

默认远程 manifest：

- `https://www.zenmind.cc/install/manifest.json`

也支持本地输入：

- 本地 manifest 文件
- 本地 `dist/<version>/` 目录
- 远程 manifest URL

本地显式传 `--manifest` 时优先用本地；不传时默认用远程 manifest。

## 常用命令

### macOS

```bash
./setup-mac.sh --action check
./setup-mac.sh --action configure --web
./setup-mac.sh --action install --source --manifest ./dist/v0.1
./setup-mac.sh --action install --release --manifest ./dist/v0.1
./setup-mac.sh --action upgrade --source --manifest ./dist/v0.1
./setup-mac.sh --action upgrade --release --manifest ./dist/v0.1
./setup-mac.sh --action start
./setup-mac.sh --action view
./setup-mac.sh --action stop
```

### Linux / WSL

```bash
./setup-linux.sh --action check
./setup-linux.sh --action configure --cli
./setup-linux.sh --action install --source --manifest ./dist/v0.1
./setup-linux.sh --action install --release --manifest ./dist/v0.1
./setup-linux.sh --action upgrade --source --manifest ./dist/v0.1
./setup-linux.sh --action upgrade --release --manifest ./dist/v0.1
./setup-linux.sh --action start
./setup-linux.sh --action view
./setup-linux.sh --action stop
```

Windows 主系统不再支持直接安装；请进入 WSL 后使用 `setup-win-wsl.sh`。

## 动作说明

### `check`

- 运行环境检测
- 输出 Required / Optional / Runtime / Next Steps

### `configure`

- `--web`：打开本地 HTML 配置页
- `--cli`：进入命令行向导
- `--sync-only`：只同步 profile 到派生文件

### `install --source`

- clone 或更新 sibling repos
- 切到 manifest 指定的稳定 tag，或 `--target-version`
- 执行 `apply-config`
- 写入 `install-state.json`

### `install --release`

- 读取 manifest
- 选择当前平台需要的 bundle
- 准备 `../release/<version>/`
- 解压 bundle，初始化缺失配置
- 尽量保留已有 live config
- 写入 `install-state.json`

### `upgrade --source`

- 要求源码仓是干净状态
- `git fetch --tags`
- 切到新的稳定 tag
- 重新同步配置
- 失败时回滚到升级前 refs

### `upgrade --release`

- 先准备新版本工作区
- 停旧栈、启新栈、做健康检查
- 成功后切换 active version
- 失败时恢复旧版本

### `start / stop / view`

这三个动作会按 `install-state.json.installMode` 自动分流：

- `source`：继续使用根仓 compose + host program 模式
- `release`：使用 `../release/<version>/deploy` 下的整栈 bundle

进入交互式 setup 时，如果当前目录已有 install state，会先静默检查一次升级：

- 有新版本：菜单直接显示 `升级到 vX.Y.Z`
- 无新版本：菜单显示普通 `升级`
- 检查失败或离线：菜单仍显示普通 `升级`

`check-update` 仍保留给 CLI 兼容使用，但不再出现在交互菜单。

## 兼容规则

- `download-all` 已废弃，当前等价于 `install --source`
- 旧 alias `precheck / edit-config / apply-config / status` 仍保留兼容
- 不自动导入历史 `~/Server/zenmind2` 部署目录；如果要纳入新 setup，请执行一次新的 `install --release --manifest <本地路径>`

## 当前纳管服务

- `gateway`
- `zenmind-app-server`
- `zenmind-voice-server`
- `pan-webclient`
- `term-webclient`
- `mcp-server-imagine`
- `mcp-server-mock`
- `agent-platform-runner`
- `agent-container-hub`

当前不由 setup 纳管：

- `mini-app-server`
- `mcp-server-bash`
- `mcp-server-email`

## 发布侧约定

发布相关脚本：

- `./scripts/deploy/package-agents.sh`
- `./scripts/deploy/collect-dist.sh <version>`

`collect-dist.sh` 会把各项目 tarball 收集到：

- `dist/<version>/`

并额外生成：

- `dist/<version>/release-manifest.json`
- `dist/<version>/SHA256SUMS`

## 参考文档

更细的 setup 说明见：

- [`docs/README.md`](/Users/linlay/Project/zenmind/zenmind/docs/README.md)
