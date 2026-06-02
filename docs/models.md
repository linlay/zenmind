# Model Support

ZenMind is designed to work well with modern Chinese model ecosystems while keeping the runtime provider registry flexible.

## Priority Models

The first product narrative should highlight:

- DeepSeek V4, including Pro and Flash style model entries.
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
