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

## Phase 1.7 — RHEL 9 CIS L1 containerDisk ([#21](https://github.com/ericcames/image.builder.pipeline/issues/21))

**Target:** Same CIS-hardened RHEL 9 image, wrapped as a containerDisk for
OpenShift Virtualization. Pushed to private Quay.io repo for consumption by
[`sales.demos`](https://github.com/ericcames/sales.demos) via `DataImportCron`.

Uses the same Image Builder API with `image_type: "guest-image"` to produce a
qcow2 download instead of an AMI. The qcow2 is wrapped as an OCI container
image and pushed to `quay.io/zigfreed/rhel9-cis-l1-golden:<date>`. See
`docs/design.md` §10 for the containerDisk contract.

| Task | Status |
|------|--------|
| Image Builder API integration for guest-image (qcow2) output | Complete |
| `wait_for_compose.py` polymorphic output for guest-image | Complete |
| `build_cis_containerdisk.yml` playbook | Complete |
| containerDisk build + Quay push workflow | Complete |
| OCI label contract (parallel to AMI tags) | Complete |
| `docs/design.md` §10 — containerDisk contract | Complete |
| End-to-end smoke test: compose → download → build → push → consumer pull | Complete (2026-09-05, tag `20260905-0411`) |
| Monthly scheduled rebuild via GitHub Actions (`containerdisk-rebuild.yml`) | Complete (#48) |

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

## Phase 3 — Windows Server 2022 containerDisk ([#24](https://github.com/ericcames/image.builder.pipeline/issues/24))

**Target:** CIS L1 Windows Server 2022 as a containerDisk on a private Quay.io
repo. No AWS AMI — Windows images are consumed by OpenShift Virtualization via
`DataImportCron`. Producer work is [#24](https://github.com/ericcames/image.builder.pipeline/issues/24),
**in this repo** — transferred here from `sales.demos#193` so the tracker matches
the decision below. Consumer is
[sales.demos#3](https://github.com/ericcames/sales.demos/issues/3), already
shipped. Permanent home is this repo — the factory repo owns hardening +
compliance evidence.

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
| Unattended install + virtio drivers + QEMU guest agent | **Done** — `playbooks/build_windows_image.yml`; built on the cluster via plain KubeVirt VMs, no operator installed. **Measured 21m26s** end to end, ending in a `Stopped`, generalized VM |
| ISO re-mastered onto `efisys_noprompt.bin` in a cluster pod — the build needs nobody at the console | **Done** — [#40](https://github.com/ericcames/image.builder.pipeline/issues/40); `playbooks/scripts/remaster_iso.sh`, Red Hat's `modify-windows-iso-file` recipe |
| ansible-lockdown/Windows-2022-CIS hardening with patch tags | Pending |
| WinRM over HTTPS on 5986 (consumer contract) | Pending |
| Audit-tag evidence capture | Pending |
| sysprep, wrap as containerDisk, `podman push` to Quay | **Done** — `playbooks/publish_windows_containerdisk.yml`; `VirtualMachineExport` → gzip → sparse expand → qcow2 → `FROM scratch`. Publishes `quay.io/zigfreed/win2k22-golden`, **private** — not `win2k22-cis-l1-golden`, which PR 2 earns |
| `data.json` generator for `golden_images/os/windows/server_2022/` | Pending |
| `docs/design.md` §10 — add Windows-specific content (§10 exists for RHEL 9; Windows needs its own entries) | **Done** — §10.1/10.2 carry the Windows repo, labels and `cis.level=none`; §10.2.1 is the export path |

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

- **Scheduled rebuilds (AMI pipeline)** — containerDisk monthly scheduling is proven and running (#48). Extend to AMI builds when ready. AAP workflow for builds requiring persistent infrastructure (AWS credentials, EC2 deploy).
- **CVE threshold automation** — integrate with Red Hat Security API to populate `cvss_deny_threshold`.
- **SBOM generation** — produce and sign SBOMs at build time, populate `sbom_ref`.
- **Multi-region AMI publishing** — promote validated AMIs across AWS regions.
