# Golden Image Pipeline — Design Document

**Status:** Draft
**Maintainer:** ericcames
**Companion repo:** [rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries)
**Last updated:** 2026-04-22

---

## 1. Purpose

This pipeline automates the construction, scanning, and compliance reporting of
hardened machine images. It produces structured `data.json` files consumed by the
`golden_images/` policy module in `rego_policy_libraries`.

Unlike the `benchmarks/` policies in that repo — which assess the *running state*
of a live system — golden image policies assert the *provenance and build-time
compliance* of an image artifact. This pipeline generates the reference data those
policies evaluate against.

---

## 2. Problem Statement

Without automated image compliance data generation, teams must:

- Manually run builds and scans each time a new image is needed
- Hand-curate allowlists and denylist that drift from reality
- Rediscover platform-specific exceptions (e.g., AWS boot partition layout) on every new build
- Struggle to prove image provenance to auditors (FedRAMP, CMMC, PCI-DSS)

This pipeline closes that gap: a single playbook run produces an authoritative,
machine-readable compliance record.

---

## 3. Pipeline Stages

### Stage 1 — Build (`build_cis_image.yml`)

Calls the Red Hat Image Builder API to:
- Create an image blueprint with the target CIS OpenSCAP profile
- Trigger an AWS AMI compose
- Poll until the compose completes
- Record the resulting AMI ID

**Key API:** `https://console.redhat.com/api/image-builder/v1/`

**Authentication:** Red Hat offline token (`RH_OFFLINE_TOKEN` env var)

**Blueprint profile:** `xccdf_org.ssgproject.content_profile_cis_server_l1`

Image Builder runs OpenSCAP at build time and writes results to
`/root/openscap_data/` inside the image.

---

### Stage 2 — Deploy and Scan (`deploy_and_scan.yml`)

- Launches a temporary EC2 instance from the AMI produced in Stage 1
- SSHs in and pulls `/root/openscap_data/` results
- Optionally re-runs a fresh OpenSCAP scan to capture runtime state
- Terminates the instance and cleans up

**Authentication:** AWS credentials via standard env vars

---

### Stage 3 — Generate Policy Data (`generate_policy_data.yml`)

Parses the XCCDF/ARF results, merges scan-derived data with curated policy
inputs, and produces `output/<platform>/data.json`:

```json
{
  "approved_base_images": ["ami-0228edcda0bbb6c3a"],
  "approved_builders": ["imagebuilder", "packer", "ansible-aac"],
  "approved_signing_keys": [],
  "max_image_age_days": 90,
  "min_hardening_score": 95,
  "required_packages": ["aide", "audit", "firewalld", "openscap-scanner"],
  "denied_packages": ["telnet", "rsh", "xinetd"],
  "exempt_controls": [
    {
      "control_id": "xccdf_org.ssgproject.content_rule_grub2_password",
      "severity": "P1",
      "reason": "Cloud VMs do not expose the console boot path that a grub2 password protects ...",
      "applies_to": ["aws_ami"]
    }
  ]
}
```

- `approved_base_images` is populated from `output/<platform>/build_output.json`
  (the AMI ID minted by Stage 1).
- `exempt_controls` is a merge of two sources: curated entries from
  `playbooks/vars/exempt_controls.yml` (canonical reasons; see §5) plus any
  low-severity scan failures auto-emitted by the XCCDF parser. Curated entries
  win on duplicate `control_id` so canonical reasons replace auto-emitted
  placeholders.
- The remaining fields (`approved_builders`, thresholds, package lists) are
  static policy inputs defined in `playbooks/generate_policy_data.yml`.

---

## 4. Credential Model

All credentials are resolved at runtime via environment variables — never stored in the repo.

| Variable | Purpose |
|----------|---------|
| `RH_OFFLINE_TOKEN` | Red Hat API access (Image Builder) |
| `AWS_ACCESS_KEY_ID` | AWS authentication |
| `AWS_SECRET_ACCESS_KEY` | AWS authentication |
| `AWS_DEFAULT_REGION` | Target AWS region |

---

## 5. Exempt Controls Design

CIS rules that fail at scan time fall into two categories:

