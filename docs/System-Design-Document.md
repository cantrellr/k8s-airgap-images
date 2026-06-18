# k8s-airgap-images System Design Document

**Version:** 1.0  
**Date:** June 18, 2026

## Executive Summary

`k8s-airgap-images` is a standalone utility repository for acquiring and promoting Kubernetes platform container images into disconnected environments. It owns the image catalog, source-list normalization, registry-aware pull workflow, deterministic retagging, Harbor project preflight, push workflow, and operational logs.

The repository pairs with `cantrellr/kubeharbor`, but it is intentionally separate. kubeharbor owns the Harbor VM and registry runtime. `k8s-airgap-images` owns the image catalog and transfer workflow.

## System Context

```mermaid
flowchart TB
    subgraph cluster_1_Internet["Internet-Connected Acquisition Side"]
        UpstreamDocker["Docker Hub"]
        UpstreamIronBank["registry1.dso.mil"]
        UpstreamDHI["dhi.io"]
        UpstreamOther["Other Registries"]
        AirgapRepo["k8s-airgap-images"]
    end

    subgraph cluster_2_WorkHost["Acquisition Host or kubeharbor VM"]
        GeneratedLists["Generated image-lists/"]
        DockerCache["Local Docker or Podman Cache"]
        Logs["logs/"]
    end

    subgraph cluster_3_AirGap["Air-Gapped Promotion Side"]
        Harbor["Harbor Registry"]
        K8sConsumers["Kubernetes Consumers"]
    end

    UpstreamDocker --> AirgapRepo
    UpstreamIronBank --> AirgapRepo
    UpstreamDHI --> AirgapRepo
    UpstreamOther --> AirgapRepo
    AirgapRepo --> GeneratedLists
    GeneratedLists --> DockerCache
    DockerCache --> Harbor
    Logs --> Harbor
    Harbor --> K8sConsumers

    style AirgapRepo fill:#e3f2fd
    style DockerCache fill:#fff3e0
    style Harbor fill:#e8f5e9
```

Diagram export: [SVG](../diagrams/svg/k8s-airgap-images-diagram-01.svg) | [PNG](../diagrams/png/k8s-airgap-images-diagram-01.png)

## Repository Architecture

```mermaid
flowchart TB
    subgraph cluster_1_Source["Governed Input"]
        SourceLists["source-lists/*.list and *.txt"]
    end

    subgraph cluster_2_Core["Core Utility"]
        MainCLI["image-airgap.sh"]
        Organizer["tools/organize_image_lists.py"]
        OrgWrapper["organize-image-lists.sh"]
        PullWrapper["download-images.sh"]
        PushWrapper["push-images.sh"]
    end

    subgraph cluster_3_Output["Generated Runtime State"]
        ImageLists["image-lists/*.list"]
        Manifest["manifest-counts.txt"]
        Logs["logs/*.list and *.tsv"]
    end

    SourceLists --> Organizer
    OrgWrapper --> MainCLI
    PullWrapper --> MainCLI
    PushWrapper --> MainCLI
    MainCLI --> Organizer
    Organizer --> ImageLists
    Organizer --> Manifest
    MainCLI --> Logs

    style SourceLists fill:#e3f2fd
    style MainCLI fill:#e8f5e9
    style Logs fill:#fff3e0
```

Diagram export: [SVG](../diagrams/svg/k8s-airgap-images-diagram-02.svg) | [PNG](../diagrams/png/k8s-airgap-images-diagram-02.png)

## Image List Processing

The organizer reads source lists, strips comments and blank lines, normalizes Docker Hub references, categorizes images by registry family, archives Bitnami images, and writes generated lists under `image-lists/`.

```mermaid
flowchart TB
    Raw["Raw source line"] --> Trim["Trim and remove comments"]
    Trim --> Empty{"Empty?"}
    Empty -- Yes --> Drop["Skip"]
    Empty -- No --> Registry{"Registry specified?"}
    Registry -- No --> AddDocker["Prefix docker.io/"]
    Registry -- Yes --> Keep["Keep explicit registry"]
    AddDocker --> Classify["Classify image"]
    Keep --> Classify
    Classify --> Bitnami{"Bitnami?"}
    Bitnami -- Yes --> Archived["archived-images.list"]
    Bitnami -- No --> DHI{"DHI?"}
    DHI -- Yes --> DHIList["10-docker-hardened-images.list"]
    DHI -- No --> IronBank{"registry1.dso.mil?"}
    IronBank -- Yes --> IronBankList["20-registry1-dso-mil-images.list"]
    IronBank -- No --> Nginx{"docker-registry.nginx.com?"}
    Nginx -- Yes --> NginxList["30-nginx-registry-images.list"]
    Nginx -- No --> PublicList["00-public-images.list"]
    DHIList --> Active["all-active-images.list"]
    IronBankList --> Active
    NginxList --> Active
    PublicList --> Active

    style Archived fill:#ffebee
    style Active fill:#e8f5e9
    style Classify fill:#fff3e0
```

Diagram export: [SVG](../diagrams/svg/k8s-airgap-images-diagram-03.svg) | [PNG](../diagrams/png/k8s-airgap-images-diagram-03.png)

## Pull Workflow

The pull workflow runs on an Internet-connected host. It organizes lists, opens registry credential gates, pulls active images, retries failures, and writes pull evidence under `logs/`.

