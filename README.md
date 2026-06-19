# k8s-airgap-images

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Air-Gap Ready](https://img.shields.io/badge/Air--Gap-Ready-0A9396?style=for-the-badge&labelColor=001219)](#workflow-overview)
[![Offline First](https://img.shields.io/badge/Offline-First-EE9B00?style=for-the-badge&labelColor=9B2226)](#workflow-overview)
[![Shell](https://img.shields.io/badge/Shell-Bash-2A9D8F?style=for-the-badge&logo=gnu-bash&logoColor=white&labelColor=1D3557)](#command-reference)
[![Harbor](https://img.shields.io/badge/Registry-Harbor-3A86FF?style=for-the-badge&labelColor=023047)](#push-workflow)
[![Catalog](https://img.shields.io/badge/Image-Catalog-6A4C93?style=for-the-badge&labelColor=240046)](#generated-image-lists)

```text
██╗  ██╗ █████╗ ███████╗      █████╗ ██╗██████╗  ██████╗  █████╗ ██████╗
██║ ██╔╝██╔══██╗██╔════╝     ██╔══██╗██║██╔══██╗██╔════╝ ██╔══██╗██╔══██╗
█████╔╝ ╚█████╔╝███████╗     ███████║██║██████╔╝██║  ███╗███████║██████╔╝
██╔═██╗ ██╔══██╗╚════██║     ██╔══██║██║██╔══██╗██║   ██║██╔══██║██╔═══╝
██║  ██╗╚█████╔╝███████║     ██║  ██║██║██║  ██║╚██████╔╝██║  ██║██║
╚═╝  ╚═╝ ╚════╝ ╚══════╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝

██╗███╗   ███╗ █████╗  ██████╗ ███████╗███████╗
██║████╗ ████║██╔══██╗██╔════╝ ██╔════╝██╔════╝
██║██╔████╔██║███████║██║  ███╗█████╗  ███████╗
██║██║╚██╔╝██║██╔══██║██║   ██║██╔══╝  ╚════██║
██║██║ ╚═╝ ██║██║  ██║╚██████╔╝███████╗███████║
╚═╝╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝

image catalog, pull cache, and registry promotion workflow
```

`k8s-airgap-images` is a local-first image acquisition and promotion utility for Kubernetes air-gapped environments. It normalizes source image lists, separates images by registry and authentication domain, pulls upstream images while Internet-connected, retags them for an internal registry, and pushes them into Harbor or another Docker/OCI-compatible registry.

This repository is designed to pair with `cantrellr/kubeharbor`, but it remains intentionally standalone. kubeharbor owns the Harbor VM and registry runtime. `k8s-airgap-images` owns source image lists, list normalization, credential prompts, upstream pulls, deterministic retagging, Harbor project preflight, and push logs.

At a glance, this project provides:

- **Deterministic Image Cataloging**: Normalize source files into generated lists grouped by registry, authentication domain, and operational purpose.
- **Connected Pull / Offline Push Workflow**: Pull images while Internet-connected, then clone or move the VM into the disconnected environment and push cached images to Harbor.
- **Credential Boundary Awareness**: Prompt separately for Docker Hub, Iron Bank, DHI, NGINX, and target registry credentials without forcing credentials when a registry can be skipped.
- **Harbor Project Preflight**: Check, create, and verify required Harbor projects before push attempts begin.
- **Predictable Retagging**: Use `strip-registry` by default for clean internal references, with `preserve-registry` available when collision avoidance matters more.
- **Operator-Friendly Logs**: Record pulled, skipped, failed, missing, retagged, and pushed images with enough detail to support reruns.

Design principles for this repo:

- **Offline-first promotion model** after source images are cached.
- **Portable tooling** based on Bash, Python, Docker, and optional Podman.
- **Idempotent reruns** for organize, pull, and push phases.
- **Credential minimization** with explicit prompts and non-interactive overrides.
- **Clean ownership boundary** between image movement and Harbor platform lifecycle.

---

## Table of Contents

- [k8s-airgap-images](#k8s-airgap-images)
  - [Key Capabilities](#key-capabilities)
  - [Supported Platforms & Requirements](#supported-platforms--requirements)
  - [Documentation Map](#documentation-map)
  - [Workflow Overview](#workflow-overview)
  - [Command Reference](#command-reference)
    - [First run](#first-run)
    - [Pull/download workflow](#pulldownload-workflow)
    - [Push workflow](#push-workflow)
  - [Generated Image Lists](#generated-image-lists)
  - [Retagging Model](#retagging-model)
  - [Environment Configuration](#environment-configuration)
  - [k8s-airgap-images and kubeharbor](#k8s-airgap-images-and-kubeharbor)
  - [Safety Controls & Idempotency](#safety-controls--idempotency)
  - [Generated Files & Directory Layout](#generated-files--directory-layout)
  - [Verification & Troubleshooting](#verification--troubleshooting)
  - [Diagram and Documentation Maintenance](#diagram-and-documentation-maintenance)

---

## Key Capabilities

- **Source List Normalization** – Reads operator-maintained image references from `source-lists/` and creates normalized output under `image-lists/`.
- **Registry-Specific List Splitting** – Separates public images, Docker Hardened Images, Iron Bank images, NGINX private registry images, archived Bitnami images, and aggregate manifests.
- **Interactive Pull Workflow** – Prompts for optional registry credentials up front, then pulls images with retry and fail-fast options.
- **Target Registry Push Workflow** – Prompts for the destination registry, authenticates, retags local images, verifies Harbor projects, and pushes cached content.
- **Harbor API Integration** – Uses Harbor API credentials to create missing projects before push unless project checks are skipped.
- **Mode-Based Target Mapping** – Supports `strip-registry` and `preserve-registry` target naming so operators can choose clean references or collision-resistant references.
- **Container Runtime Choice** – Uses Docker by default and supports Podman through `CONTAINER_CLI=podman`.

---

## Supported Platforms & Requirements

| Category | Details |
| --- | --- |
| Operating systems | Linux hosts with Bash, Python 3, and Docker or Podman |
| Privileges | Pull/push workflows usually require access to the selected container runtime socket or equivalent privileges |
| Runtime | Docker by default; Podman supported with `CONTAINER_CLI=podman` |
| Connectivity | Pull requires Internet access. Push is intended to run against an internally reachable registry without public Internet access |
| Target registry | Harbor or another Docker/OCI-compatible registry |
| Optional credentials | Docker Hub, `registry1.dso.mil`, `dhi.io`, `docker-registry.nginx.com`, and target Harbor/registry credentials |
| Companion repo | `cantrellr/kubeharbor` when this workflow is used with the standard air-gapped Harbor VM |

---

## Documentation Map

| Document | Purpose |
| --- | --- |
| [docs/System-Design-Document.md](docs/System-Design-Document.md) | Complete system design, architecture diagrams, workflow model, security posture, operations, failure modes, and roadmap. |
| [docs/operator-runbook.md](docs/operator-runbook.md) | Practical operator workflow for organizing lists, pulling images, pushing images, validating logs, and recovering from common failures. |
| [docs/documentation-maintenance.md](docs/documentation-maintenance.md) | Documentation and Mermaid diagram maintenance rules. |
| [diagrams/README.md](diagrams/README.md) | Local Mermaid rendering workflow for SVG/PNG exports. |

---

## Workflow Overview

1. **Source list maintenance:** Operators place upstream image references under `source-lists/`.
2. **Organize:** The Python normalization engine produces categorized lists under `image-lists/` and writes counts into `manifest-counts.txt`.
3. **Pull while connected:** Run the download workflow on an Internet-connected host or staging VM. Authenticate only to registries that need credentials.
4. **Move the cache:** Clone, move, or re-IP the VM into the air-gapped environment, or preserve the runtime image cache as part of the wider transfer process.
5. **Push offline:** Run the push workflow against Harbor or another internal registry. The tool retags images, checks or creates projects, and pushes cached content.
6. **Verify:** Review logs, missing-image reports, failed-pull reports, and target mapping output before declaring the image set ready for cluster use.

Use this repo when you need to move Kubernetes platform images from upstream registries into an internal registry for disconnected operations. Typical image sets include RKE2, Rancher, Argo CD, Istio, Kiali, monitoring, ingress, and platform utility images.

---

## Command Reference

### First run

```bash
chmod +x ./*.sh
./organize-image-lists.sh
cat image-lists/manifest-counts.txt
```

Wrapper behavior:

- `organize-image-lists.sh` runs `organize` only.
- `download-images.sh` runs `organize`, then `pull`.
- `push-images.sh` runs `organize`, then `push`.

### Pull/download workflow

```bash
./download-images.sh
```

The pull workflow asks for credentials at the beginning. You can skip each registry credential prompt independently.

Credential prompts happen in this order:

1. `docker.io`
2. `registry1.dso.mil`
3. `dhi.io` if DHI registry images exist
4. `docker-registry.nginx.com` if NGINX registry images exist

Useful options:

```bash
./download-images.sh --dry-run
./download-images.sh --force
./download-images.sh --fail-fast
./download-images.sh --list image-lists/20-registry1-dso-mil-images.list
CONTAINER_CLI=podman ./download-images.sh
```

### Push workflow

```bash
./push-images.sh --target kubeharbor.dev.kube/library
```

After the target prefix is entered, the push workflow authenticates to the target registry:

- If `--harbor-api-user` and `--harbor-api-password` are provided, login is non-interactive and uses those credentials.
- Otherwise, the workflow prompts for target registry credentials.

By default, that same credential entry is reused for Harbor project preflight, so the push flow asks once for credentials. Use `--harbor-api-user/--harbor-api-password` or `HARBOR_API_USER/HARBOR_API_PASSWORD` only when Harbor project-management credentials must differ from push credentials. Use `--separate-harbor-credentials` to force a separate Harbor API credential prompt.

Useful options:

```bash
./push-images.sh --dry-run --target kubeharbor.dev.kube/library
./push-images.sh --target kubeharbor.dev.kube/library --mode preserve-registry
./push-images.sh --list image-lists/10-docker-hardened-images.list --target kubeharbor.dev.kube/library
./push-images.sh --target kubeharbor.dev.kube/library --fail-fast
./push-images.sh --target kubeharbor.dev.kube/library --skip-project-check
./push-images.sh --target kubeharbor.dev.kube/library --ensure-projects
./push-images.sh --target kubeharbor.dev.kube/library --separate-harbor-credentials
./push-images.sh --target kubeharbor.dev.kube/library --harbor-api-url https://kubeharbor.dev.kube --harbor-api-user admin --harbor-api-password '<token>'
./push-images.sh --target kubeharbor.dev.kube/library --harbor-insecure
HARBOR_PROJECT_VERIFY_RETRIES=10 HARBOR_PROJECT_VERIFY_DELAY=3 ./push-images.sh --target kubeharbor.dev.kube/library
CONTAINER_CLI=podman ./push-images.sh --target kubeharbor.dev.kube/library
```

---

## Generated Image Lists

| File | Purpose |
| --- | --- |
| `image-lists/00-public-images.list` | Images treated as public/no-auth pulls. Docker Hub public images are normalized with `docker.io/`. |
| `image-lists/10-docker-hardened-images.list` | Docker Hardened Image / DHI-style images, including `docker.io/cantrellcloud/dhi-*` and `dhi.io/*`. |
| `image-lists/20-registry1-dso-mil-images.list` | Iron Bank / `registry1.dso.mil` images. |
| `image-lists/30-nginx-registry-images.list` | `docker-registry.nginx.com` images, separated because these commonly need registry credentials. |
| `image-lists/archived-images.list` | Bitnami images removed from the active pull/push workflow. |
| `image-lists/all-active-images.list` | All non-archived images to pull and push. |
| `image-lists/all-source-images.list` | All unique normalized images found in source files. |
| `image-lists/manifest-counts.txt` | Generated counts by category. |

---

## Retagging Model

Default push mode is `strip-registry`, which removes the upstream registry name from the target repository path:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/library/rancher/rancher:v2.14.2

docker.io/busybox:1.37.0
  -> kubeharbor.dev.kube/library/busybox:1.37.0

registry1.dso.mil/ironbank/big-bang/argocd:v3.1.4
  -> kubeharbor.dev.kube/library/ironbank/big-bang/argocd:v3.1.4
```

Single-segment upstream repositories, for example `docker.io/busybox`, are automatically placed under `library/` when the target path would otherwise be invalid for Harbor-style registries.

If you want to preserve the upstream registry name in the target path, use:

```bash
./push-images.sh --mode preserve-registry --target kubeharbor.dev.kube/library
```

That maps:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/library/docker.io/rancher/rancher:v2.14.2
```

---

## Environment Configuration

| Variable | Purpose |
| --- | --- |
| `CONTAINER_CLI=docker|podman` | Selects container runtime. |
| `SOURCE_DIR` | Overrides the default source image-list directory. |
| `LIST_DIR` | Overrides the generated image-list directory. |
| `LOG_DIR` | Overrides the log directory. |
| `RETRIES` | Controls pull/push retry attempts. |
| `HARBOR_API_URL` | Overrides Harbor API base URL. Defaults to `https://<target-registry-host>`. |
| `HARBOR_API_USER` | Provides Harbor API username for non-interactive project preflight. |
| `HARBOR_API_PASSWORD` | Provides Harbor API password/token for non-interactive project preflight. |
| `HARBOR_API_INSECURE=true` | Enables insecure Harbor API TLS. |
| `HARBOR_PROJECT_VERIFY_RETRIES` | Controls post-create verify retry count. |
| `HARBOR_PROJECT_VERIFY_DELAY` | Controls delay between verify retries in seconds. |

---

## k8s-airgap-images and kubeharbor

Keep the ownership boundary clean:

| Capability | k8s-airgap-images | kubeharbor |
| --- | --- | --- |
| Source image catalog | Owns | References |
| Image list normalization | Owns | Does not own |
| Pull/push workflows | Owns | Wraps |
| Harbor project preflight | Owns via Harbor API | Delegates |
| Harbor install and runtime lifecycle | Does not own | Owns |
| Docker/containerd storage under `/data` | Consumes | Owns |
| TLS and client trust | Requires working trust | Owns |

This separation lets image catalog work change quickly without coupling it to Harbor installation, data disk preparation, or certificate lifecycle automation.

---

## Safety Controls & Idempotency

- `organize` can be rerun safely; it regenerates list files from `source-lists/`.
- `pull` skips images already present locally unless `--force` is used.
- `push` retags deterministically and can be rerun safely.
- Pull and push logs are de-duplicated where appropriate.
- Failure logs are timestamped so reruns do not destroy troubleshooting evidence.
- Harbor project preflight creates missing projects unless `--skip-project-check` is used.
- Robot accounts are commonly push-scoped and may not be able to create projects. Use a project-management account for API preflight when required.
- If your target registry uses a private CA or self-signed certificate, configure Docker or Podman trust before pushing.

---

## Generated Files & Directory Layout

```text
k8s-airgap-images/
├── image-airgap.sh                  # Main utility: organize, pull, push
├── organize-image-lists.sh           # Wrapper for organize
├── download-images.sh                # Wrapper for organize + pull
├── push-images.sh                    # Wrapper for organize + push
├── source-lists/                     # Source image lists maintained by operators
├── image-lists/                      # Generated normalized lists
├── logs/                             # Pull/push/project reconcile logs
├── tools/organize_image_lists.py      # Python list normalization engine
├── docs/                             # Operator and architecture documentation
└── diagrams/                         # Mermaid source and local render workflow
```

---

## Verification & Troubleshooting

After organize:

```bash
cat image-lists/manifest-counts.txt
wc -l image-lists/all-active-images.list
```

Before push:

```bash
./push-images.sh --dry-run --target kubeharbor.dev.kube/library
```

When troubleshooting, start with:

- `logs/` for pull, push, missing-image, and Harbor project reconciliation details.
- [docs/operator-runbook.md](docs/operator-runbook.md) for practical rerun and recovery guidance.
- [docs/System-Design-Document.md](docs/System-Design-Document.md) for workflow and architecture context.

Important operational notes:

- For single-segment images that map under `library/`, make sure a `library` project/namespace exists in the target registry.
- `strip-registry` is the default because it matches the standard internal registry layout and produces cleaner image references.
- `preserve-registry` is available when you need collision avoidance across `docker.io`, `quay.io`, `ghcr.io`, `registry1.dso.mil`, and other upstream registries.

---

## Diagram and Documentation Maintenance

GitHub Actions are not required for this repo. Diagrams are rendered locally with Mermaid CLI.

First-time local setup:

```bash
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
```

Normal re-sync after editing Mermaid source or the system design document:

```bash
./diagrams/apply-diagram-updates.sh .
```

Do not run the diagram renderer with `sudo`. It should run as your normal user. The browser dependency installer uses `sudo` internally only for `apt-get`.
