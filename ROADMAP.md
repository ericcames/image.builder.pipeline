# Roadmap

## Goal

Automate the full lifecycle of building, scanning, and validating CIS-compliant
machine images — producing structured policy data for OPA enforcement in
[rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries),
and serving as the source of hardened images for
[sales.demos](https://github.com/ericcames/sales.demos).

---

## Phase 1 — RHEL 9 CIS L1 (Complete)

**Target:** End-to-end build → scan → `data.json` for RHEL 9 CIS Level 1 Server.

Validated 2026-05-12. Current state in [docs/cis-l1-rhel9-status.md](docs/cis-l1-rhel9-status.md).

| Task | Status |
|------|--------|
| Image Builder API integration — blueprint, compose, AMI capture | Complete |
| AWS EC2 deploy and SCAP result extraction | Complete |
| Fresh OpenSCAP scan fallback when build-time results unavailable | Complete |
| `collections/requirements.yml` and pinned `amazon.aws` | Complete |
| OpenSCAP XCCDF result parser | Complete |
| `data.json` generator for `golden_images/os/linux/rhel_9/` | Complete |
| Enumerate and document AWS-specific exempt controls | Complete (5 curated entries with documented reasons in `playbooks/vars/exempt_controls.yml`; full text in design.md §5.2) |
| Image Builder customizations to close packaging gaps | Complete (#14 — `aide`, `firewalld`, `systemd-journal-remote` added) |
| Pipeline hardening (token refresh, t3.medium default, cleanup-on-failure) | Complete (#9) |
| End-to-end smoke test: build → scan → generate | Complete (2026-05-12; score 98.07 / gate 95 — OPA-consumes side tracked separately) |

---

## Phase 1.5 — Downstream consumer integration

**Target:** `sales.demos` consumes pipeline-built AMIs instead of stock Red Hat
marketplace AMIs. See `docs/design.md` §9 for the contract.

| Task | Status |
|------|--------|
| Implement AMI tagging contract in `build_cis_image.yml` per design.md §9.2 | Complete (6 tags: `Pipeline`, `OS`, `CIS-Level`, `BuildDate`, `ComposeID`, `Name`) |
| `sales.demos` tag-based `aws_ami` filter (Pipeline + OS + CIS-Level) with `owners = ["463606842039"]` | Pending |
| Smoke test: Satellite installs cleanly on tagged pipeline AMI | Pending |
| Document any CIS-L1-vs-Satellite exempt controls discovered | Pending |
| Roll AMI consumption to all RHEL 9 nodes | Pending |

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

## Phase 3 — Windows Server 2022 containerDisk ([#21](https://github.com/ericcames/image.builder.pipeline/issues/21))

**Target:** CIS L1 Windows Server 2022 as a containerDisk on a private Quay.io
repo. No AWS AMI — Windows images are consumed by OpenShift Virtualization via
`DataImportCron`. Producer work tracked in
[sales.demos#193](https://github.com/ericcames/sales.demos/issues/193); consumer
in [sales.demos#3](https://github.com/ericcames/sales.demos/issues/3). Permanent
home is this repo — the factory repo owns hardening + compliance evidence.

**Key decisions:**

| Decision | Choice | Why |
|---|---|---|
| Hardening | [ansible-lockdown/Windows-2022-CIS](https://github.com/ansible-lockdown/Windows-2022-CIS) | Ansible-native, per-control tags |
| Evidence | Role audit tags | OpenSCAP does not cover Windows; CIS-CAT Pro requires paid SecureSuite membership |
| Install | Unattended from answer file | No manual clicks in an image factory |
| Media | 180-day eval ISO | No volume-licensed media available — **time bomb, must be documented in tag and run-sheet** |
| Distribution | Private Quay repo, containerdisk, date-tagged, never overwritten | Windows cannot be redistributed publicly |
| Consumer contract | One string — a containerdisk tag | Decouples producer from consumer lifecycle |

| Task | Status |
|------|--------|
| Unattended install + virtio drivers + QEMU guest agent | Pending |
| ansible-lockdown/Windows-2022-CIS hardening with patch tags | Pending |
| WinRM over HTTPS on 5986 (consumer contract) | Pending |
| Audit-tag evidence capture | Pending |
| sysprep, wrap as containerDisk, `podman push` to Quay | Pending |
| `data.json` generator for `golden_images/os/windows/server_2022/` | Pending |
| `docs/design.md` §10 — containerDisk contract (parallel to §9 for AMIs) | Pending |

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
