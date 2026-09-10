# Segment1 OPDEV v2.7 air-gap inventory contract

This repository carries an explicit artifact contract for `cantrellr/k8mm-seg1opdev-multicluster` v2.7 so platform releases do not rely on manually comparing two repositories.

## Contract files

- `contracts/seg1opdev-v2.7-required-charts.list` — the 16 Helm package filenames required by the deployment package.
- `contracts/seg1opdev-v2.7-required-source-images.list` — pullable upstream container images required by the deployment.
- `contracts/seg1opdev-v2.7-local-images.list` — private/local build images required by the deployment but not backed by an authoritative public Internet source in this repository.
- `source-lists/seg1opdev-v2.7-images.list` — direct upstream images used by the active Segment1 OPDEV release.
- `source-lists/active-bitnami-seg1opdev-v2.7.list` — narrow Bitnami exceptions that remain active even though legacy Bitnami content is archived by default.
- `source-lists/rancher-images-v2-15.txt` — Rancher v2.15 transitive/system image inventory. The Segment1 contract also explicitly pins the Rancher server and direct utility images used by the deployment values.

## Why active Bitnami exceptions exist

The repository normally archives Bitnami images. Segment1 OPDEV v2.7 still resolves the packaged `cert-manager` and `contour` charts to seven exact Bitnami runtime images. Those seven images are explicitly opted back into `all-active-images.list`; the rest of the legacy Bitnami inventory remains archived.

The required active exceptions are:

```text
docker.io/bitnami/acmesolver:1.18.2-debian-12-r5
docker.io/bitnami/cainjector:1.18.2-debian-12-r5
docker.io/bitnami/cert-manager-webhook:1.18.2-debian-12-r5
docker.io/bitnami/cert-manager:1.18.2-debian-12-r5
docker.io/bitnami/contour:1.32.1-debian-12-r0
docker.io/bitnami/envoy:1.34.5-debian-12-r0
docker.io/bitnami/nginx:1.29.1-debian-12-r0
```

Do not broaden the active exception policy to every Bitnami image. Add only versions that are proven requirements of a current deployment package.

## Local/private-only utility images

The deployment also requires:

```text
kubeharbor.dev.kube/library/chrony-air-gapped:v0.1.4
kubeharbor.dev.kube/library/ultimate-k8s-toolbox:v1.0.1
```

These are tracked as required artifacts, but they are not treated as Internet-pull candidates because no authoritative public source is defined here. Before an air-gap release is declared complete, verify they are already in the staging cache/registry or export them from the build environment and import/push them into KubeHarbor.

## Validation

Run the self-contained validation before downloading artifacts:

```bash
python3 tools/validate_seg1opdev_inventory.py
```

The validator checks that:

1. every required upstream image exists in `source-lists/`;
2. every required image lands in generated `all-active-images.list`;
3. required Bitnami exceptions are active rather than archived;
4. both the specific and aggregate Helm inventories contain all 16 Segment1 OPDEV packages;
5. Longhorn is `1.12.1` and Rancher `2.15.0` remains represented through the package contract;
6. the two local/private-only utility images are explicitly tracked.

For a true cross-repository validation against a local checkout of the deployment repository:

```bash
python3 tools/validate_seg1opdev_inventory.py \
  --deployment-repo /path/to/k8mm-seg1opdev-multicluster
```

The cross-repository mode additionally compares the deployment's `helm/required-packages.txt`, `helm/gitlab-runner-source-images.txt`, and `helm/longhorn-images.txt` with this repository's v2.7 contract and verifies the local utility image references are still present.

## CI behavior

`.github/workflows/validate-seg1opdev-inventory.yml` runs the internal contract validation for relevant pull requests and pushes to `main`.

Because `k8mm-seg1opdev-multicluster` is private, GitHub's repository-scoped `GITHUB_TOKEN` cannot be assumed to read it. Configure a repository secret named `SEG1OPDEV_REPO_TOKEN` with read-only access to that repository to enable the optional cross-repository CI check. If the secret is absent, CI emits a notice and still enforces the static v2.7 contract.

The workflow defaults to the `multicluster-longhorn` deployment branch for cross-repository comparison; a different branch or tag can be selected with the manual workflow input.

## Release workflow

Before moving an artifact set into the air-gap:

```bash
python3 tools/validate_seg1opdev_inventory.py
./organize-image-lists.sh
./download-images.sh
./download-helm-charts.sh --list chart-lists/k8s-mystical-mesh-helm-packages.list
```

Then verify the local/private-only images are present in the staging registry/cache before transfer. This gives the release process a fail-fast contract instead of discovering missing images or charts after Fleet begins reconciliation.
