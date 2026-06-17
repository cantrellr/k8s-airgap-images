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

Wrapper behavior:

- `organize-image-lists.sh` runs `organize` only.
- `download-images.sh` runs `organize`, then `pull`.
- `push-images.sh` runs `organize`, then `push`.

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
./download-images.sh --fail-fast
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

docker.io/busybox:1.37.0
  -> kubeharbor.dev.kube/library/busybox:1.37.0

registry1.dso.mil/ironbank/big-bang/argocd:v3.1.4
  -> kubeharbor.dev.kube/ironbank/big-bang/argocd:v3.1.4
```

Single-segment upstream repositories (for example `docker.io/busybox` or `dhi.io/keycloak`) are automatically placed under `library/` to produce a project/repository shape accepted by Harbor-style registries.

Before push attempts begin, the script reconciles Harbor projects referenced by the target images: check if each project exists, create missing projects, verify they exist, then continue with push.

After the target prefix is entered, the push workflow authenticates to the target registry:

- If `--harbor-api-user` and `--harbor-api-password` are provided, login is non-interactive and uses those credentials.
- Otherwise, it prompts for target registry credentials (defaults to yes).

By default, that same credential entry is reused for Harbor project preflight, so push flow asks once for credentials. Use `--harbor-api-user/--harbor-api-password` (or `HARBOR_API_USER/HARBOR_API_PASSWORD`) only when Harbor project-management credentials must differ from push credentials. Use `--separate-harbor-credentials` to force a separate Harbor API credential prompt.

When `--harbor-api-user` and `--harbor-api-password` are both provided, push flow is non-interactive for target login and Harbor preflight: the script will not prompt for credentials. If login fails, it logs the failure and exits.

Harbor preflight HTTP behavior:

- Initial project read `200`: read success is logged.
- Initial project read `404`: project is treated as missing and create is attempted.
- Initial project read `403`: no warning/error is emitted at that stage; create is attempted.
- Post-create verify read `403`: treated as a failure and the push exits.

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
./push-images.sh --target kubeharbor.dev.kube --fail-fast
./push-images.sh --target kubeharbor.dev.kube --skip-project-check
./push-images.sh --target kubeharbor.dev.kube --ensure-projects
./push-images.sh --target kubeharbor.dev.kube --separate-harbor-credentials
./push-images.sh --target kubeharbor.dev.kube --harbor-api-url https://kubeharbor.dev.kube --harbor-api-user admin --harbor-api-password '<token>'
./push-images.sh --target kubeharbor.dev.kube --harbor-insecure
HARBOR_PROJECT_VERIFY_RETRIES=10 HARBOR_PROJECT_VERIFY_DELAY=3 ./push-images.sh --target kubeharbor.dev.kube
CONTAINER_CLI=podman ./push-images.sh --target kubeharbor.dev.kube
```

## Environment configuration

- `CONTAINER_CLI=docker|podman` selects container runtime.
- `SOURCE_DIR`, `LIST_DIR`, `LOG_DIR` override default directories.
- `RETRIES` controls pull/push retry attempts.
- `HARBOR_API_URL` overrides Harbor API base URL (defaults to `https://<target-host>`).
- `HARBOR_API_USER`, `HARBOR_API_PASSWORD` provide Harbor API credentials.
- `HARBOR_API_INSECURE=true` enables insecure Harbor API TLS.
- `HARBOR_PROJECT_VERIFY_RETRIES` controls post-create verify retry count.
- `HARBOR_PROJECT_VERIFY_DELAY` controls delay between verify retries in seconds.

## Idempotency behavior

- `organize` can be rerun safely; it regenerates list files from `source-lists/`.
- `pull` skips images already present locally unless `--force` is used.
- `push` retags deterministically and can be rerun safely.
- Pull and push logs are de-duplicated where appropriate.
- Failure logs are timestamped so reruns do not destroy troubleshooting evidence.

## Important operational notes

- If your target registry uses a private CA or self-signed certificate, configure Docker or Podman trust before pushing.
- The push workflow preflights Harbor projects and creates missing ones before pushing unless `--skip-project-check` is used.
- Harbor project preflight uses Harbor API credentials (interactive prompt, or `HARBOR_API_USER`/`HARBOR_API_PASSWORD`, or corresponding CLI options).
- Robot accounts are commonly push-scoped and may not be able to create projects. Use a project-management account for API preflight when required.
- For single-segment images that map under `library/`, make sure a `library` project/namespace exists in the target registry.
- `strip-registry` is the default because it matches the requested internal registry layout and produces cleaner image references.
- `preserve-registry` is available when you need collision avoidance across `docker.io`, `quay.io`, `ghcr.io`, `registry1.dso.mil`, and other upstream registries.
