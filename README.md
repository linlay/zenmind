# ZenMind

<div align="center">

[English](./README.md) | [简体中文](./docs/README.zh-CN.md)

<img src="./docs/media/zenmind-logo.svg" alt="ZenMind logo" height="96" />

</div>

ZenMind is a desktop-first AI agent platform for local, web, and mobile workflows.

It packages the core agent runtime into one Desktop experience, connects to modern Chinese model ecosystems such as DeepSeek V4, MiMo, MiniMax M3, and Qwen/Bailian, and exposes a custom AGW UI protocol for rich agent interaction.

## Highlights

- One Desktop app to install, initialize, start, stop, and monitor the ZenMind services.
- Native support direction for DeepSeek V4, MiMo, MiniMax M3, Qwen/Bailian, and MiniMax office workflows.
- A custom AGW UI protocol for streaming output, HITL approval, viewport rendering, usage telemetry, and sub-agent invocation.
- A local sandbox layer for long-lived agent sessions, tool environments, and office/document automation.
- Designed for the same agent experience across Desktop, web clients, and upcoming mobile clients.

## Demo Video

> Placeholder: add the ZenMind walkthrough video here.

## Screenshots

> Placeholder: add Desktop, agent chat, service center, AGW UI, and mobile preview screenshots here.

## One-Click Desktop

ZenMind is distributed through ZenMind Desktop. The Desktop app wraps the core services, prepares local configuration, starts the runtime in the right order, and gives users a single control center for the whole system.

> Download placeholder: add the official Desktop release link here.

## Core Architecture

<div align="center">
  <img src="./docs/media/zenmind-architecture.svg" alt="ZenMind architecture" />
</div>

ZenMind Desktop brings together four core services:

- `zenmind-app-server`: authentication, OIDC, admin console, and app access tokens.
- `agent-platform`: agent runtime, model registry, tools, memory, HITL, usage, and sub-agent orchestration.
- `agent-webclient`: chat UI, timeline, model switching, viewport rendering, and usage display.
- `agent-container-hub`: local sandbox sessions, environment templates, and container-backed tool runtimes.

## AGW UI Protocol

AGW UI is ZenMind's custom protocol between clients and the Agent Platform. It combines HTTP, SSE, and optional WebSocket transport with a rich event model for agent work:

- H2A streaming and attach recovery.
- HITL modes for question, approval, form, and plan confirmation.
- Builtin and HTML viewports for interactive agent UI.
- Usage snapshots for tokens, cache, reasoning, tool calls, and estimated cost.
- `agent_invoke` for sub-agent tasks that stream back into the main timeline.

Read more in [AGW UI Protocol](./docs/agwui.md).

## Documentation

- [Architecture](./docs/architecture.md)
- [AGW UI Protocol](./docs/agwui.md)
- [Model Support](./docs/models.md)
- [Mobile Direction](./docs/mobile.md)
- [Docs Index](./docs/README.md)

## License

See [LICENSE](./LICENSE).
