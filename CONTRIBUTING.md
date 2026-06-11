# Contributing

Thanks for your interest in improving the Self-Hosted AI Stack. This is an
infra/ops project (Docker Compose + shell), so contributions are mostly about
keeping the stack reproducible, lint-clean, and secure.

## Local checks

Before opening a PR, run the same checks CI does:

```bash
# Validate the Compose file renders and is internally consistent
make validate

# Lint YAML and shell scripts
make lint

# Run the compose smoke tests (renders the config, checks invariants)
make test
```

`make lint` runs:

- **yamllint** (config in `.yamllint`, line-length relaxed to 120)
- **shellcheck** on `scripts/*.sh` and `tests/*.sh`

`make test` runs [`tests/smoke-compose.sh`](tests/smoke-compose.sh), which
renders the Compose config with dummy secrets and asserts the project's
invariants (no default host ports, pinned images, required secrets enforced,
valid `serve.json`, etc.). It starts no containers.

Install the tools if you don't have them:

```bash
# macOS
brew install yamllint shellcheck hadolint

# Debian/Ubuntu
sudo apt-get install -y yamllint shellcheck
```

`make validate` requires Docker but reads secrets from `.env`. For a quick
syntax-only check without real secrets you can export dummies:

```bash
TS_AUTHKEY=x WEBUI_SECRET_KEY=x docker compose config -q
```

## Conventions

- **No `version:` key** in `docker-compose.yml` (modern, lint-clean form). Use
  the top-level `name:` instead.
- **Pin image tags.** Never use floating tags like `:latest` in the committed
  compose file. Add a `*_IMAGE` env override if a service needs to track a
  rolling tag.
- **Shell scripts** start with `set -euo pipefail`, source `scripts/lib.sh` for
  shared helpers, and must pass shellcheck.
- **2-space indentation** for YAML and shell; tabs only in the `Makefile`. The
  `.editorconfig` enforces this.
- **Never commit secrets.** `.env` is gitignored; add new variables to
  `.env.example` with safe placeholders and document them in
  `docs/CONFIGURATION.md`.

## Adding a service

1. Add it to `docker-compose.yml` with a pinned `*_IMAGE` env var, a healthcheck,
   a named volume (if it has state), and the `ai-net` network.
2. Do **not** publish host ports unless the service genuinely needs them; prefer
   tailnet/Caddy exposure.
3. Update `README.md` and `docs/CONFIGURATION.md`.
4. Run `make validate && make lint`.

## Commit / PR

- Keep PRs focused and describe the change and how you tested it.
- Confirm `make validate` and `make lint` pass.
