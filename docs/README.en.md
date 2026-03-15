# ZenMind

The primary up-to-date operating guide is maintained in:

- [docs/README.md](/Users/linlay-macmini/Project/zenmind/zenmind/docs/README.md)

This repository now acts as the local control plane for sibling repos:

- one local profile file
- generated `.env/configs` in sibling repos
- one root `docker compose`
- host-level `cloudflared` forwarding to `127.0.0.1:11945`