```mermaid
flowchart TB
    Start["download-images.sh"] --> Organize["organize image lists"]
    Organize --> CLI["image-airgap.sh pull"]
    CLI --> DockerLogin["docker.io prompt"]
    DockerLogin --> IronBankLogin["registry1.dso.mil prompt"]
    IronBankLogin --> OptionalDHI["dhi.io prompt if needed"]
    OptionalDHI --> OptionalNginx["NGINX prompt if needed"]
    OptionalNginx --> PullLoop["Pull each active image"]
    PullLoop --> Exists{"Image already local?"}
    Exists -- Yes --> SuccessLog["pull-success.list"]
    Exists -- No --> Retry["Pull with retries"]
    Retry --> Pulled{"Pull succeeded?"}
    Pulled -- Yes --> SuccessLog
    Pulled -- No --> FailedLog["pull-failed timestamp list"]

    style PullLoop fill:#e3f2fd
    style SuccessLog fill:#e8f5e9
    style FailedLog fill:#ffebee
```

Diagram export: [SVG](../diagrams/svg/k8s-airgap-images-diagram-04.svg) | [PNG](../diagrams/png/k8s-airgap-images-diagram-04.png)

## Push Workflow

The push workflow runs after images are present in the local cache. It resolves the target prefix, authenticates to the target registry, optionally reconciles Harbor projects, retags each image, pushes the target reference, and logs source-to-target mappings.

```mermaid
flowchart TB
    Start["push-images.sh"] --> Organize["ensure generated lists exist"]
    Organize --> Target["Resolve target prefix"]
    Target --> Login["Login to target registry"]
    Login --> ProjectCheck{"Ensure projects?"}
    ProjectCheck -- Yes --> Reconcile["Harbor API project preflight"]
    ProjectCheck -- No --> PushLoop["Push loop"]
    Reconcile --> PushLoop
    PushLoop --> LocalImage{"Source image local?"}
    LocalImage -- No --> Missing["missing-local log"]
    LocalImage -- Yes --> Retag["Retag source to target"]
    Retag --> Push["Push target image"]
    Push --> PushOK{"Push succeeded?"}
    PushOK -- Yes --> Success["push-success.list"]
    PushOK -- No --> Failed["push-failed timestamp list"]
    Retag --> Map["push-image-map TSV"]

    style Reconcile fill:#fff3e0
    style Success fill:#e8f5e9
    style Missing fill:#ffebee
    style Failed fill:#ffebee
```

Diagram export: [SVG](../diagrams/svg/k8s-airgap-images-diagram-05.svg) | [PNG](../diagrams/png/k8s-airgap-images-diagram-05.png)

## kubeharbor Integration

When paired with kubeharbor, this repository is staged under `/data/k8s-airgap-images`. kubeharbor wrapper scripts call the staged CLI and keep large image operations tied to the data disk.

```mermaid
flowchart TB
    subgraph cluster_1_Kubeharbor["kubeharbor Repo"]
        StageScript["install-k8s-airgap-images.sh"]
        PullWrapper["pull-images-to-data-cache.sh"]
        PushWrapper["push-data-cache-to-harbor.sh"]
        DockerRoot["DockerRootDir under /data"]
    end

    subgraph cluster_2_K8sAirgap["k8s-airgap-images staged repo"]
        StagedRepo["/data/k8s-airgap-images"]
        CLI["image-airgap.sh"]
        Lists["image-lists/"]
        Logs["logs/"]
    end

    subgraph cluster_3_Registry["Harbor"]
        Harbor["kubeharbor.dev.kube/library"]
    end

    StageScript --> StagedRepo
    PullWrapper --> CLI
    PushWrapper --> CLI
    CLI --> Lists
    CLI --> Logs
    CLI --> DockerRoot
    DockerRoot --> Harbor
    CLI --> Harbor

    style StagedRepo fill:#e3f2fd
    style DockerRoot fill:#fff3e0
    style Harbor fill:#e8f5e9
```

Diagram export: [SVG](../diagrams/svg/k8s-airgap-images-diagram-06.svg) | [PNG](../diagrams/png/k8s-airgap-images-diagram-06.png)

## Security and Credential Handling

The utility prompts separately for upstream registry access during pull. For push, it can reuse target registry credentials for Harbor project preflight unless separate Harbor API credentials are supplied.

Hard rules:

- Do not commit registry credentials.
- Do not commit generated logs that contain sensitive operational details.
- Configure Docker or Podman trust before pushing to private registry endpoints.
- Use project-management credentials for Harbor project creation and scoped robot accounts for steady-state automation.
- Use insecure Harbor API mode only for lab or temporary troubleshooting.

## Operations Model

Day-0 work is source-list review and organization. Day-1 work is image pull and push execution. Day-2 work is catalog maintenance, credential hygiene, failure-log review, and periodic validation against downstream platform bundles.

## Failure Modes and Recovery

| Failure mode | Likely cause | Recovery |
| --- | --- | --- |
| No source files found | `source-lists/` empty or wrong `SOURCE_DIR` | Add source lists or set `SOURCE_DIR`. |
| Pull denied | Missing or expired upstream registry access | Re-run pull and authenticate to the relevant registry. |
| Pull failures | Missing image, rate limit, registry outage, or bad tag | Review `pull-failed` logs, correct source lists, rerun. |
| OS disk pressure | Container runtime storage not backed by `/data` | Fix runtime storage before pulling large sets. |
| Push missing local image | Image was not pulled or cache was pruned | Pull the missing image before pushing. |
| Project creation denied | Harbor account lacks project-management rights | Use an account with required Harbor permissions or precreate projects. |
| TLS unknown authority | Internal CA not trusted | Install CA trust for Docker or Podman. |

## Roadmap

1. Add optional SBOM and provenance generation for approved image-list releases.
2. Add schema validation for source-list metadata.
3. Add dry-run reports for target Harbor projects and image counts.
4. Add optional registry namespace collision checks.
