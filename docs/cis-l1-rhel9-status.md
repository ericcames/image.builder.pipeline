# RHEL 9 CIS Level 1 — Compliance Status

Snapshot of the latest validated end-to-end pipeline run. Updated when a new
validation completes or the curated exempt list changes. Pipeline mechanics live
in [design.md](design.md); this document captures *where things are right now*.

## Latest validation

| Field | Value |
|---|---|
| Date | 2026-05-12 |
| AMI ID | `ami-0228edcda0bbb6c3a` |
| Region | `us-east-1` |
| Build profile | `xccdf_org.ssgproject.content_profile_cis_server_l1` |
| Pipeline commit | `1682602` |

## Headline numbers

- **Raw compliance score:** **98.07** (gate: 95)
- **Pass:** 254 | **Fail:** 5 | **N/A:** 33 | **Not-checked:** 0
- **Exempt entries in `data.json`:** 5 (1 auto-emitted, 5 curated)
- **Effective compliance** (passes + exempts / non-N/A): ~99.6%

Score formula: `pass / (pass + fail)`, excluding N/A and not-checked. Exempt rules
still count against the raw score; OPA does the effective-compliance math at
policy-evaluation time using `exempt_controls`.

## Currently failing rules (all 5 documented exempt)

| Control | XCCDF | Policy | One-line reason |
|---|---|---|---|
| `grub2_password` | high | P1 | Cloud VMs lack the console boot path the rule protects |
| `ensure_root_password_configured` | medium | P2 | AWS uses ec2-user + SSH key auth; root password isn't in the model |
| `file_permission_user_init_files` | medium | P2 | AMI build precedes user creation; rule applies to deployed instances |
| `partition_for_tmp` | low | P3 | EBS AMIs use a single cloud-init-expanded root partition |
| `sshd_limit_user_access` | unknown | P3 | SSH access policy is a consumer decision, not a base-OS decision |

Full canonical text and rationale lives in [`playbooks/vars/exempt_controls.yml`](../playbooks/vars/exempt_controls.yml)
and [design.md §5.2](design.md). Update both files together when the list changes.

## How to reproduce

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=...

ansible-playbook playbooks/build_cis_image.yml      # ~20 min — Image Builder compose
ansible-playbook playbooks/deploy_and_scan.yml      # ~5 min — EC2 deploy + scan
ansible-playbook playbooks/generate_policy_data.yml # seconds — emits data.json
```

Stage 3's debug output reports the score, pass/fail breakdown, and exempt count.
The full `data.json` is at `output/rhel9/data.json` (gitignored).

## Downstream consumption

| Consumer | What it reads | Integration point |
|---|---|---|
| [`rego_policy_libraries`](https://github.com/ynotbhatc/rego_policy_libraries) | `data.json` | `golden_images/os/linux/rhel_9/data.json` |
| [`sales.demos`](https://github.com/ericcames/sales.demos) | The AMI itself, via tag filter | Terraform `data.aws_ami` tag filter (pending Phase 1.5) |

See [design.md §6](design.md) and [§9](design.md) for the full consumer contracts.

## Validation history

| Date | Score | Pass/Fail | Notes |
|---|---|---|---|
| 2026-05-12 | **98.07** | 254/5 | Cat A packages added (#14); Cat B (#13) + Cat C (#15) exempts curated. All 13 original fails classified. |
| 2026-05-11 | 94.94 | 244/13 | Baseline first real end-to-end run. 10 medium + 1 high + 1 low + 1 unknown failing; only `partition_for_tmp` auto-exempted with placeholder reason. |

## Maintenance

Refresh this document when:

- A new end-to-end validation run completes (update Latest validation + add a History row)
- The curated exempt list changes (update Currently failing rules table)
- The Image Builder customizations change in a way that affects which rules pass

Validation cadence: rebuild and re-scan periodically to catch CIS benchmark
updates, RHEL base-image refreshes, and SSG remediation drift.
