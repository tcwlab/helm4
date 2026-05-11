# tcwlab/helm4

> Pinned [Helm](https://helm.sh/) CLI in a hardened Alpine container for reproducible Kubernetes pipelines. Image tag = Helm version. Drop-in for Forgejo/GitHub Actions container jobs that need deterministic toolchain versions.

[![Docker Pulls](https://img.shields.io/docker/pulls/tcwlab/helm4?label=pulls)](https://hub.docker.com/r/tcwlab/helm4)
[![Image Size](https://img.shields.io/docker/image-size/tcwlab/helm4/latest?label=size)](https://hub.docker.com/r/tcwlab/helm4/tags)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

---

## Quick start

```bash
docker pull tcwlab/helm4:latest

# Run against the current directory
docker run --rm -v "$PWD:/workspace" tcwlab/helm4:latest version
```

Or as a Forgejo / GitHub Actions container job:

```yaml
helm-lint:
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/helm4:latest
  steps:
    - name: Checkout (shell-based, no Node required)
      env:
        GITHUB_TOKEN: ${{ secrets.FORGEJO_TOKEN }}
      run: |
        git config --global init.defaultBranch main
        git init .
        git remote add origin \
          "https://oauth2:${GITHUB_TOKEN}@git.mon.k8b.co/${GITHUB_REPOSITORY}.git"
        git fetch --depth=1 origin "${GITHUB_SHA}"
        git checkout FETCH_HEAD
    - run: helm lint ./chart
```

> Quick-start examples use `:latest` so you can try the image immediately.
> For production CI pipelines, pin a concrete tag — see [Tags](#tags) below.

---

## Tags

> Version numbers below are illustrative. For the current set of tags, see
> [Docker Hub tags](https://hub.docker.com/r/tcwlab/helm4/tags).

| Tag                   | Description                                            |
| --------------------- | ------------------------------------------------------ |
| `4.1.4`, `4.1`, `3` | Concrete SemVer (recommended for production pipelines) |
| `latest`              | Rolling reference; always points at the newest release |

**Always pin a concrete version in production.** `latest` is fine for local
experiments, but pinning protects your pipeline from a toolchain bump that
lands without a PR. The major/minor floating tags (`4`, `4.1`) are
convenient for internal use; external consumers should pin the full SemVer.

The `helm` image tag **mirrors** the Helm CLI version exactly. When Helm
4.1.4 is released, `tcwlab/helm4:4.1.4` contains that exact version (not a
wrapper SemVer).

---

## Supported architectures

- `linux/amd64`
- `linux/arm64`

Every tag is a multi-arch manifest list. Docker pulls the right
architecture automatically.

---

## What's included

| Tool                              | Version              | Purpose                        |
| --------------------------------- | -------------------- | ------------------------------ |
| [`helm`](https://helm.sh/)        | `4.1.4`             | Kubernetes package manager     |
| `curl`                            | from Alpine 3.23 apk | Download support               |
| `tar`                             | from Alpine 3.23 apk | Archive extraction             |
| `git`                             | from Alpine 3.23 apk | Helm chart repos via git       |
| `bash`                            | from Alpine 3.23 apk | Shell compatibility            |
| `ca-certificates`                 | from Alpine 3.23 apk | TLS/SSL certificate validation |

Base image: `alpine:3.23`. Default workdir: `/workspace`. Default user:
`helmusr` (non-root). Helm cache/config directories pre-created under
`/home/helmusr/.config/helm`, `/home/helmusr/.cache/helm`, and
`/home/helmusr/.local/share/helm`.

---

## Usage

### Lint a chart

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/helm4:4.1.4 lint ./chart
```

### Render templates (smoke test)

```bash
docker run --rm -v "$PWD:/workspace" tcwlab/helm4:4.1.4 \
  template ./chart --debug
```

### Use against a cluster

To talk to a real cluster, mount your kubeconfig:

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  -v "$HOME/.kube:/home/helmusr/.kube:ro" \
  tcwlab/helm4:4.1.4 \
  list -A
```

### Forgejo workflow — full snippet

```yaml
helm-lint:
  name: Helm Lint
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/helm4:4.1.4
  steps:
    - name: Checkout
      env:
        GITHUB_TOKEN: ${{ secrets.FORGEJO_TOKEN }}
      run: |
        git config --global init.defaultBranch main
        git init .
        git remote add origin \
          "https://oauth2:${GITHUB_TOKEN}@git.mon.k8b.co/${GITHUB_REPOSITORY}.git"
        git fetch --depth=1 origin "${GITHUB_SHA}"
        git checkout FETCH_HEAD
    - name: helm lint
      run: helm lint ./chart
    - name: helm template (smoke test)
      run: helm template ./chart --debug | head -40
```

---

## Configuration

### Volume mount points

| Path                     | Purpose                                    |
| ------------------------ | ------------------------------------------ |
| `/workspace`             | Default workdir; mount your chart repo here |
| `/home/helmusr/.kube`    | Mount kubeconfig (read-only) to talk to a cluster |
| `/home/helmusr/.cache/helm` | Helm dependency cache (mount to persist between runs) |

### Environment variables

The image passes all environment variables directly to Helm. Common patterns:

| Variable             | Example                       | Purpose                              |
| -------------------- | ----------------------------- | ------------------------------------ |
| `HELM_KUBECONTEXT`   | `production`                  | Use a specific kube context          |
| `HELM_NAMESPACE`     | `auth`                        | Default namespace                    |
| `HELM_DEBUG`         | `true`                        | Verbose debug output                 |
| `KUBECONFIG`         | `/home/helmusr/.kube/config`  | Path to the kubeconfig file          |

### Working directory

The image runs with `WORKDIR /workspace`. If your chart is in a
subdirectory, use:

```yaml
- run: |
    cd ./charts/my-wrapper
    helm lint .
    helm template .
```

---

## Why `tcwlab/helm4` and not upstream images?

Pinning discipline. Public Helm images (Docker Hub, GHCR) often use
`latest` or floating major versions, which means your CI toolchain can
silently advance to a new Helm version without a PR. `tcwlab/helm4` enforces
the principle that **every tool version is explicit** — the image tag is
the version, and upgrades happen via PR.

Additional benefits:

- **Deterministic builds** — same tag always pulls the exact Helm version
  (no surprises).
- **Consistent Alpine base** — all tcwlab images use Alpine 3.23, minimal
  and hardened identically.
- **Multi-arch by default** — `linux/amd64` and `linux/arm64` in every
  release.
- **Security scanning** — each build is scanned with Trivy before
  publication.

---

## Source, issues, contributing

- **Source**: [`github.com/tcwlab/helm4`](https://github.com/tcwlab/helm4)
- **Issues / feature requests**: [`github.com/tcwlab/helm4/issues`](https://github.com/tcwlab/helm4/issues)
- **Docker Hub**: [`hub.docker.com/r/tcwlab/helm4`](https://hub.docker.com/r/tcwlab/helm4)

---

## Build, supply chain

Every release is built and published by the repo's own
[`.forgejo/workflows/ci.yml`](https://github.com/tcwlab/helm4/blob/main/.forgejo/workflows/ci.yml)
on a Forgejo runner:

- Multi-arch build (`linux/amd64`, `linux/arm64`) via `docker buildx` with
  `--sbom=true --provenance=mode=max`.
- Trivy vulnerability scan on `HIGH`/`CRITICAL` severity (failures show up
  as PR comments).
- Self-lint via `betterlint` running against the Dockerfile.

The `helm` image version is cut by `semantic-release` from Conventional
Commits on `main`. The version exactly mirrors the Helm CLI version (e.g.,
release of Helm 4.1.4 triggers a new `tcwlab/helm4:4.1.4` image).

---

## License

Apache License 2.0. See [`LICENSE`](LICENSE) for the full text.

Helm itself is licensed under Apache 2.0. See
[`helm/helm`](https://github.com/helm/helm) for details.
