# ZenMind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Repository Type](https://img.shields.io/badge/repo-hub%20portal-blue)](https://github.com/linlay/zenmind)
[![Release Status](https://img.shields.io/badge/releases-planned-lightgrey)](https://github.com/linlay/zenmind/releases)

[默认 (中文)](README.md) | [简体中文独立页](README.zh-CN.md) | [English](README.en.md)

ZenMind 是一个个人电脑智能体代理（PC Agent Proxy），支持连接终端控制台并使用编码 CLI。

## 快速了解

[![Watch Demo Video](https://img.shields.io/badge/Demo-Video-black?logo=github)](https://github.com/linlay/zenmind/releases)

![ZenMind Overview](docs/media/zenmind-overview.svg)

## 安装方式

1. 源码安装（当前可用）：使用本仓库 setup 流程拉取、打包并启动。
2. Release 安装（预留）：
- [ ] 预留
3. 移动端下载（预留）：
- Android APK 下载：
- [ ] 预留
- iOS App Store 下载：
- [ ] 预留

源码安装入口：

```bash
# macOS
./setup-mac.sh

# Windows
.\setup-windows.bat
```

常用非交互命令：

```bash
./setup-mac.sh --action precheck
./setup-mac.sh --action first-install
./setup-mac.sh --action start
```

## 项目地图

| 项目 | 角色定位 |
|---|---|
| [zenmind-app-server](https://github.com/linlay/zenmind-app-server) | App 管理服务（认证、设备认证、消息盒子、管理 API） |
| [agent-platform-runner](https://github.com/linlay/agent-platform-runner) | 智能体运行器（Agent 编排与运行） |
| [term-webclient](https://github.com/linlay/term-webclient) | 控制台客户端（Web Terminal，支持编码 CLI） |
| [agent-platform-admin](https://github.com/linlay/agent-platform-admin) | 智能体管理端 |
| [zenmind-react-app](https://github.com/linlay/zenmind-react-app) | 移动端 App（终端、智能体、账号配置） |

## 主要功能

- 统一认证与消息盒子：账号登录、设备认证、消息收件与管理接口。
- 终端能力：浏览器终端、会话管理、断线恢复、SSH 场景支持。
- Agent 运行能力：Agent 编排、SSE 流式返回、人机协作提交流程。
- 移动端集成：聊天、终端、智能体管理和账号配置统一在 App 内。
- 跨仓库统一 setup：通过 Hub 仓库一键串联拉取、打包、启动。

## 演示视频（预留）

- [ ] 预留

## 功能截图（预留）

- [ ] 登录与设备认证流程
- [ ] 消息盒子与通知联动
- [ ] Web Terminal 多会话
- [ ] Agent 对话与工具执行
- [ ] 移动端核心页面（聊天/终端/智能体）

规划能力：

- 云端 Skills 沙箱（Planned）
- 本地容器化沙箱（Planned）

## 这个仓库做什么

`zenmind` 是总入口仓库，负责：

- 统一导航各子项目
- 提供跨仓库 setup 入口
- 维护 release 链接与总览文档

## License

MIT. See [LICENSE](LICENSE).
