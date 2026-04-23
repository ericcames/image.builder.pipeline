# image.builder.pipeline

Automation pipeline for building CIS-compliant images via Red Hat Image Builder,
scanning with OpenSCAP, and generating structured policy compliance data for
[rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries).

## Overview

This pipeline automates three stages:

1. **Build** — trigger a CIS-hardened image compose via the Red Hat Image Builder API
2. **Scan** — deploy the image to AWS and extract OpenSCAP results
3. **Generate** — parse SCAP results into `data.json` policy data files

The output feeds directly into the `golden_images/` policy module in `rego_policy_libraries`,
populating approved baseline values, exempt controls, and compliance thresholds.

## Architecture

```
Red Hat Image Builder (console.redhat.com)
        │
        ▼ AMI
   AWS EC2 (temp instance)
        │
        ▼ SCAP results (/root/openscap_data/)
   OpenSCAP Parser
        │
        ▼
   data.json → rego_policy_libraries/golden_images/
```

## Supported Platforms

| Platform | CIS Benchmark | Status |
|----------|--------------|--------|
| RHEL 9 | CIS Level 1 Server | Phase 1 — Active |
| RHEL 8 | CIS Level 1 Server | Phase 2 |
| RHEL 10 | CIS Level 1 Server | Phase 2 — pending benchmark |
| Windows Server 2022 | CIS Level 1 | Phase 3 |

See [ROADMAP.md](ROADMAP.md) for full platform schedule.

## Prerequisites

- Red Hat account with Image Builder access (console.redhat.com)
- Red Hat offline token in `~/.ansible/ansible.cfg` under `[galaxy_server.rh_certified]` as `token=`
  (same token used for Automation Hub — obtain from console.redhat.com → Automation Hub → Connect to Hub → API token)
- AWS credentials with EC2 permissions
- Ansible collections: `amazon.aws`, `ansible.builtin`

```bash
ansible-galaxy collection install amazon.aws -p ./collections
```

## Quick Start

```bash
cp -r inventories/sample/ inventories/<customer>-<platform>/

export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=<your_aws_account_id>

# Full pipeline
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/build_cis_image.yml
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/deploy_and_scan.yml
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/generate_policy_data.yml
```

## Output

Generated `data.json` files are written to `output/<platform>/data.json` and
should be copied into the appropriate `golden_images/` path in `rego_policy_libraries`.

## Related Projects

- [rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries) — OPA policy library this pipeline feeds
- [aap.as.code](https://github.com/ericcames/aap.as.code) — AAP bootstrap and demo platform

## License

MIT — see [LICENSE](LICENSE)
