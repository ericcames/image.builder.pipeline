# image.builder.pipeline

Automation pipeline for building CIS-compliant images via Red Hat Image Builder,
scanning with OpenSCAP, and generating structured policy compliance data for
[rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries).

## Overview

This pipeline automates three stages:

1. **Build** — trigger a CIS-hardened image compose via the Red Hat Image Builder API (AMI or qcow2)
2. **Scan** — deploy the image to AWS and extract OpenSCAP results (AMI path)
3. **Generate** — parse SCAP results into `data.json` policy data files
4. **containerDisk** — wrap qcow2 as a containerDisk and push to Quay.io for OpenShift Virtualization

The output feeds directly into the `golden_images/` policy module in `rego_policy_libraries`,
populating approved baseline values, exempt controls, and compliance thresholds.

## Architecture

```
Red Hat Image Builder (console.redhat.com)
        │
        ├──────────────────────────┐
        ▼ AMI                     ▼ qcow2
   AWS EC2 (temp instance)   containerDisk wrap
        │                         │
        ▼ SCAP results            ▼ podman push
   OpenSCAP Parser           Quay.io (private)
        │                         │
        ▼                         ▼
   data.json → rego_policy    DataImportCron →
   _libraries/golden_images/  OpenShift Virt VMs
```

## Supported Platforms

| Platform | Output | CIS Benchmark | Status |
|----------|--------|--------------|--------|
| RHEL 9 | AMI | CIS Level 1 Server | **Phase 1 — Complete** (score 98.07 / 95 gate — see [status](docs/cis-l1-rhel9-status.md)) |
| RHEL 9 | containerDisk | CIS Level 1 Server | **Phase 1.7 — Complete** |
| RHEL 8 | AMI | CIS Level 1 Server | Phase 2 |
| RHEL 10 | AMI | CIS Level 1 Server | Phase 2 — pending benchmark |
| Windows Server 2022 | containerDisk | CIS Level 1 | Phase 3 |

See [ROADMAP.md](ROADMAP.md) for full platform schedule and
[docs/cis-l1-rhel9-status.md](docs/cis-l1-rhel9-status.md) for the
latest RHEL 9 compliance snapshot.

## Claude skills

Workflows in this repo are packaged as skills under `.claude/skills/`.

| Skill | Does |
|---|---|
| `first-time` | Validates every local prerequisite on a new machine |
| `collections-sync` | Pins, installs and verifies the Ansible collections |
| `dev-workflow` | The mandatory issue → branch → PR → merge cycle |
| `rhel9-containerdisk` | Builds the RHEL 9 CIS L1 containerDisk (Phase 1.7) |
| `windows-image-build` | Builds the Windows Server 2022 containerDisk (Phase 3) |

## Prerequisites

- Red Hat account with Image Builder access (console.redhat.com)
- Red Hat offline token in `~/.ansible.cfg` under `[galaxy_server.rh_certified]` as `token=`
  (same token used for Automation Hub — obtain from console.redhat.com → Automation Hub → Connect to Hub → API token)
- AWS credentials with EC2 permissions
- Ansible collections (installed via requirements.yml)

```bash
ansible-galaxy collection install -r collections/requirements.yml -p ./collections
```

## Quick Start

### AMI pipeline (AWS)

```bash
cp -r inventories/sample/ inventories/<customer>-<platform>/

export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=<your_aws_account_id>

ansible-playbook -i inventories/<customer>-<platform>/ playbooks/build_cis_image.yml
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/deploy_and_scan.yml
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/generate_policy_data.yml
```

### containerDisk pipeline (OpenShift Virt)

```bash
podman login quay.io                  # one-time setup
# QUAY_REPO defaults to quay.io/zigfreed/rhel9-cis-l1-golden
ansible-playbook playbooks/build_cis_containerdisk.yml
```

## Output

Generated `data.json` files are written to `output/<platform>/data.json` and
should be copied into the appropriate `golden_images/` path in `rego_policy_libraries`.

## Related Projects

- [rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries) — OPA policy library this pipeline feeds
- [sales.demos](https://github.com/ericcames/sales.demos) — Demo platform; AMI and containerDisk consumer

## License

MIT — see [LICENSE](LICENSE)
