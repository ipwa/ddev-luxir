# ddev-luxir

A DDEV add-on that runs a Luxir search server (https://luxir.org) as a `luxir` service.
The repo also builds and publishes the Luxir container image
`ghcr.io/ipwa/luxir`, which other projects use in CI.
Hosted on GitHub. License: Apache-2.0.

## Where things are

- `luxir/Dockerfile`, `luxir/luxir-entrypoint.sh`: the image. This is the **single source of
  truth**, used both by the add-on's local build and by `.github/workflows/image.yml`.
- `docker-compose.luxir.yaml`, `install.yaml`, `commands/`: the add-on.
- `tests/test.bats`: bats tests, run by `.github/workflows/tests.yml`.
- `docs/luxir-notes.md`: Luxir API and runtime facts. Read it before touching flags or the API.
  Update it when you learn something new.
- `PLAN.md` (local only, not committed): the phased build plan.

## Conventions

- Follow `ddev/ddev-addon-template` and `ddev/ddev-solr`. When unsure how DDEV expects
  something, read those repos rather than guessing.
- Every file installed into a user's project starts with the `#ddev-generated` marker, so DDEV
  can update and remove it.
- Shell scripts use `#!/usr/bin/env bash` and `set -euo pipefail`, and must pass `shellcheck`.
- User-tunable settings are env vars with defaults in compose (`${LUXIR_X:-default}`).
  Users override them with `ddev dotenv set .ddev/.env.luxir --luxir-x=value`.
- Pin versions everywhere. Never use `:latest` in the add-on or docs.
- The Luxir version appears in exactly two places: the `ARG LUXIR_VERSION` default in
  `luxir/Dockerfile` and the compose default. `tests/test.bats` asserts that they match.
- Never publish Luxir's port on the host except through the DDEV router (`HTTP_EXPOSE` /
  `HTTPS_EXPOSE`). Luxir has no authentication.

## Commands

- Lint: `shellcheck luxir/*.sh commands/*/*`
- Image: `docker build --platform linux/amd64 -t luxir-dev luxir/`
- Tests: `bats tests/test.bats`. These need DDEV installed. For iteration, use
  `bats tests/test.bats --filter-tags '!release'`.

## Commits

Small commits, one logical change each, imperative subject line. Don't push, tag or create
releases unless asked.

## When unsure

Luxir is pre-1.0. Check behaviour against the running container, for example
`docker run --rm luxir-dev luxir --help`, before relying on it. If PLAN.md turns out to be
wrong, stop and report rather than working around it silently.
