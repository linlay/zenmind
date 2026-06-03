# Model Support

ZenMind is designed to work well with modern Chinese model ecosystems while keeping the runtime provider registry flexible.

## DeepSeek V4 Agent Configuration

ZenMind uses the current DeepSeek V4 model IDs:

| Model key | Provider | Protocol | Model ID | Context | Max output | Pricing source |
| --- | --- | --- | --- | --- | --- | --- |
| `deepseek-v4-flash` | `deepseek` | `OPENAI` | `deepseek-v4-flash` | `maxInputTokens: 1048576` (1M) | `maxOutputTokens: 393216` | DeepSeek API Docs |
| `deepseek-v4-pro` | `deepseek` | `OPENAI` | `deepseek-v4-pro` | `maxInputTokens: 1048576` (1M) | `maxOutputTokens: 393216` | DeepSeek API Docs |

The runtime registry uses `modelId`, `provider`, `protocol`, `isReasoner`, `isFunction`, `maxInputTokens`, and `pricing.inputCacheHit/inputCacheMiss/output`. These fields are verified by the Agent Platform: `maxInputTokens` is loaded as the model context window, and the pricing fields are used by usage cost estimation for cache-hit input, cache-miss input, and output tokens.

The DeepSeek provider compatibility layer preserves `reasoning_content` for DeepSeek-style reasoning messages. ZenMind does not carry a workaround for an already-fixed upstream bug here; it only keeps provider-specific request and response compatibility fields that the runtime reads.

DeepSeek V4 reasoning uses `reasoning_effort=max` for the highest supported thinking effort. If a caller uses the legacy `xhigh` level, the compatibility path maps it to `max`.

## Official DeepSeek Pricing

Pricing is verified against DeepSeek API Docs and listed in USD per 1M tokens:

| Model | Input cache hit | Input cache miss | Output |
| --- | --- | --- | --- |
| `deepseek-v4-flash` | `$0.0028` | `$0.14` | `$0.28` |
| `deepseek-v4-pro` | `$0.003625` | `$0.435` | `$0.87` |

Local registries may also carry CNY billing metadata for runtime cost display, but reviewer-facing pricing in this document follows the official DeepSeek API Docs USD values. Provider secrets, including API keys from local registry files, must not be copied into documentation.

## Priority Models

The first product narrative should highlight:

- DeepSeek V4, using `deepseek-v4-pro` and `deepseek-v4-flash`.
- MiMo, with usage mapping support for provider-specific cache fields.
- MiniMax M3, as a priority future-facing MiniMax model family.
- Qwen and Bailian, including coder and general reasoning models.
- MiniMax office workflows through document, spreadsheet, PDF, and presentation skill environments.

## Why It Matters

ZenMind treats model choice as a runtime capability:

- Agents can carry default model configuration.
- Chat runs can override model and reasoning effort.
- The web client can show model options for CODER agents.
- Usage telemetry carries model key, token details, reasoning tokens, cache details, and estimated cost.

## Provider Registry Direction

Model support should stay registry-driven:

- Providers define base URL, API key handling, protocol behavior, and default model.
- Models define model key, provider key, model ID, protocol, vision support, reasoning support, context window, and pricing metadata.
- Compatibility mapping handles provider-specific usage fields so UI usage remains stable.

## MiniMax Office Path

ZenMind also treats MiniMax as more than a chat model provider. The local sandbox can expose office-oriented skill paths for PDF, XLSX, DOCX, and PPT workflows, giving agents a runtime designed for document-heavy tasks.
