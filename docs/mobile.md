# Mobile Direction

ZenMind is designed to support mobile clients without inventing a separate agent protocol.

## Shared Protocol

Mobile clients should connect through the same AGW UI semantics used by Desktop and web:

- query to start a run
- stream events to render live progress
- submit for HITL interactions
- steer to add instructions while a run is active
- interrupt to stop a run
- viewport payloads for richer forms and confirmations
- usage snapshots for transparent model cost and token feedback

## Gateway And Channels

The Agent Platform already has a channel and gateway direction for clients that cannot connect like a local browser surface.

Mobile support should use that shape:

- a channel identifies the client surface and routing policy
- gateway connections bridge mobile clients to the platform
- the same agent keys and team routing can be reused
- artifacts and resources stay tied to the chat and run model

## Product Goals

The mobile version should feel like the same ZenMind system:

- continue or inspect active agent runs
- answer HITL questions and approvals from the phone
- review usage and run status
- receive artifacts and references
- work with the same agent catalog used by Desktop

## Near-Term Scope

The first mobile version should prioritize continuity:

- session list and active run state
- chat timeline rendering
- HITL submit flows
- attachment and resource preview
- usage visibility

Full Desktop service management remains a Desktop responsibility.
