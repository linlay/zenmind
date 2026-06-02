# Architecture

ZenMind is organized around a Desktop shell that wraps the runtime services needed for a complete agent experience.

<div align="center">
  <img src="./media/zenmind-architecture.svg" alt="ZenMind architecture" />
</div>

## Desktop Shell

ZenMind Desktop is the user entry point. It installs bundled services, prepares local configuration, starts services in dependency order, monitors health, and embeds service web surfaces.

The Desktop shell is responsible for the product experience:

- one-click setup and service lifecycle
- token bridge for authenticated embedded webviews
- control center, logs, settings, and plugin surfaces
- shared navigation between assistant, services, market, help, and settings

## Core Services

ZenMind is built from four core services:

- `zenmind-app-server`: identity, OAuth2/OIDC, admin console, app access tokens, and device-facing access.
- `agent-platform`: the agent runtime, including model registry, tools, memory, channels, AGW UI events, HITL, usage, and sub-agent orchestration.
- `agent-webclient`: the main agent UI for chat, timeline replay, model switching, viewport rendering, HITL panels, attachments, and usage display.
- `agent-container-hub`: local sandbox sessions and environment templates for controlled tool execution.

## Runtime Shape

The preferred product shape is Desktop first:

- Desktop owns installation, initialization, and service health.
- App Server provides trust and token issuance.
- Agent Platform owns agent execution and AGW UI streams.
- Agent Webclient renders the user-facing agent workspace.
- Container Hub provides local sandboxes for tools and long-lived sessions.

Mobile and browser clients should use the same AGW UI protocol rather than a separate agent contract.

## What This Repository Is

This repository is the project entry point for ZenMind. It describes the product, architecture, protocol, model support, and mobile direction. The implementation lives across the sibling service repositories.
