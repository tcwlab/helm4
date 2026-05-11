# helm4 — Repository Context

> **Onboarding handshake:** Read in this order:
>
> 1. `Projects/CLAUDE.md` (global standards, workspace-local)
> 2. `tcwlab/CLAUDE.md` (toolchain context, workspace-local)
> 3. This file (helm-specific)

---

## What is `helm`?

`helm` is the container image that bundles a pinned [Helm](https://helm.sh/) CLI, hardened on Alpine 3.23, intended for Forgejo/GitHub Actions `container:` jobs that lint, template, or deploy Kubernetes Helm charts in CI. The image tag mirrors the Helm CLI version exactly (`tcwlab/helm4:4.1.4` contains Helm 4.1.4), so consumer pipelines can pin a concrete Helm version without surprises.

This image grew out of the *adopt-not-build* book examples (`Buecher/adopt-not-build-examples/02-companion-helm/`) and the broader pattern across TCW verticals where a Helm-chart wrapper sits in front of an OSS upstream (Zitadel, Authentik, Vault, Cilium, FluxCD, …). Those wrapper repos all need a deterministic, reproducible Helm CLI in their CI — without dragging in `setup-helm` actions, Node.js, or the host runner's pre-installed Helm binary.

### Consumers

Primary consumers are the Helm-chart-wrapper repos in K8Box, Atrium, Spectrum, and IdentServ — anywhere a Helm chart is linted (`helm lint`), template-rendered (`helm template`) or deployed in CI. Plus the *adopt-not-build* book companion examples, where the image carries the `helm-lint` job.

---

## What's inside?

[Dockerfile](https://git.mon.k8b.co/tcwlab/helm4/src/branch/main/Dockerfile):

- **Stage 1 — `base`**: `alpine:3.23` with `curl`, `tar`, `git`, `bash`, `ca-certificates` from apk.
- **Stage 2 — `dependencies`**: Architecture-aware download of the Helm binary from `https://get.helm.sh/`. Picks `arm64` or `amd64` based on `apk --print-arch`. Installs to `/usr/local/bin/helm` and runs `helm version --short` as a smoke test inside the build.
- **Stage 3 — `release`**: Inherits from `base`, copies the Helm binary from the dependencies stage, sets OCI labels, creates a non-root user `helmusr`, and pre-creates the Helm 4 cache/config directories under `$HOME` so consumer pipelines do not need to write to `$HOME` from read-only mounts.

Contents:

| Component         | Version            | Purpose                              |
| ----------------- | ------------------ | ------------------------------------ |
| Helm CLI          | `4.1.4`           | Kubernetes package manager           |
| `curl`            | Alpine 3.23 apk    | Download support                     |
| `tar`             | Alpine 3.23 apk    | Archive extraction                   |
| `git`             | Alpine 3.23 apk    | Helm chart repos via git             |
| `bash`            | Alpine 3.23 apk    | Shell compatibility                  |
| `ca-certificates` | Alpine 3.23 apk    | TLS/SSL certificate validation       |

ENTRYPOINT: `helm`. WORKDIR: `/workspace`. USER: `helmusr` (non-root).

Intentionally **no** Node.js — the image is meant for shell-based checkout (`git init && git fetch`), not Forgejo's JS-based `actions/checkout`. Saves image footprint and avoids Node.js version dependencies.

---

## Tool Versions and Pinning Strategy

The image tag **mirrors** the Helm CLI version exactly: `tcwlab/helm4:4.1.4` contains Helm 4.1.4. There is no separate wrapper SemVer — the only version-relevant variable is the Helm CLI itself.

### Update Discipline

- **Helm bump**: PR with `ARG HELM_VERSION=<new-version>` in the Dockerfile. The CI pipeline reads this ARG in the `publish` step and tags the image accordingly. New image tag = new Helm version.
- **Alpine major bump**: PR with `FROM alpine:<n>` in stage 1. No image SemVer change — Alpine is the base, not the application.
- **Helm major bump (3 → 4)**: Coordinate with consumer repos via the K8Box/Atrium platform CLAUDE.md — Helm 4 has breaking chart compatibility considerations. Roll out across the toolchain in lockstep, not piecemeal.

---

## Release Procedure

`semantic-release` as in the other image repos: auto-tag from Conventional Commits, Forgejo release, Docker Hub push as `tcwlab/helm4:<helm-version>-<semver>` (immutable), `tcwlab/helm4:<helm-version>` (float), and `tcwlab/helm4:latest` (float).

Consumer pipelines pin the concrete `<helm-version>` (e.g. `4.1.4`). `latest` is acceptable for local experiments but not for production CI — see [`tcwlab/CLAUDE.md`](../CLAUDE.md) for the consumer-side pinning discipline.

---

## What to do on version bump

1. PR with the Helm version bump in the Dockerfile (`ARG HELM_VERSION=<new>`).
2. CI passes — smoke test (`helm version --short`) must succeed.
3. Trivy scan must pass HIGH/CRITICAL — Helm releases occasionally bring transitive Go-stdlib CVEs that need a patched Helm release before we can publish.
4. **Consumer outreach** on Helm minor/major bump: the consumer repos in `Buecher/adopt-not-build-examples/`, `Atrium/idp/`, `K8Box/*/` etc. pin `HELM_VERSION` in their `ci.yml` `env:` block. On bump, coordinate these values upward via PRs in those repos.
5. Update the top-level [`tcwlab/versions.yaml`](../versions.yaml).

---

## What explicitly does NOT belong in this image

- **Helm plugins** (`helm-diff`, `helm-secrets`, `helm-unittest`, …). The image stays minimal — plugins are a consumer concern. If a consumer needs a plugin, it gets installed in a CI step or in a downstream image that derives from `tcwlab/helm4`.
- **kubectl**. We have a separate image planning (currently in `legacy/kubectl/` as reference) for that. Mixing kubectl into helm contradicts the "one tool per image" discipline.
- **A pre-configured kubeconfig**. Consumers mount their own kubeconfig at runtime; the image must not assume any cluster context.
- **Helm chart repository credentials**. Configured at runtime via `helm repo add` with the consumer's secrets.
- **Node.js**. Intentionally omitted — see "What's inside?" above.

---

## Consumer Snippets

### Lint a chart in a Forgejo container job

```yaml
helm-lint:
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/helm4:4.1.4
  steps:
    - name: Checkout (shell)
      env:
        GITHUB_TOKEN: ${{ secrets.FORGEJO_TOKEN }}
      run: |
        git config --global init.defaultBranch main
        git init .
        git remote add origin \
          "https://oauth2:${GITHUB_TOKEN}@git.mon.k8b.co/${{ github.repository }}.git"
        git fetch --depth=1 origin "${{ github.sha }}"
        git checkout FETCH_HEAD

    - name: helm lint
      run: helm lint ./chart

    - name: helm template (smoke test)
      run: helm template ./chart --debug | head -40
```

### Render templates and run a Trivy config scan

```yaml
helm-render:
  runs-on: ubuntu-22.04
  container:
    image: tcwlab/helm4:4.1.4
  steps:
    - uses: https://data.forgejo.org/actions/checkout@v4
    - run: helm template ./chart > /tmp/rendered.yaml

trivy-scan:
  runs-on: ubuntu-22.04
  needs: [helm-render]
  container:
    image: tcwlab/trivy:0.70.0
  steps:
    - uses: https://data.forgejo.org/actions/checkout@v4
    - run: trivy config ./chart
```

Complete pipeline pattern: see [`Buecher/adopt-not-build-examples/.forgejo/workflows/ci.yml`](https://git.mon.k8b.co/Buecher/adopt-not-build-examples/src/branch/main/.forgejo/workflows/ci.yml) for the canonical lint-template-scan combination.

---

## Known Pain Points / Open Topics

- **Cluster connectivity from CI**. The image itself has no opinion about how the consumer reaches a real cluster — kubeconfig is mounted at runtime. The K8Box-internal practice is to use a short-lived `helm install --kube-token=…` rather than mounting a static kubeconfig, but that is a consumer concern.
- **Helm cache between CI runs**. The image pre-creates `~/.cache/helm` so that consumer pipelines can mount a cache volume to persist chart dependencies between runs. There is no centralized TCW Helm cache backend — intentional, because setup and maintenance overhead do not fit current scale.
- **`apk add git` uses the Alpine default version**. On security vulnerabilities in git, we would have to push a base image update ourselves. Currently `git` is upgraded with `apk upgrade`, but not version-pinned — trade-off between reproducibility and security-patch velocity.
- **No plugin pre-installation**. Consumers who need `helm-diff` or `helm-secrets` install them in a CI step. This is a deliberate trade-off (image stays small, plugin versions stay in the consumer's hands), but creates duplication in pipelines that need the same plugin frequently. If a TCW-wide plugin combination crystallizes, it can graduate to a dedicated `tcwlab/helm4-with-diff` image — but only when the duplication actually hurts.