1. **Real hardening gaps** — packages missing, services not enabled, config not applied.
   Fixed in `build_cis_image.yml` blueprint customizations so the rule passes on rebuild.
2. **Structural mismatches with the deployment environment** — rules that can't apply
   on AWS regardless of how the image is built (no console boot recovery, no separate
   partitions, SSH-key-only auth model). Treated as exempt with documented reasons.

Category 2 entries live in `playbooks/vars/exempt_controls.yml`, keyed by platform, and
get merged into `data.json` under `exempt_controls` at policy-data generation time.
This list is managed in the pipeline repo rather than hardcoded in OPA policy — a data
file update is sufficient when exceptions change; no policy code review required.

The parser (`playbooks/filter_plugins/xccdf.py`) also auto-emits low-severity (XCCDF
`low` → policy P3) scan failures as exempt candidates. Curated entries take precedence
on duplicate `control_id` so the canonical reason is preserved.

### 5.1 Severity mapping

Policy severity maps from XCCDF severity:

| XCCDF severity | Policy severity | Notes |
|---|---|---|
| high | P1 | Highest gating impact |
| medium | P2 | |
| low | P3 | Auto-emitted as exempt by default |
| unknown / info | P3 | SSG didn't assign a severity — treated as lowest gating weight |

### 5.2 Canonical curated entries (RHEL 9, AWS)

| Control | XCCDF | Policy | Reason |
|---|---|---|---|
| `grub2_password` | high | P1 | Cloud VMs don't expose the console boot path that grub2 password protects. Baking a password into the AMI is ineffective (no console-recovery path on AWS) and a credential-leak risk (password stored in the image artifact). |
| `ensure_root_password_configured` | medium | P2 | RHEL on AWS uses `ec2-user` with SSH key authentication; root password is not part of the security model. Setting one provides no defense against an attacker who can already reach the instance and creates a credential leak risk in the AMI artifact. |
| `partition_for_tmp` | low | P3 | AWS EBS-backed AMIs use a single root partition that cloud-init expands at first boot. A separate `/tmp` partition is incompatible with that launch flow. |
| `file_permission_user_init_files` | medium | P2 | Rule applies to user home directories on a deployed system. At AMI build time no users exist yet — `ec2-user` is created by cloud-init at first boot, not in the image artifact. Hardening user init file permissions is a post-deploy responsibility. |
| `sshd_limit_user_access` | unknown | P3 | SSH access policy (`AllowUsers`/`AllowGroups`/etc.) is a consumer decision: the pipeline produces a base OS image and does not know which users or service accounts downstream setup will require SSH access. Baking `AllowUsers ec2-user` would risk locking out legitimate downstream users. |

Source: `playbooks/vars/exempt_controls.yml`. Update both files together when the list changes.

---

## 6. Integration with rego_policy_libraries

Generated `data.json` files map to:

```
rego_policy_libraries/
└── golden_images/
    └── os/
        └── linux/
            └── rhel_9/
                └── data.json    ← output of this pipeline
```

The OPA policies reference this data as:
```rego
input.image.source_image_id in data.golden_images.rhel9.approved_base_images
input.image.builder in data.golden_images.rhel9.approved_builders
```

---

## 7. OPA Policy Module Reference

The following modules in `rego_policy_libraries` consume the data this pipeline produces:

| Module | Data fields consumed |
|--------|---------------------|
| `image_provenance.rego` | `approved_base_images`, `approved_builders`, `max_image_age_days` |
| `hardening_baseline.rego` | `min_hardening_score`, `exempt_controls` |
| `package_policy.rego` | `required_packages`, `denied_packages` |
| `image_signing.rego` | `approved_signing_keys` |

---

## 8. Full Golden Image Policy Design

For the complete OPA policy design — module taxonomy, input schema, output contract,
severity tiers, and enforcement integration — see the policy design document maintained
by the `rego_policy_libraries` repo owner.

Key decisions made during planning (2026-04-22):

