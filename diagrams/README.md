# Diagram workflow

This folder follows the local-first diagram pattern used by kubeharbor and k8s-mystical-mesh-documents.

## Folder contract

| Path | Purpose |
| --- | --- |
| `mermaid-source/*.mmd` | Source of truth for Mermaid diagrams. |
| `svg/*.svg` | Generated SVG exports. |
| `png/*.png` | Generated PNG exports. |
| `DIAGRAM-INDEX.md` | Human-readable diagram inventory. |
| `DIAGRAM-INDEX.json` | Machine-readable diagram inventory. |
| `render-mermaid-assets.sh` | Local Mermaid CLI renderer. |
| `apply-diagram-updates.sh` | Wrapper that renders and syncs diagram metadata. |

## First-time setup

```bash
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
```

## Normal sync

```bash
./diagrams/apply-diagram-updates.sh .
```

## Rules

- Do not run the renderer with `sudo`.
- Do not hand-create placeholder SVG or PNG files.
- Commit Mermaid source, Markdown, index files, and rendered exports together.
- GitHub Actions are not required.
