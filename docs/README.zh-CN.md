# ZenMind

<div align="center">

[English](../README.md) | [简体中文](./README.zh-CN.md)

<img src="./media/zenmind-logo.svg" alt="ZenMind logo" height="96" />

</div>

ZenMind 是一个以 Desktop 为入口的 AI Agent 平台，面向本地、Web 和移动端工作流。

它把核心智能体运行时封装进一个桌面应用，重点支持 DeepSeek V4（`deepseek-v4-pro` 和 `deepseek-v4-flash`）、MiMo、MiniMax M3、Qwen/百炼等国产模型生态，并通过自定义 AGW UI 协议承载流式输出、人工确认、交互视图、用量统计和子智能体调用。

## 官网

[www.zenmind.cc](https://www.zenmind.cc) 提供官方 Desktop 安装包下载，也可以基于当前开源项目自行打包。

## 关于 ZenMind

ZenMind 的初心很简单：让宅在家里的电脑不只是待机，而是变成一个可以持续协作的 AI Agent 工作站。它以 Desktop 为入口，连接本地服务、Web/移动客户端和国产模型生态，努力做一个更开放、更本地优先的 OpenClaw 方向平台。

## 核心亮点

- 一个 Desktop 应用完成安装、初始化、启动、停止和服务监控。
- 面向 DeepSeek V4（`deepseek-v4-pro` 和 `deepseek-v4-flash`）、MiMo、MiniMax M3、Qwen/百炼与 MiniMax 办公技能链路。
- 自定义 AGW UI 协议支持流式输出、HITL、viewport、usage 和子智能体。
- 本地沙箱层支持长生命周期会话、工具环境和文档办公自动化。
- 同一套智能体体验服务 Desktop、Web Client 和即将到来的移动端。

## Agent 配置

| 模型 | Context | 最高 thinking effort | DeepSeek API Docs 官方价格 |
| --- | --- | --- | --- |
| `deepseek-v4-flash` | `maxInputTokens: 1048576`（1M context） | `reasoning_effort=max` | cache hit `$0.0028`，cache miss `$0.14`，output `$0.28` / 1M tokens |
| `deepseek-v4-pro` | `maxInputTokens: 1048576`（1M context） | `reasoning_effort=max` | cache hit `$0.003625`，cache miss `$0.435`，output `$0.87` / 1M tokens |

运行时 registry 使用当前 V4 模型 ID、`maxOutputTokens: 393216`，以及 cache-hit input、cache-miss input、output 三类 pricing 字段。字段映射和验证依据见 [模型支持](./models.zh-CN.md)。

## 演示视频

> 占位：这里后续补充 ZenMind 产品演示视频。

## 截图

<div align="center">
  <img src="./assets/screenshot-plan-approval.jpg" alt="ZenMind 计划审批流程" />
  <br />
  <br />
  <img src="./assets/screenshot-deepseek-cache-hit.jpg" alt="ZenMind DeepSeek 缓存命中用量视图" />
  <br />
  <br />
  <img src="./assets/screenshot-user-approval.jpg" alt="ZenMind 用户确认流程" />
</div>

## Desktop 一键安装

ZenMind 通过 ZenMind Desktop 分发。Desktop 会包裹核心服务，准备本地配置，按正确顺序启动运行时，并提供统一控制中心。

可以从 [www.zenmind.cc](https://www.zenmind.cc) 下载官方安装包，也可以基于当前开源仓库自行打包。

## 核心架构

<div align="center">
  <img src="./media/zenmind-architecture.svg" alt="ZenMind architecture" />
</div>

ZenMind Desktop 包裹四个核心服务：

- `zenmind-app-server`：认证、OIDC、管理台和 App 访问令牌。
- `agent-platform`：智能体运行时、模型注册、工具、记忆、HITL、用量统计和子智能体编排。
- `agent-webclient`：对话前端、Timeline、模型切换、viewport 渲染和用量展示。
- `agent-container-hub`：本地沙箱会话、环境模板和容器工具运行时。

## AGW UI 协议

AGW UI 是 ZenMind 客户端与 Agent Platform 之间的自定义协议。它把 HTTP、SSE 和可选 WebSocket 传输，与丰富的智能体事件模型结合起来：

- H2A 流式输出与 attach 续接。
- `question / approval / form / plan` 四类 HITL 等待态。
- builtin viewport 与 HTML viewport 交互视图。
- token、cache、reasoning、工具调用和成本维度的 usage 快照。
- `agent_invoke` 子智能体任务，并实时汇聚回主 Timeline。

更多说明见 [AGW UI 协议](./agwui.md)。

## 文档

- [AGW UI 协议](./agwui.md)
- [架构说明](./architecture.md)
- [文档索引](./README.md)
- [移动端方向](./mobile.md)
- [模型支持](./models.zh-CN.md)

## License

见 [LICENSE](../LICENSE)。
