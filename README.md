# Self-Hosted AI Stack

> Run local LLMs with Ollama, a clean web UI (Open WebUI), and secure remote access over a Tailscale VPN — your own private ChatGPT on your hardware.

[![CI](https://github.com/AntoniRomera/self-hosted-ai/actions/workflows/ci.yml/badge.svg)](https://github.com/AntoniRomera/self-hosted-ai/actions/workflows/ci.yml)
![Ollama](https://img.shields.io/badge/Ollama-local%20LLMs-black)
![Docker](https://img.shields.io/badge/Docker-compose-2496ED)
![Tailscale](https://img.shields.io/badge/Tailscale-VPN-242526)
![License](https://img.shields.io/badge/license-MIT-green)

## Why

Keep your prompts and data **private and free**: serve open models locally, reach
them from anywhere via VPN (**no ports exposed to the internet**), and avoid
per-token costs for everyday use.

## What's inside

- 🧠 **Ollama** — local model serving. Ships with a small, CPU-friendly default
  set: `llama3.2:3b` and `qwen2.5:3b` for chat, plus `nomic-embed-text` for
  Open WebUI's RAG/embeddings. Fully configurable via `OLLAMA_MODELS`.
- 💬 **Open WebUI** — chat interface, model switching, conversation history, RAG.
- 🔐 **Tailscale** — private mesh VPN; access your stack from laptop/phone with
  **zero open ports** (Tailscale Serve publishes Open WebUI over tailnet HTTPS).
- 🐳 **Docker Compose** — one command to bring it all up.
- 🌐 **Caddy** (optional) — reverse proxy with automatic public TLS for real
  domains, behind the `tls` Compose profile.

All images are pinned for reproducibility.

## Architecture

```mermaid
flowchart LR
    Dev[Laptop / Phone] -- Tailscale VPN --> TS[tailscale container]
    subgraph Host[Docker host]
      TS -- "Serve (HTTPS)" --> UI[Open WebUI :8080]
      UI --> O[Ollama :11434]
    end
    Dev -. "optional public HTTPS" .-> Caddy[Caddy :443]
    Caddy --> UI
```

No host ports are published by default. The only way in is through your tailnet
(or, optionally, the Caddy reverse proxy if you explicitly enable it).

## Getting started

```bash
git clone https://github.com/AntoniRomera/self-hosted-ai.git
cd self-hosted-ai
cp .env.example .env

# Edit .env and set at minimum:
#   TS_AUTHKEY        - from https://login.tailscale.com/admin/settings/keys
#   WEBUI_SECRET_KEY  - generate: openssl rand -hex 32
$EDITOR .env

# Bring it all up and preload the configured models:
make up
```

Then open `https://<TS_HOSTNAME>.<your-tailnet>.ts.net` from any device on your
tailnet. (`TS_HOSTNAME` defaults to `self-hosted-ai`.)

> **Local-only access without Tailscale?** Copy
> `docker-compose.override.yml.example` to `docker-compose.override.yml`, then
> `make up`. Open WebUI will be reachable at `http://127.0.0.1:3000`.

### Tailscale auth key

Generate an auth key in the Tailscale admin console. For an unattended home
server, a **reusable + ephemeral + tagged** key works well. Put it in `.env`:

```env
TS_AUTHKEY="tskey-auth-xxxxxxxxxxxx"
```

The key is read only from the environment — it is **never** committed (`.env` is
gitignored). The container runs in userspace networking mode, so it needs no
special host privileges.

## Configuration

| Variable           | Description                                                        | Default                                       |
|--------------------|--------------------------------------------------------------------|-----------------------------------------------|
| `OLLAMA_MODELS`    | Comma-separated models to preload                                  | `llama3.2:3b,qwen2.5:3b,nomic-embed-text`     |
| `OLLAMA_KEEP_ALIVE`| How long a model stays in memory after last use                   | `5m`                                          |
| `WEBUI_PORT`       | Host port (only when local-only override is enabled)              | `3000`                                         |
| `WEBUI_SECRET_KEY` | **Required.** Signs session cookies (`openssl rand -hex 32`)       | _none_                                         |
| `WEBUI_AUTH`       | Set `false` to disable login (trusted single user only)           | `true`                                         |
| `TS_AUTHKEY`       | **Required secret.** Tailscale auth key                            | _none_                                         |
| `TS_HOSTNAME`      | Node name on the tailnet (MagicDNS)                               | `self-hosted-ai`                              |
| `TS_EXTRA_ARGS`    | Extra args for `tailscale up`                                      | _empty_                                        |
| `COMPOSE_PROFILES` | Set to `tls` to enable the Caddy reverse proxy                     | _empty_                                        |
| `CADDY_DOMAIN`     | Public domain for Caddy TLS (required with `tls` profile)          | `ai.example.com`                              |
| `*_IMAGE`          | Pinned image tags (`OLLAMA_IMAGE`, `OPENWEBUI_IMAGE`, …)           | see `.env.example`                            |

Full deep-dive: [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md).

## Hardware notes

LLMs are memory-bound. Pick model sizes to fit your RAM (CPU) or VRAM (GPU):

| Hardware                  | Comfortable model sizes      | Examples                                  |
|---------------------------|------------------------------|-------------------------------------------|
| CPU only, 8 GB RAM        | ~3B (quantized)              | `llama3.2:3b`, `qwen2.5:3b`               |
| CPU only, 16 GB RAM       | up to ~7-8B (slow)           | `llama3.1:8b`, `qwen2.5:7b`               |
| GPU, 8-12 GB VRAM         | 7-8B comfortably             | `llama3.1:8b`, `mistral:7b`               |
| GPU, 24 GB VRAM           | 14-32B (quantized)           | `qwen2.5:14b`, `qwen2.5:32b-instruct-q4`  |

The defaults target CPU-only 8 GB+ hosts so the stack just works out of the box.

**Enable an NVIDIA GPU:** uncomment the `deploy.resources` (or `gpus: all`) block
under the `ollama` service in `docker-compose.yml`. Requires the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/).
Details in [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md#gpu-acceleration).

## TLS / remote access options

Two supported paths:

1. **Tailscale Serve (default, recommended).** Zero-config HTTPS using tailnet
   certificates. Open WebUI is published only on your tailnet — nothing is
   exposed publicly. Config lives in [`tailscale/serve.json`](tailscale/serve.json).
2. **Public Caddy + real domain.** For exposing the UI on the public internet.
   Set `COMPOSE_PROFILES=tls` and `CADDY_DOMAIN=your.domain` in `.env`, point the
   domain's DNS at the host, and Caddy provisions a Let's Encrypt certificate
   automatically. See [`Caddyfile`](Caddyfile).

## Backup & restore

Chat history and settings live in the `openwebui-data` volume (a SQLite DB at
`/app/backend/data`).

```bash
# Back up Open WebUI data to ./backups/openwebui-<timestamp>.tar.gz
make backup

# Also back up downloaded models (large):
make backup-all

# Restore a backup (stop the stack first):
make down
make restore FILE=backups/openwebui-20260101-120000.tar.gz
make up
```

Backups use an ephemeral `alpine` container to tar the named volume, so they work
while the stack is running and need no host tooling.

## Make targets

| Target            | What it does                                  |
|-------------------|-----------------------------------------------|
| `make up`         | Start the stack and preload models            |
| `make down`       | Stop and remove containers                    |
| `make logs`       | Follow logs                                    |
| `make ps`         | Show service status                           |
| `make pull-models`| Pull models from `OLLAMA_MODELS`              |
| `make backup`     | Back up Open WebUI data                        |
| `make restore`    | Restore a backup (`FILE=...`)                 |
| `make validate`   | `docker compose config` sanity check          |
| `make lint`       | Run yamllint + shellcheck                      |
| `make test`       | Run the compose smoke tests                    |
| `make clean`      | Remove containers **and volumes** (data loss) |

## Testing

This is an infra project, so "tests" mean validating the stack definition
rather than running it. [`tests/smoke-compose.sh`](tests/smoke-compose.sh)
renders the Compose config with dummy secrets and asserts the invariants that
matter here:

- every service is defined and wired correctly (`open-webui` -> `ollama`);
- **no host ports are published** in the default config;
- the optional override binds only to `127.0.0.1`;
- Caddy appears **only** under the `tls` profile;
- all images are pinned (no `:latest`);
- required secrets (`WEBUI_SECRET_KEY`, `TS_AUTHKEY`) are enforced;
- `tailscale/serve.json` is valid JSON proxying to `open-webui:8080`;
- `.env.example` holds placeholders, never real keys.

```bash
make test     # runs tests/smoke-compose.sh
```

The same checks (plus yamllint, shellcheck, and `caddy validate`) run in CI on
every push and pull request via
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Troubleshooting

- **Can't reach the UI on the tailnet.** Check `make logs` for the `tailscale`
  service. Confirm the node appears in your Tailscale admin console and that
  MagicDNS + HTTPS certificates are enabled for your tailnet.
- **`WEBUI_SECRET_KEY is required`.** You started Compose without setting it.
  Run `make up`, which validates `.env`, or set the value before `docker compose up`.
- **Model pull is slow / fails.** Large models take time. Re-run
  `make pull-models`; it is idempotent and resumes.
- **Out of memory / killed.** The model is too big for your RAM/VRAM. Pick a
  smaller size from the hardware table above.
- **Caddy can't get a cert.** Ensure `CADDY_DOMAIN` resolves to this host and
  ports 80/443 are reachable from the internet.

## Related projects

Part of a small self-hosting / infra portfolio:

- [`terraform-aws-modules`](https://github.com/AntoniRomera/terraform-aws-modules) — reusable AWS infrastructure modules.
- [`ai-agents-framework`](https://github.com/AntoniRomera/ai-agents-framework) — agent orchestration you can point at this stack's Ollama endpoint.
- [`mcp-erp-server`](https://github.com/AntoniRomera/mcp-erp-server) — MCP server example.
- [`ai-job-aggregator`](https://github.com/AntoniRomera/ai-job-aggregator) — data pipeline example.
- [`openclaw-integration`](https://github.com/AntoniRomera/openclaw-integration) — integration glue.

## License

MIT © Antoni Romera Luis
