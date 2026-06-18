#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
source_dir = repo / "diagrams" / "mermaid-source"
doc_path = repo / "docs" / "System-Design-Document.md"
index_md = repo / "diagrams" / "DIAGRAM-INDEX.md"
index_json = repo / "diagrams" / "DIAGRAM-INDEX.json"

sources = sorted(source_dir.glob("*.mmd"))
if not sources:
    raise SystemExit(f"No Mermaid sources found under {source_dir}")

titles = {
    "k8s-airgap-images-diagram-01": "System Context",
    "k8s-airgap-images-diagram-02": "Repository Architecture",
    "k8s-airgap-images-diagram-03": "Image List Processing",
    "k8s-airgap-images-diagram-04": "Pull Workflow",
    "k8s-airgap-images-diagram-05": "Push Workflow",
    "k8s-airgap-images-diagram-06": "kubeharbor Integration",
}

entries = []
for idx, src in enumerate(sources, start=1):
    stem = src.stem
    entries.append({
        "id": idx,
        "title": titles.get(stem, stem),
        "source": f"diagrams/mermaid-source/{src.name}",
        "svg": f"diagrams/svg/{stem}.svg",
        "png": f"diagrams/png/{stem}.png",
    })

md_lines = [
    "# Diagram Index",
    "",
    "This index tracks the Mermaid source diagrams used by `docs/System-Design-Document.md`.",
    "",
    "| ID | Title | Source | SVG | PNG |",
    "| --- | --- | --- | --- | --- |",
]
for entry in entries:
    source = Path(entry["source"]).name
    svg = Path(entry["svg"]).name
    png = Path(entry["png"]).name
    md_lines.append(
        f"| {entry['id']:02d} | {entry['title']} | "
        f"[MMD](mermaid-source/{source}) | [SVG](svg/{svg}) | [PNG](png/{png}) |"
    )

index_md.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
index_json.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")

if doc_path.exists():
    text = doc_path.read_text(encoding="utf-8")
    mermaid_count = len(re.findall(r"```mermaid", text))
    export_count = text.count("Diagram export:")
    if mermaid_count != len(entries):
        raise SystemExit(f"Expected {len(entries)} Mermaid blocks, found {mermaid_count}.")
    if export_count != len(entries):
        raise SystemExit(f"Expected {len(entries)} Diagram export lines, found {export_count}.")

print("Updated Markdown/index files:")
print(f"  - {index_md.relative_to(repo)}")
print(f"  - {index_json.relative_to(repo)}")
