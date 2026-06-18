# k8s-airgap-images documentation

This folder contains operator and architecture documentation for the `k8s-airgap-images` image acquisition and promotion utility.

## Documentation index

| Document | Purpose |
| --- | --- |
| [System Design Document](System-Design-Document.md) | System architecture, workflow model, registry boundary, security posture, operations, failure modes, and Mermaid diagrams. |
| [Operator Runbook](operator-runbook.md) | Step-by-step commands for organizing image lists, pulling images, pushing images, reviewing logs, and troubleshooting. |
| [Documentation Maintenance](documentation-maintenance.md) | Rules for maintaining Markdown, Mermaid source files, rendered exports, and diagram index metadata. |
| [Diagram Workflow](../diagrams/README.md) | Local Mermaid rendering workflow for SVG/PNG exports. |

## First-read workflow

For a new operator, read these in order:

1. [System Design Document](System-Design-Document.md) to understand the architecture and boundaries.
2. [Operator Runbook](operator-runbook.md) before pulling or pushing a large image set.
3. [Documentation Maintenance](documentation-maintenance.md) before changing docs or diagrams.

## Source-of-truth model

`source-lists/` contains governed input. `image-lists/` contains generated output. Do not hand-edit generated files and then treat the result as durable design intent. Update the source list and rerun the organizer.

## Primary commands

```bash
./organize-image-lists.sh
./download-images.sh
./push-images.sh --target kubeharbor.dev.kube/library
```

## Diagram commands

```bash
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
./diagrams/apply-diagram-updates.sh .
```

GitHub Actions are not required for diagram rendering.
