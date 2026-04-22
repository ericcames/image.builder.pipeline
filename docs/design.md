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

Parses the XCCDF/ARF results and produces:

```json
{
  "approved_base_images": [],
  "approved_builders": ["imagebuilder", "packer", "ansible-aac"],
  "approved_signing_keys": [],
  "max_image_age_days": 90,
  "min_hardening_score": 95,
  "required_packages": ["aide", "audit", "firewalld", "openscap-scanner"],
  "denied_packages": ["telnet", "rsh", "xinetd"],
  "exempt_controls": [
    {
      "control_id": "<populated from scan>",
      "severity": "P3",
      "reason": "<populated from scan — AWS-specific exception>",
      "applies_to": ["aws_ami"]
    }
  ]
}
```

Output is written to `output/<platform>/data.json`.

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

AWS-specific exceptions (known Image Builder P3 failures) are enumerated by running
the pipeline once per platform and recording the failing control IDs. These are stored
in `data.json` under `exempt_controls` with documented reasons.

This list is managed here rather than hardcoded in OPA policy — a data file update
is sufficient when exceptions change, no policy code review required.

**Initial enumeration:** run Phase 1 pipeline, capture XCCDF results, identify
failing controls that are AWS-deployment-specific (not hardening failures).

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
