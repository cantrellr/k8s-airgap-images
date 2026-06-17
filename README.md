# Image Air-Gap Pull/Push Utility Bundle

This bundle normalizes the provided image sources, removes Bitnami images from the active workflow, pulls all active images, and retags/pushes them into a target registry/repository prefix.

## Directory layout

```text
image-airgap-bundle/
├── image-airgap.sh                  # Main utility: organize, pull, push
├── organize-image-lists.sh           # Wrapper for organize
├── download-images.sh                # Wrapper for organize + pull
├── push-images.sh                    # Wrapper for organize + push
├── source-lists/                     # Original uploaded source image lists
├── image-lists/                      # Generated normalized lists
└── logs/                             # Pull/push success, failure, and map logs
```

## Generated image lists

| File | Purpose |
|---|---|
| `image-lists/00-public-images.list` | Images treated as public/no-auth pulls. Docker Hub public images are included here and are normalized with `docker.io/`. |
| `image-lists/10-docker-hardened-images.list` | Docker Hardened Image / DHI-style images, including `docker.io/cantrellcloud/dhi-*` and `dhi.io/*`. |
| `image-lists/20-registry1-dso-mil-images.list` | Iron Bank / `registry1.dso.mil` images. |
| `image-lists/30-nginx-registry-images.list` | `docker-registry.nginx.com` images, separated because these commonly need registry credentials. |
| `image-lists/archived-images.list` | Bitnami images removed from the active pull/push workflow. |
| `image-lists/all-active-images.list` | All non-archived images to pull and push. |
| `image-lists/all-source-images.list` | All unique normalized images found in the provided source files. |
| `image-lists/manifest-counts.txt` | Generated counts by category. |

## First run

```bash
chmod +x ./*.sh
./organize-image-lists.sh
```

## Pull/download workflow

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
./download-images.sh --list image-lists/20-registry1-dso-mil-images.list
CONTAINER_CLI=podman ./download-images.sh
```

## Push workflow

```bash
./push-images.sh
```

You will be prompted for the target registry/repository prefix, for example:

```text
kubeharbor.dev.kube
```

Default push mode is `strip-registry`, which removes the upstream registry name from the target repository path:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/rancher/rancher:v2.14.2

registry1.dso.mil/ironbank/big-bang/argocd:v3.1.4
  -> kubeharbor.dev.kube/ironbank/big-bang/argocd:v3.1.4
```

After the target prefix is entered, the push workflow prompts for credentials to authenticate to the target registry. The target registry login prompt defaults to yes, but you can answer no for an open/no-auth lab registry.

If you want to preserve the upstream registry name in the target path, use:

```bash
./push-images.sh --mode preserve-registry --target kubeharbor.dev.kube
```

That maps:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/docker.io/rancher/rancher:v2.14.2
```

Useful options:

```bash
./push-images.sh --dry-run --target kubeharbor.dev.kube
./push-images.sh --target kubeharbor.dev.kube --mode preserve-registry
./push-images.sh --list image-lists/10-docker-hardened-images.list --target kubeharbor.dev.kube
CONTAINER_CLI=podman ./push-images.sh --target kubeharbor.dev.kube
```

## Idempotency behavior

- `organize` can be rerun safely; it regenerates list files from `source-lists/`.
- `pull` skips images already present locally unless `--force` is used.
- `push` retags deterministically and can be rerun safely.
- Pull and push logs are de-duplicated where appropriate.
- Failure logs are timestamped so reruns do not destroy troubleshooting evidence.

## Important operational notes

- If your target registry uses a private CA or self-signed certificate, configure Docker or Podman trust before pushing.
- For Harbor, make sure the project in the target prefix already exists. For `kubeharbor.dev.kube`, the appropriate project must exist.
- `strip-registry` is the default because it matches the requested internal registry layout and produces cleaner image references.
- `preserve-registry` is available when you need collision avoidance across `docker.io`, `quay.io`, `ghcr.io`, `registry1.dso.mil`, and other upstream registries.
