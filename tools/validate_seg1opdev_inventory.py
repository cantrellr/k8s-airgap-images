#!/usr/bin/env python3
"""Validate the k8mm-seg1opdev-multicluster v2.7 air-gap contract.

The default check is self-contained and CI-safe.  An optional local checkout of
k8mm-seg1opdev-multicluster can be supplied to perform a true cross-repository
comparison against its packaged Helm/image manifests.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "source-lists"
CONTRACT_DIR = ROOT / "contracts"
CHART_LISTS = (
    ROOT / "chart-lists" / "k8s-mystical-mesh-helm-packages.list",
    ROOT / "chart-lists" / ".all-charts.generated.list",
)


def clean_lines(path: Path) -> set[str]:
    values: set[str] = set()
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        value = raw.split("#", 1)[0].strip()
        if value:
            values.add(value)
    return values


def has_registry(image: str) -> bool:
    first = image.split("/", 1)[0]
    return first == "localhost" or "." in first or ":" in first


def normalize_image(image: str) -> str:
    image = image.strip()
    return image if has_registry(image) else f"docker.io/{image}"


def load_all_source_images() -> set[str]:
    values: set[str] = set()
    files = sorted(SOURCE_DIR.glob("*.list")) + sorted(SOURCE_DIR.glob("*.txt"))
    for path in files:
        for image in clean_lines(path):
            values.add(normalize_image(image))
    return values


def chart_packages(path: Path) -> set[str]:
    packages: set[str] = set()
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        raw = raw.split("#", 1)[0].strip()
        if not raw:
            continue
        parts = raw.split("|")
        if len(parts) != 4:
            raise ValueError(f"Malformed chart inventory line in {path}: {raw}")
        _alias, _repo, chart, version = parts
        packages.add(f"{chart}-{version}.tgz")
    return packages


def show_diff(label: str, expected: set[str], actual: set[str]) -> int:
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if not missing and not extra:
        print(f"[PASS] {label}")
        return 0
    print(f"[FAIL] {label}")
    for value in missing:
        print(f"       missing: {value}")
    for value in extra:
        print(f"       extra:   {value}")
    return 1


def validate_self() -> int:
    failures = 0
    required_images = {normalize_image(v) for v in clean_lines(CONTRACT_DIR / "seg1opdev-v2.7-required-source-images.list")}
    required_charts = clean_lines(CONTRACT_DIR / "seg1opdev-v2.7-required-charts.list")
    local_images = clean_lines(CONTRACT_DIR / "seg1opdev-v2.7-local-images.list")

    source_images = load_all_source_images()
    missing_sources = sorted(required_images - source_images)
    if missing_sources:
        failures += 1
        print("[FAIL] Required Segment1 OPDEV source images are missing from source-lists:")
        for image in missing_sources:
            print(f"       {image}")
    else:
        print(f"[PASS] All {len(required_images)} pullable Segment1 OPDEV source images are inventoried.")

    with tempfile.TemporaryDirectory(prefix="k8s-airgap-inventory-") as tmp:
        env = os.environ.copy()
        env["SOURCE_DIR"] = str(SOURCE_DIR)
        env["LIST_DIR"] = tmp
        proc = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "organize_image_lists.py")],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            failures += 1
            print("[FAIL] Image list organizer failed:")
            print(proc.stdout)
            print(proc.stderr)
        else:
            active = clean_lines(Path(tmp) / "all-active-images.list")
            archived = clean_lines(Path(tmp) / "archived-images.list")
            active_bitnami = clean_lines(Path(tmp) / "active-bitnami-images.list")
            missing_active = sorted(required_images - active)
            incorrectly_archived = sorted(required_images & archived)
            if missing_active:
                failures += 1
                print("[FAIL] Required Segment1 OPDEV images are not in all-active-images.list:")
                for image in missing_active:
                    print(f"       {image}")
            else:
                print(f"[PASS] All {len(required_images)} required pullable images are active pull candidates.")
            if incorrectly_archived:
                failures += 1
                print("[FAIL] Required Segment1 OPDEV images are still archived:")
                for image in incorrectly_archived:
                    print(f"       {image}")
            else:
                print("[PASS] No required Segment1 OPDEV image is archived.")
            expected_bitnami = {i for i in required_images if i.startswith("docker.io/bitnami/")}
            if expected_bitnami != active_bitnami:
                failures += show_diff("Active Bitnami exception set", expected_bitnami, active_bitnami)
            else:
                print(f"[PASS] Active Bitnami exception set contains {len(active_bitnami)} images.")

    for chart_list in CHART_LISTS:
        packages = chart_packages(chart_list)
        missing = sorted(required_charts - packages)
        if missing:
            failures += 1
            print(f"[FAIL] {chart_list.relative_to(ROOT)} is missing required packages:")
            for package in missing:
                print(f"       {package}")
        else:
            print(f"[PASS] {chart_list.relative_to(ROOT)} contains all {len(required_charts)} required Helm packages.")

    expected_local = {
        "kubeharbor.dev.kube/library/chrony-air-gapped:v0.1.4",
        "kubeharbor.dev.kube/library/ultimate-k8s-toolbox:v1.0.1",
    }
    failures += show_diff("Local/private-only image contract", expected_local, local_images)

    if failures:
        print(f"[FAIL] Segment1 OPDEV v2.7 inventory validation failed with {failures} issue(s).")
        return 1
    print("[PASS] Segment1 OPDEV v2.7 air-gap inventory contract is internally consistent.")
    return 0


def deployment_text(root: Path) -> str:
    chunks: list[str] = []
    allowed = {".yaml", ".yml", ".sh", ".txt", ".md", ".env"}
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in allowed:
            try:
                chunks.append(path.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                pass
    return "\n".join(chunks)


def validate_deployment_repo(deployment_repo: Path) -> int:
    failures = 0
    deployment_repo = deployment_repo.resolve()
    required_charts = clean_lines(CONTRACT_DIR / "seg1opdev-v2.7-required-charts.list")
    required_images = {normalize_image(v) for v in clean_lines(CONTRACT_DIR / "seg1opdev-v2.7-required-source-images.list")}
    local_images = clean_lines(CONTRACT_DIR / "seg1opdev-v2.7-local-images.list")

    package_file = deployment_repo / "helm" / "required-packages.txt"
    if not package_file.is_file():
        print(f"[FAIL] Deployment repo is missing {package_file}")
        return 1
    failures += show_diff("Cross-repo Helm package contract", required_charts, clean_lines(package_file))

    runner_file = deployment_repo / "helm" / "gitlab-runner-source-images.txt"
    if runner_file.is_file():
        runner_images = {normalize_image(v) for v in clean_lines(runner_file)}
        missing = sorted(runner_images - required_images)
        if missing:
            failures += 1
            print("[FAIL] Deployment GitLab Runner images are absent from the air-gap contract:")
            for image in missing:
                print(f"       {image}")
        else:
            print("[PASS] Deployment GitLab Runner image contract matches the air-gap inventory.")
    else:
        failures += 1
        print(f"[FAIL] Deployment repo is missing {runner_file}")

    longhorn_file = deployment_repo / "helm" / "longhorn-images.txt"
    if longhorn_file.is_file():
        longhorn_images = {normalize_image(v) for v in clean_lines(longhorn_file)}
        missing = sorted(longhorn_images - required_images)
        if missing:
            failures += 1
            print("[FAIL] Deployment Longhorn images are absent from the air-gap contract:")
            for image in missing:
                print(f"       {image}")
        else:
            print("[PASS] Deployment Longhorn image contract matches the air-gap inventory.")
    else:
        failures += 1
        print(f"[FAIL] Deployment repo is missing {longhorn_file}")

    text = deployment_text(deployment_repo)
    missing_local_refs = sorted(image for image in local_images if image not in text)
    if missing_local_refs:
        failures += 1
        print("[FAIL] Local/private image contract contains entries not referenced by the deployment repo:")
        for image in missing_local_refs:
            print(f"       {image}")
    else:
        print("[PASS] Deployment repo references all local/private Segment1 OPDEV utility images.")

    if failures:
        print(f"[FAIL] Cross-repository validation failed with {failures} issue(s).")
        return 1
    print("[PASS] k8s-airgap-images is aligned with the supplied k8mm-seg1opdev-multicluster checkout.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--deployment-repo",
        type=Path,
        help="Optional local checkout of cantrellr/k8mm-seg1opdev-multicluster for cross-repo comparison.",
    )
    args = parser.parse_args()

    rc = validate_self()
    if rc != 0:
        return rc
    if args.deployment_repo:
        return validate_deployment_repo(args.deployment_repo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
