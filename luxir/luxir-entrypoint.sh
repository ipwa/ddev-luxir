#!/usr/bin/env bash
#ddev-generated
set -euo pipefail

libdir=/usr/local/lib/luxir
tier="${LUXIR_CPU_TIER:-auto}"

case "$tier" in
  v2|v3|v4)
    if ! "$libdir/luxir-$tier" --version >/dev/null 2>&1; then
      echo "luxir: LUXIR_CPU_TIER=$tier is not supported by this CPU (or emulation)." >&2
      echo "luxir: try LUXIR_CPU_TIER=auto, v3 or v2." >&2
      exit 1
    fi
    bin="$libdir/luxir-$tier"
    ;;
  auto)
    bin=""
    for t in v4 v3 v2; do
      if "$libdir/luxir-$t" --version >/dev/null 2>&1; then
        bin="$libdir/luxir-$t"
        break
      fi
    done
    if [ -z "$bin" ]; then
      echo "luxir: no CPU tier (v4, v3, v2) starts on this CPU." >&2
      exit 1
    fi
    ;;
  *)
    echo "luxir: invalid LUXIR_CPU_TIER '$tier' (use auto, v2, v3 or v4)." >&2
    exit 1
    ;;
esac

echo "luxir: using $("$bin" --version 2>&1 | head -n1)" >&2

# Make `luxir` available interactively in the container.
mkdir -p "$HOME/bin"
ln -sf "$bin" "$HOME/bin/luxir"
ln -sf "$bin" /tmp/luxir

# `luxir ...` or a leading flag that isn't a server flag: run the binary directly,
# so `docker run IMAGE luxir --help` works.
if [ "${1:-}" = "luxir" ]; then
  shift
  exec "$bin" "$@"
fi
case "${1:-}" in
  --help|-h|--version|-V) exec "$bin" "$@" ;;
esac

args=(
  "--store.backend=fs"
  "--store.data-dir=${LUXIR_DATA_DIR:-/var/lib/luxir}"
  "--server.http.port=9400"
  "--max-ram-mb=${LUXIR_MAX_RAM_MB:-512}"
  "--log-level=${LUXIR_LOG_LEVEL:-info}"
)

# LUXIR_EXTRA_ARGS is word-split on purpose: "--a=1 --b=2" becomes two arguments.
if [ -n "${LUXIR_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  args+=(${LUXIR_EXTRA_ARGS})
fi
args+=("$@")

exec "$bin" "${args[@]}"
