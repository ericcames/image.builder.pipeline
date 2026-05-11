# Roadmap

## Goal

Automate the full lifecycle of building, scanning, and validating CIS-compliant
machine images — producing structured policy data for OPA enforcement in
[rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries),
and serving as the source of hardened AMIs for
[demo.datacenter](https://github.com/ericcames/demo.datacenter) (DC1).

---

## Phase 1 — RHEL 9 CIS L1 (Active)

**Target:** End-to-end build → scan → `data.json` for RHEL 9 CIS Level 1 Server.

| Task | Status |
|------|--------|
| Image Builder API integration — blueprint, compose, AMI capture | Complete |
| AWS EC2 deploy and SCAP result extraction | Complete |
| Fresh OpenSCAP scan fallback when build-time results unavailable | Complete |
| `collections/requirements.yml` and pinned `amazon.aws` | Complete |
| OpenSCAP XCCDF result parser | **Pending** |
| `data.json` generator for `golden_images/os/linux/rhel_9/` | **Pending** |
| Enumerate and document AWS-specific exempt controls (P3) | Pending |
| End-to-end smoke test: build → scan → generate → OPA consumes | Pending |

---

## Phase 1.5 — demo.datacenter (DC1) integration

**Target:** DC1's Terraform consumes pipeline-built AMIs instead of stock Red Hat
marketplace AMIs. See `docs/design.md` §9 for the contract.

| Task | Status |
|------|--------|
| Implement AMI naming + tagging in `build_cis_image.yml` per design.md §9 | Pending |
| Update DC1 `roles/infrastructure/files/variables.tf` — `rhel9_ami_name` filter to `rhel9-cis-l1-*` | Pending |
| Update DC1 `data.tf.j2` — owner from Red Hat account to `self` | Pending |
| Smoke test: `satellite_setup.yml` installs cleanly on `rhel9-cis-l1` base | Pending |
| Document any CIS-L1-vs-Satellite exempt controls discovered | Pending |
| Roll AMI consumption to all RHEL 9 DC1 nodes | Pending |

---

## Phase 2 — CIS L2 and RHEL family expansion

**Target:** CIS Level 2 Server option for workloads; RHEL 8 mirrored.

| Task | Status |
|------|--------|
| CIS L2 Server blueprint for RHEL 9 (`rhel9-cis-l2-*` AMI lineage) | Pending |
| Separate `data.json` per level — `rhel_9_l1/` and `rhel_9_l2/` | Pending |
| RHEL 8 CIS Level 1 pipeline (mirrors Phase 1) | Pending |
| RHEL 10 pipeline — pending CIS RHEL 10 benchmark publication | Blocked |

Satellite host OS stays L1. L2 is workload-node-only until L2-on-Satellite is proven.

---

## Phase 3 — Windows Server 2022

**Target:** CIS Level 1, Windows Server 2022.

Windows image manifest format differs from Linux. Requires:
- Separate input schema extension in `rego_policy_libraries`
- Windows-specific SCAP/OVAL tooling (not OpenSCAP)
- Possible use of EC2 Image Builder (AWS) rather than Red Hat Image Builder

| Task | Status |
|------|--------|
| Windows image pipeline design | Pending |
| CIS/STIG benchmark selection | Pending |
| SCAP/OVAL result parser for Windows | Pending |
| `data.json` generator for `golden_images/os/windows/server_2022/` | Pending |

---

## Phase 4 — Additional Platforms

Platforms from `rego_policy_libraries` design doc, prioritized by demand:

| Platform | Priority | Notes |
|----------|----------|-------|
| Ubuntu 22.04 / 24.04 | High | OpenSCAP supported |
| Amazon Linux 2023 | High | EC2 Image Builder native |
| Rocky Linux 8 / 9 | High | RHEL-compatible, same pipeline as RHEL |
| UBI 8 / UBI 9 | Medium | Container base image pipeline |
| Debian 12 | Medium | AppArmor instead of SELinux |

---

## Future Considerations

- **Scheduled rebuilds** — rebuild and re-scan on a cadence to catch CIS benchmark updates and base image refreshes. AAP workflow.
- **CVE threshold automation** — integrate with Red Hat Security API to populate `cvss_deny_threshold`.
- **SBOM generation** — produce and sign SBOMs at build time, populate `sbom_ref`.
- **Multi-region AMI publishing** — promote validated AMIs across AWS regions.
