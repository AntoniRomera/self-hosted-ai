# Configuration reference

Every knob for the Self-Hosted AI Stack lives in `.env` (copied from
`.env.example`). This document explains each one, plus the GPU and security
models.

## Environment variables

### Models

| Variable            | Default                                    | Notes |
|---------------------|--------------------------------------------|-------|
| `OLLAMA_MODELS`     | `llama3.2:3b,qwen2.5:3b,nomic-embed-text`  | Comma-separated. `scripts/preload-models.sh` pulls each one. Pick sizes that fit your hardware (see below). |
| `OLLAMA_KEEP_ALIVE` | `5m`                                       | Time a model stays resident after the last request. `-1` keeps it loaded forever, `0` unloads immediately. Longer = faster follow-ups, more RAM. |

`nomic-embed-text` is an embedding model. Keep it in the list if you want Open
WebUI's document RAG / knowledge features to work.

### Open WebUI

| Variable           | Default | Notes |
|--------------------|---------|-------|
| `WEBUI_SECRET_KEY` | _none_  | **Required.** Signs session cookies. Generate with `openssl rand -hex 32`. Changing it invalidates existing sessions. |
| `WEBUI_AUTH`       | `true`  | `false` disables the login screen — only acceptable for a single trusted user on a private tailnet. |
| `WEBUI_PORT`       | `3000`  | Host port used **only** when you enable the local-only override file. Ignored in the default (Tailscale-only) setup. |

### Tailscale

| Variable        | Default          | Notes |
|-----------------|------------------|-------|
| `TS_AUTHKEY`    | _none_           | **Required secret.** From the Tailscale admin console. Reusable + ephemeral + tagged recommended for servers. |
| `TS_HOSTNAME`   | `self-hosted-ai` | MagicDNS node name. UI ends up at `https://<TS_HOSTNAME>.<tailnet>.ts.net`. |
| `TS_EXTRA_ARGS` | _empty_          | Passed verbatim to `tailscale up`, e.g. `--advertise-tags=tag:ai --accept-routes`. |

The container uses `TS_USERSPACE=true` (userspace networking) so it needs no
`NET_ADMIN` capability or `/dev/net/tun`. State persists in the
`tailscale-state` volume. `TS_SERVE_CONFIG=/config/serve.json` makes the
container run Tailscale Serve, publishing Open WebUI over tailnet HTTPS.

### Reverse proxy (optional public TLS)

| Variable           | Default          | Notes |
|--------------------|------------------|-------|
| `COMPOSE_PROFILES` | _empty_          | Set to `tls` to start the Caddy service. |
| `CADDY_DOMAIN`     | `ai.example.com` | Public domain Caddy serves and provisions a certificate for. Required when the `tls` profile is on. |

### Image pins

`OLLAMA_IMAGE`, `OPENWEBUI_IMAGE`, `TAILSCALE_IMAGE`, `CADDY_IMAGE` let you
override the pinned tags. To track Open WebUI's rolling release instead of a
pinned tag, set `OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main` (less
reproducible, but always latest).

## Model selection guidance

| Hardware             | Comfortable sizes  | Examples                                 |
|----------------------|--------------------|------------------------------------------|
| CPU, 8 GB RAM        | ~3B quantized      | `llama3.2:3b`, `qwen2.5:3b`              |
| CPU, 16 GB RAM       | up to ~7-8B (slow) | `llama3.1:8b`, `qwen2.5:7b`              |
| GPU, 8-12 GB VRAM    | 7-8B               | `llama3.1:8b`, `mistral:7b`             |
| GPU, 24 GB VRAM      | 14-32B quantized   | `qwen2.5:14b`, `qwen2.5:32b-instruct-q4`|

Quantized variants (`q4_K_M`, etc.) trade a little quality for much lower memory.
Browse the [Ollama library](https://ollama.com/library) for tags.

## GPU acceleration

The stack runs CPU-only by default. To use an NVIDIA GPU:

1. Install the
   [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/)
   on the host and restart Docker.
2. In `docker-compose.yml`, uncomment **one** of the GPU blocks under the
   `ollama` service:

   ```yaml
   deploy:
     resources:
       reservations:
         devices:
           - driver: nvidia
             count: all
             capabilities: ["gpu"]
   ```

   or the shorthand:

   ```yaml
   gpus: all
   ```

3. `make restart`. Verify with:

   ```bash
   docker compose exec ollama nvidia-smi
   ```

AMD GPUs need the ROCm Ollama image (`ollama/ollama:rocm`) — set `OLLAMA_IMAGE`
accordingly and follow Ollama's ROCm docs.

## Security model

- **No open ports by default.** The Compose file publishes nothing to the host.
  Access is only via the tailnet (Tailscale Serve) unless you opt in to the
  local-only override or the Caddy `tls` profile.
- **Secrets stay in `.env`.** `TS_AUTHKEY` and `WEBUI_SECRET_KEY` are only ever
  read from the environment. `.env` is gitignored; `.env.example` holds
  placeholders only. The Compose file fails fast (`${VAR:?...}`) if a required
  secret is missing.
- **Isolated network.** All services share an internal bridge network
  (`ai-net`). Ollama and Open WebUI are not reachable from the host or LAN.
- **Healthchecks** gate startup ordering (Open WebUI waits for Ollama; Tailscale
  and Caddy wait for Open WebUI) and let `make ps` show real readiness.
- **Userspace Tailscale** avoids granting the container elevated host
  capabilities.

## Local-only access (no Tailscale)

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
make up   # Open WebUI now on http://127.0.0.1:${WEBUI_PORT}
```

The override binds to `127.0.0.1`, keeping it off your LAN. You still need a
valid (even if unused) `TS_AUTHKEY` because the tailscale service is part of the
default stack — or remove that service from your override if you truly want no
Tailscale at all.
