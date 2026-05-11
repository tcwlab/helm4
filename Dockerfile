# ─────────────────────────────────────────────────────────────────────────────
# tcwlab/helm4
#
# Lean Alpine image with pinned Helm version.
# Image tag corresponds to Helm version: tcwlab/helm4:4.1.4
#
# Supported platforms: linux/amd64, linux/arm64
#
# Build (multi-arch):
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     --build-arg HELM_VERSION=4.1.4 \
#     -t tcwlab/helm4:4.1.4 --push .
# ─────────────────────────────────────────────────────────────────────────────

#####
# STAGE 1: base image
#####
FROM --platform=$BUILDPLATFORM alpine:3.23 AS base
ARG BUILDPLATFORM
# hadolint ignore=DL3018
RUN apk add -U --no-cache curl tar git bash ca-certificates && \
    apk upgrade && \
    rm -rf /var/cache/apk/*

#####
# STAGE 2: download Helm binary (architecture-aware)
#####
FROM base AS dependencies
ARG HELM_VERSION=4.1.4
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN case "$(apk --print-arch)" in \
        aarch64) LOCAL_ARCH="arm64" ;; \
        x86_64)  LOCAL_ARCH="amd64" ;; \
        *) echo "Unsupported architecture: $(apk --print-arch)" && exit 1 ;; \
    esac && \
    curl -fsSL \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${LOCAL_ARCH}.tar.gz" \
      -o /tmp/helm.tar.gz && \
    tar -xzf /tmp/helm.tar.gz -C /tmp && \
    mv "/tmp/linux-${LOCAL_ARCH}/helm" /usr/local/bin/helm && \
    rm -rf /tmp/helm.tar.gz "/tmp/linux-${LOCAL_ARCH}" && \
    chmod +x /usr/local/bin/helm && \
    helm version --short

#####
# STAGE 3: production image
#####
FROM base AS release
ARG HELM_VERSION=4.1.4

LABEL org.opencontainers.image.title="helm4" \
      org.opencontainers.image.description="Helm 4 — pinned version for reproducible CI" \
      org.opencontainers.image.vendor="The Chameleon Way" \
      org.opencontainers.image.url="https://hub.docker.com/r/tcwlab/helm4" \
      org.opencontainers.image.source="https://github.com/tcwlab/helm4" \
      org.opencontainers.image.version="${HELM_VERSION}"

COPY --from=dependencies /usr/local/bin/helm /usr/local/bin/helm

# Non-root user. Pre-create the Helm cache/config directories Helm 3+ expects
# under $HOME so that consumer pipelines do not have to write to $HOME from
# read-only mounts.
RUN addgroup -S helmusr && adduser -S helmusr -G helmusr && \
    mkdir -p /home/helmusr/.config/helm \
             /home/helmusr/.cache/helm \
             /home/helmusr/.local/share/helm && \
    chown -R helmusr:helmusr /home/helmusr

USER helmusr
WORKDIR /workspace
ENTRYPOINT ["helm4"]
