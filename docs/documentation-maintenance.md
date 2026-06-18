# Documentation Maintenance

This repository uses the same local-first documentation pattern as kubeharbor: Markdown is committed, Mermaid source is committed, and SVG/PNG exports are generated locally with Mermaid CLI.

GitHub Actions are not required.

## Source-of-truth rules

- Architecture diagrams are authored in `diagrams/mermaid-source/*.mmd`.
- Markdown embeds Mermaid diagrams directly for GitHub readability.
- Rendered SVG and PNG files are generated outputs under `diagrams/svg/` and `diagrams/png/`.
- Do not create hand-built placeholder SVG or PNG files.
- Do not run diagram rendering with `sudo`.

## Local render workflow

First-time setup:

```bash
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
```

Normal sync:

```bash
./diagrams/apply-diagram-updates.sh .
```

The local renderer installs Mermaid CLI under `.diagram-tools/` when requested. That folder is ignored by Git.

## Commit contract

When diagrams change, keep the following files in the same commit:

- `docs/System-Design-Document.md`
- `diagrams/mermaid-source/*.mmd`
- `diagrams/svg/*.svg`
- `diagrams/png/*.png`
- `diagrams/DIAGRAM-INDEX.md`
- `diagrams/DIAGRAM-INDEX.json`

If SVG/PNG exports are not regenerated, say so in the commit or do not commit the diagram-source change yet. Broken diagram links are documentation debt.

## Validation checklist

```bash
grep -c '```mermaid' docs/System-Design-Document.md
grep -c 'Diagram export:' docs/System-Design-Document.md
./diagrams/apply-diagram-updates.sh .
git status --short
```

The Mermaid block count and export line count should match the diagram index.
