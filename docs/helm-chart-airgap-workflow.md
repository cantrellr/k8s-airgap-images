# Helm Chart Air-Gap Workflow

This repo now tracks two different artifact types:

1. Container images under `source-lists/` and generated `image-lists/`.
2. Helm chart packages under `chart-lists/` and downloaded `helm-packages/`.

The Helm chart workflow is intentionally separate from image pull/push. A Helm chart package is a `.tgz` file that can be copied directly into an air-gapped repo or staged under a companion deployment repository such as `k8s-mystical-mesh`.

## Chart list format

Chart lists live under `chart-lists/` and use pipe-delimited rows:

```text
repo_alias|repo_url|chart|version
```

Example:

```text
cnpg|https://cloudnative-pg.github.io/charts|cloudnative-pg|0.29.0
```

Blank lines and comments beginning with `#` are ignored.

## Download charts while connected

```bash
./download-helm-charts.sh --list chart-lists/cloudnativepg-postgres-ha-charts.list
```

Downloaded chart packages are placed under:

```text
helm-packages/
```

For CloudNativePG, the expected outputs are:

```text
helm-packages/cloudnative-pg-0.29.0.tgz
helm-packages/cluster-0.7.0.tgz
helm-packages/plugin-barman-cloud-0.7.0.tgz
```

## Create a transferable chart package

```bash
./create-chart-package.sh
```

The script creates a tarball under:

```text
bundles/
```

That tarball includes:

```text
chart-lists/
helm-packages/
```

## Recommended CloudNativePG image workflow

CloudNativePG images are tracked separately in:

```text
source-lists/cloudnativepg-postgres-ha-images.list
```

Run the normal image workflow after adding or updating image lists:

```bash
./organize-image-lists.sh
./download-images.sh --list image-lists/all-active-images.list
```

Then transfer the connected host image cache or push the cached images into the offline registry with:

```bash
./push-images.sh --target kubeharbor.dev.kube/library
```

## Offline deployment handoff

A complete offline handoff for this repo should include:

```text
image-lists/
source-lists/
chart-lists/
helm-packages/
logs/
```

The deployment repo can then reference chart packages locally, for example:

```text
helm/packages/cloudnative-pg-0.29.0.tgz
```

or consume them directly from this repo's `helm-packages/` directory if both repos are checked out on the same air-gapped workstation.
