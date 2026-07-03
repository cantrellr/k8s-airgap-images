# Mesh Helm Latest Package Inventory

This note tracks the latest upstream chart package list for upgrade testing.

Package list: chart-lists/k8s-mystical-mesh-helm-packages-latest.list

Run:

```bash
./download-helm-charts.sh --list chart-lists/k8s-mystical-mesh-helm-packages-latest.list
```

Use this list for upgrade testing only. The mesh-pinned package list remains the safer deployment source until values files, images, CRDs, and upgrade notes are validated.

Rancher is kept at 2.14.2 because the mesh repo already references rancher-2.14.2.tgz, even though Rancher's GitHub latest release page currently resolves to v2.14.1.

Trident operator is kept at 100.2602.1 because that is the highest version referenced by the mesh repo. NetApp's current 26.02 docs show 100.2602.0, so verify the Helm repository before changing this package.

mongo-express remains manual until a reliable upstream chart source is confirmed.
