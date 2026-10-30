# Hermes Autonomous Agent & 9Router Infrastructure

A lightweight, integrated Node.js environment combining **9Router** (AI Router & Token Saver proxy) with the **Hermes Autonomous Agent** for distributed developer task execution and system telemetry.

## Overview

This repository provides an automated agent runtime for Linux instances:
1. **9Router Service**: Runs a local OpenAI-compatible API proxy on port `20128` (`http://127.0.0.1:20128/v1`), providing seamless load balancing, fallback routing, and token optimization across multiple AI models.
2. **Hermes Agent**: Connects outward via a secure WebSocket channel to the central dashboard, reporting live node health metrics (CPU utilization, free RAM, uptime) and executing developer automation workflows.

## Features

- **Standard Node.js Runtime**: Zero external compiler or Python versioning conflicts.
- **Local Token Security**: Automatically generates and enforces an authorized local secret in `~/workspace/.auth_key` with strict file permissions (`chmod 600`).
- **Resilient Auto-Reconnection**: Reconnects to the controller with exponential backoff if network connectivity drops.
- **One-Command Setup**: Single shell script installs dependencies and starts both services in the background.

## Installation & Running

```bash
git clone https://github.com/makassartoraja936-max/hirmis-na-9-router.git ~/workspace/hirmis-na-9-router
cd ~/workspace/hirmis-na-9-router
bash setup.sh
```

## Configuration

Custom node configuration is optionally read from:
- `~/workspace/.vps_name`: Display name of this node (e.g. `Muse-11`)
- `~/workspace/.worker_id`: Unique identifier for this instance (e.g. `worker-muse-11`)
- `~/workspace/.auth_key`: Local authorization secret (auto-generated)

## License

MIT License - see [LICENSE](LICENSE) for details.
