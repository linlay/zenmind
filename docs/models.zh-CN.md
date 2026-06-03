# 模型支持

ZenMind 面向现代国产模型生态设计，同时保持运行时 provider registry 的灵活性。

## DeepSeek V4 Agent 配置

ZenMind 使用当前 DeepSeek V4 模型 ID：

| 模型 key | Provider | Protocol | Model ID | Context | 最大输出 | 价格来源 |
| --- | --- | --- | --- | --- | --- | --- |
| `deepseek-v4-flash` | `deepseek` | `OPENAI` | `deepseek-v4-flash` | `maxInputTokens: 1048576`（1M） | `maxOutputTokens: 393216` | DeepSeek API Docs |
| `deepseek-v4-pro` | `deepseek` | `OPENAI` | `deepseek-v4-pro` | `maxInputTokens: 1048576`（1M） | `maxOutputTokens: 393216` | DeepSeek API Docs |

运行时 registry 使用 `modelId`、`provider`、`protocol`、`isReasoner`、`isFunction`、`maxInputTokens`，以及 `pricing.inputCacheHit/inputCacheMiss/output`。这些字段已由 Agent Platform 验证：`maxInputTokens` 会被加载为模型 context window，pricing 三字段会用于 cache-hit input、cache-miss input 和 output tokens 的用量成本估算。

DeepSeek provider 兼容层会为 DeepSeek 风格推理消息保留 `reasoning_content`。ZenMind 不保留已经由上游修复的问题 workaround；这里仅保留运行时会读取的 provider-specific request 和 response 兼容字段。

DeepSeek V4 的最高 thinking effort 使用 `reasoning_effort=max`。如果调用方使用旧的 `xhigh` 等级，兼容路径会映射到 `max`。

## DeepSeek 官方价格

以下价格已按 DeepSeek API Docs 核对，单位为 USD / 1M tokens：

| 模型 | Input cache hit | Input cache miss | Output |
| --- | --- | --- | --- |
| `deepseek-v4-flash` | `$0.0028` | `$0.14` | `$0.28` |
| `deepseek-v4-pro` | `$0.003625` | `$0.435` | `$0.87` |

本地 registry 也可以带 CNY 口径的 billing metadata，用于运行时成本展示；但本文档面向 reviewer 的价格以 DeepSeek API Docs 官方 USD 价格为准。文档中不得复制本地 registry 文件里的 provider secrets，包括 API keys。

## 优先模型

首版产品叙事应突出：

- DeepSeek V4，使用 `deepseek-v4-pro` 和 `deepseek-v4-flash`。
- MiMo，支持 provider-specific cache 字段的 usage 映射。
- MiniMax M3，作为 MiniMax 未来优先模型族。
- Qwen 与百炼，包括 coder 和通用 reasoning 模型。
- MiniMax office workflows，通过文档、表格、PDF 和演示文稿技能环境承载。

## 为什么重要

ZenMind 把模型选择视为运行时能力：

- Agent 可以携带默认模型配置。
- Chat run 可以覆盖模型和 reasoning effort。
- Web client 可以为 CODER agents 展示模型选项。
- Usage telemetry 携带 model key、token 明细、reasoning tokens、cache 明细和估算成本。

## Provider Registry 方向

模型支持应保持 registry-driven：

- Providers 定义 base URL、API key 处理、protocol 行为和默认模型。
- Models 定义 model key、provider key、model ID、protocol、vision 支持、reasoning 支持、context window 和 pricing metadata。
- Compatibility mapping 处理 provider-specific usage 字段，让 UI usage 保持稳定。

## MiniMax Office 路径

ZenMind 也把 MiniMax 视为不止聊天模型 provider。本地沙箱可以暴露面向 PDF、XLSX、DOCX 和 PPT 工作流的 office skill paths，为文档密集型任务提供合适的 agent runtime。
