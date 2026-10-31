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
- `~/workspace/.vps_name`: Display name of this node (e.g. `Muse-13`)
- `~/workspace/.worker_id`: Unique identifier for this instance (e.g. `worker-muse-13`)
- `~/workspace/.auth_key`: Local authorization secret (auto-generated)

## Auto-restart after a VM replacement

A VM replacement wipes running processes, `/var` (system crontab) and
`/etc` (systemd). Only `~/` survives, so this repo alone cannot restart
itself, and it deliberately does NOT install crontab, `.bashrc` hooks,
or systemd units — those would be hidden persistence and would not
survive a replacement anyway.

The durable pattern is two parts:

1. **In this repo:** `ensure_worker.sh` is idempotent and transparent.
   Run it any number of times: it starts Hermes only if it is not
   running, and starts 9Router in tray mode bound to `127.0.0.1:20128`
   only if `http://127.0.0.1:20128/v1/models` does not answer. It
   never duplicates a healthy service, never overwrites identity or
   auth files, and never logs a secret.
2. **Outside the VM, in Muse:** one user-authorized Muse hook (or
   cron) that polls every 60 seconds and, only when a service is
   dead, wakes Muse to run `ensure_worker.sh` and verify it. That
   schedule is managed by Muse, is visible to the user, survives VM
   replacement, and is the only auto-restart trigger. Without it,
   a new VM still needs one manual `bash setup.sh Muse-13`.

Manual guard check, no chat needed afterwards:

```bash
bash ~/workspace/hirmis-na-9-router/ensure_worker.sh
curl -s http://127.0.0.1:20128/v1/models | head -c 200
grep 'Connected to Hub successfully' ~/workspace/hermes.log
```

## License

MIT License - see [LICENSE](LICENSE) for details.
