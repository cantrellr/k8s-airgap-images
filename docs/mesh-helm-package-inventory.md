# Mesh Helm Package Inventory

This inventory captures Helm packages referenced by the mesh install scripts.

Package list: chart-lists/k8s-mystical-mesh-helm-packages.list

Run: ./download-helm-charts.sh --list chart-lists/k8s-mystical-mesh-helm-packages.list

Packages are staged under helm-packages/.

The inventory includes Contour, cert-manager, MetalLB, Trident, Trident Protect, kube-prometheus-stack, Argo CD, NATS, Rancher, Rocket.Chat, MongoDB Kubernetes Operator, Portainer, and Longhorn.

mongo-express-6.5.2.tgz is referenced by the mesh repo, but no matching untarred chart metadata or reliable upstream chart source was identified during repo inventory. Keep that package staged manually until its upstream chart source is confirmed.

The Helm downloader supports normal HTTP/S chart repositories and OCI chart repositories.
