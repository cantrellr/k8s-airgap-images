# k8s-airgap-images Operator Runbook

This runbook covers the practical operating model for `k8s-airgap-images`: organize source lists, pull upstream images, move the cached runtime into an air gap, and push images into Harbor.

## Prerequisites

- Linux host with Bash and Python 3.
- Docker or Podman installed.
- Source image lists under `source-lists/`.
- Registry credentials available where needed.
- Internal registry CA trust configured before pushing to a private Harbor endpoint.

When used with kubeharbor, confirm the container runtime data root is backed by `/data` before pulling large image sets:

```bash
docker info --format '{{.DockerRootDir}}'
```

## 1. Organize image lists

```bash
./organize-image-lists.sh
cat image-lists/manifest-counts.txt
```

Review the generated files:

```bash
ls -lah image-lists
wc -l image-lists/*.list
```

The generated `all-active-images.list` is the normal pull and push input. Bitnami images are written to `archived-images.list` and removed from the active workflow.

## 2. Dry-run pull

```bash
./download-images.sh --dry-run
```

Use dry-run output to validate credential gates and list selection before spending time on a full pull.

## 3. Pull images on the Internet-connected host

```bash
./download-images.sh
```

The workflow prompts for Docker Hub first, then Iron Bank, then optional DHI and NGINX private registry access when relevant lists exist.

Useful scoped pull:

```bash
./download-images.sh --list image-lists/20-registry1-dso-mil-images.list
```

Review pull logs:

```bash
ls -lah logs
cat logs/pull-failed-*.list 2>/dev/null || true
```

Do not move into the air gap until pull failures are understood. Missing upstream layers cannot be recovered after disconnect.

## 4. Move or clone into the air gap

When using the kubeharbor VM-clone model, do not prune Docker before cloning. The local image cache is the asset being carried across the boundary.

## 5. Dry-run push

```bash
./push-images.sh --dry-run --target kubeharbor.dev.kube/library
```

Check the target prefix and push mode. Default mode is `strip-registry`.

## 6. Push into Harbor

```bash
./push-images.sh --target kubeharbor.dev.kube/library
```

For collision avoidance, preserve the upstream registry hostname in the target path:

```bash
./push-images.sh --target kubeharbor.dev.kube/library --mode preserve-registry
```

If the Harbor project-management account is different from the registry push account:

```bash
./push-images.sh \
  --target kubeharbor.dev.kube/library \
  --separate-harbor-credentials
```

## 7. Validate push results

```bash
ls -lah logs
cat logs/push-failed-*.list 2>/dev/null || true
cat logs/push-missing-local-*.list 2>/dev/null || true
head -20 logs/push-image-map-*.tsv 2>/dev/null || true
```

Validate a representative image from the target registry:

```bash
docker pull kubeharbor.dev.kube/library/rancher/rancher:v2.14.2
```

## Troubleshooting

| Symptom | Cause | Action |
| --- | --- | --- |
| `No .list or .txt source files found` | Wrong or empty `source-lists/` | Add source files or set `SOURCE_DIR`. |
| Pull is denied | Missing credentials or wrong registry account | Re-run and authenticate to the relevant registry. |
| Pull is slow or rate-limited | Upstream rate limiting | Authenticate to Docker Hub or reduce concurrency by running scoped lists. |
| Push missing local image | Image was not pulled or cache was pruned | Pull the source image again before pushing. |
| Harbor project create denied | Account lacks project-management rights | Use a Harbor account with project create/list permissions or precreate projects. |
| TLS unknown authority | CA trust missing | Install Harbor CA trust for Docker or Podman. |

## Operational guardrails

- Keep `source-lists/` under review control.
- Treat generated `image-lists/` as reproducible output.
- Keep logs long enough for transfer evidence and troubleshooting.
- Do not commit credentials or sensitive logs.
- Do not copy Docker layer files directly into Harbor storage.
