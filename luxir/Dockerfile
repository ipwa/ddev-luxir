# Unofficial, community-maintained image for Luxir (https://luxir.org).
# Base: ubuntu:24.04 (glibc >= 2.35 is required by Luxir).
FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3

ARG LUXIR_VERSION=0.1.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl tzdata \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    base="https://github.com/luxir-search/luxir/releases/download/v${LUXIR_VERSION}"; \
    mkdir -p /usr/local/lib/luxir /tmp/dl; cd /tmp/dl; \
    curl -fsSLO "${base}/SHA256SUMS"; \
    for t in v2 v3 v4; do curl -fsSLO "${base}/luxir-${LUXIR_VERSION}-linux-x86_64-${t}"; done; \
    sha256sum -c --ignore-missing SHA256SUMS; \
    for t in v2 v3 v4; do \
      install -m 0755 "luxir-${LUXIR_VERSION}-linux-x86_64-${t}" "/usr/local/lib/luxir/luxir-${t}"; \
    done; \
    rm -rf /tmp/dl

# uid 1000 is taken by the base image's "ubuntu" user.
RUN groupadd -g 1001 luxir \
 && useradd -u 1001 -g luxir -m -s /bin/bash luxir \
 && mkdir -p /var/lib/luxir \
 && chown luxir:luxir /var/lib/luxir

COPY --chmod=0755 luxir-entrypoint.sh /usr/local/bin/luxir-entrypoint.sh

USER luxir
EXPOSE 9400 9401
VOLUME /var/lib/luxir
ENTRYPOINT ["/usr/local/bin/luxir-entrypoint.sh"]
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=10 \
  CMD curl -fsS http://127.0.0.1:9400/health || exit 1

LABEL org.opencontainers.image.source="https://github.com/ipwa/ddev-luxir" \
      org.opencontainers.image.version="${LUXIR_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.description="UNOFFICIAL, community-maintained container image of the Luxir search server. Not affiliated with the Luxir project."
