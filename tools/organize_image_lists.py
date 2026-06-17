#!/usr/bin/env python3
from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path

source_dir = Path(os.environ.get("SOURCE_DIR", "source-lists")).resolve()
list_dir = Path(os.environ.get("LIST_DIR", "image-lists")).resolve()
list_dir.mkdir(parents=True, exist_ok=True)

files = sorted([p for p in source_dir.glob("*.list")] + [p for p in source_dir.glob("*.txt")])
if not files:
    raise SystemExit(f"No .list or .txt source files found under {source_dir}")

def has_registry(image: str) -> bool:
    first = image.split("/", 1)[0]
    return first == "localhost" or "." in first or ":" in first

def normalize(image: str) -> str:
    image = image.split("#", 1)[0].strip()
    if not image:
        return ""
    if not has_registry(image):
        return f"docker.io/{image}"
    return image

def is_bitnami(image: str) -> bool:
    return image.startswith("docker.io/bitnami/") or image.startswith("bitnami/")

def is_dhi(image: str) -> bool:
    return (
        image.startswith("dhi.io/")
        or image.startswith("docker.io/cantrellcloud/dhi-")
        or (image.startswith("docker.io/") and "/dhi-" in image)
    )

def is_ironbank(image: str) -> bool:
    return image.startswith("registry1.dso.mil/")

def is_nginx_private(image: str) -> bool:
    return image.startswith("docker-registry.nginx.com/")

all_source: set[str] = set()
public: set[str] = set()
dhi: set[str] = set()
ironbank: set[str] = set()
nginx: set[str] = set()
archived: set[str] = set()

for path in files:
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        image = normalize(raw)
        if not image:
            continue
        all_source.add(image)
        if is_bitnami(image):
            archived.add(image)
        elif is_dhi(image):
            dhi.add(image)
        elif is_ironbank(image):
            ironbank.add(image)
        elif is_nginx_private(image):
            nginx.add(image)
        else:
            public.add(image)

active = public | dhi | ironbank | nginx
outputs = {
    "00-public-images.list": public,
    "10-docker-hardened-images.list": dhi,
    "20-registry1-dso-mil-images.list": ironbank,
    "30-nginx-registry-images.list": nginx,
    "archived-images.list": archived,
    "all-active-images.list": active,
    "all-source-images.list": all_source,
}

for name, values in outputs.items():
    (list_dir / name).write_text("".join(f"{v}\n" for v in sorted(values)), encoding="utf-8")

counts = {
    "Generated": datetime.now(timezone.utc).astimezone().isoformat(),
    "Source directory": str(source_dir),
    "Total unique source images": len(all_source),
    "Active images, excluding archived Bitnami": len(active),
    "Public/no-auth list": len(public),
    "Docker Hardened Images/DHI list": len(dhi),
    "registry1.dso.mil/Iron Bank list": len(ironbank),
    "docker-registry.nginx.com list": len(nginx),
    "Archived Bitnami list": len(archived),
}
text = "\n".join(f"{k}: {v}" for k, v in counts.items()) + "\n"
(list_dir / "manifest-counts.txt").write_text(text, encoding="utf-8")
print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Organized image lists under {list_dir}")
for line in text.splitlines():
    print(f"  {line}")