- **data.json over hardcoded values** — lists change independently of policy logic
- **Image Builder as primary build tool** — OpenSCAP runs at build time, results embedded in image
- **OpenSCAP profile ID normalization** — Image Builder uses full XCCDF IDs; policy must handle both short and full form
- **P1 gate logic in orchestrator only** — individual modules emit severity-tagged violations; `rhel9_golden_image_main.rego` decides ALLOW/DENY
- **Exempt controls enumerated by this pipeline** — not hardcoded in Rego
- **RHEL 9 before Windows** — establish patterns on the well-defined platform first

---

## 9. Integration with demo.datacenter (DC1)

A second consumer of this pipeline's output, distinct from `rego_policy_libraries`.
DC1 consumes the **AMIs themselves** — not `data.json` — as the boot image for its
Layer 1 Satellite host and Layer 3 RHEL workload nodes.

**Status:** Pipeline applies the tagging contract below as of Phase 1.5. DC1's
`variables.tf` swap to consume these tags is the remaining Phase 1.5 work.

### 9.1 Discovery mechanism — tag-based

DC1's Terraform discovers AMIs via `data "aws_ami"` with tag filters. Tag-based
discovery is more flexible than name-pattern matching: consumers can filter on
any combination of provenance / OS / level without coupling to a specific name
format.

```hcl
data "aws_ami" "rhel9_cis_l1" {
  owners      = ["463606842039"]
  most_recent = true

  filter {
    name   = "tag:Pipeline"
    values = ["image-builder-pipeline"]
  }
  filter {
    name   = "tag:OS"
    values = ["rhel9"]
  }
  filter {
    name   = "tag:CIS-Level"
    values = ["L1"]
  }
}
```

`owners = ["463606842039"]` reflects how Red Hat Image Builder actually
delivers AMIs: it is a **hosted service** that builds in Red Hat's own AWS
service account (`463606842039`) and shares the result with the consumer
account named in the API's `share_with_accounts` field. The consumer never
owns the AMI — only has launch permission for it — so `owners = ["self"]`
in the data source would not match. Consumers must filter on the Image
Builder service account ID instead.

`most_recent = true` picks the freshest matching build, which is also
reflected in the `BuildDate` tag for explicit age checks.

### 9.2 AMI tagging contract

The pipeline applies six tags to every AMI it produces. These are the versioned
cross-repo contract with DC1 and any other consumer:

| Tag | Value | Why |
|---|---|---|
| `Pipeline` | `image-builder-pipeline` | Provenance — filter to pipeline-built only |
| `OS` | `rhel9`, `rhel8`, `win2022` | Filter dimension |
| `CIS-Level` | `L1`, `L2` | Workload groups may select level |
| `BuildDate` | ISO 8601 timestamp (e.g. `2026-05-12T01:00:00Z`) | Age tracking |
| `ComposeID` | Image Builder compose UUID | Traceability back to pipeline logs |
| `Name` | `{os}-cis-l{level}-{YYYYMMDD-HHMM}` (e.g. `rhel9-cis-l1-20260512-0100`) | Human-readable label for AWS console / CLI listings |

The `Name` tag follows a stable pattern but is *not* a discovery key — it's
operator convenience. Discovery uses `Pipeline` + `OS` + `CIS-Level`.

### 9.3 Architecture: OS-only, not product-baked

Pipeline produces **OS-only** hardened AMIs. Product installs (Satellite, app
stacks) happen **on top** via DC1's existing setup playbooks
(e.g., `satellite_setup.yml`). Rationale:

- Satellite has post-install state (orgs, manifests, certs, content views) that doesn't AMI-ify cleanly
- Keeps the pipeline product-agnostic — one `rhel9-cis-l1` AMI serves Satellite host, workload nodes, and any future product
- DC1's existing setup playbooks need only the AMI filter swap to consume hardened AMIs

### 9.4 CIS Level selection per DC1 layer

- **Satellite host (Layer 1):** CIS L1 only. L2 firewall/service tightening fights Satellite's installer (requires ports 80, 443, 5647, 8000, 8140, 9090 open and several services running).
- **RHEL workload nodes (Layer 3):** L1 baseline; L2 available per workload group as L2 builds mature.
- **F5 / Palo Alto / Infoblox:** Out of scope — appliance AMIs come from AWS Marketplace, not this pipeline.
