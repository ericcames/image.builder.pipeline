# Roadmap

## Goal

Automate the full lifecycle of building, scanning, and validating CIS-compliant
machine images — producing structured policy data for OPA enforcement in
[rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries).

---

## Phase 1 — RHEL 9 (Active)

**Target:** CIS Level 1 Server, RHEL 9

| Task | Status |
|------|--------|
| Image Builder API integration — create blueprint and trigger compose | Pending |
| AWS EC2 deploy and SCAP result extraction | Pending |
| OpenSCAP XCCDF result parser | Pending |
| `data.json` generator for `golden_images/os/linux/rhel_9/` | Pending |
| Enumerate and document AWS-specific exempt controls (P3) | Pending |
| End-to-end test: build → scan → generate | Pending |

---

## Phase 2 — RHEL Family Expansion

**Target:** RHEL 8, RHEL 10

| Task | Status |
|------|--------|
| RHEL 8 CIS Level 1 pipeline (mirrors Phase 1) | Pending |
| RHEL 10 pipeline — pending CIS RHEL 10 benchmark publication | Blocked |

---

## Phase 3 — Windows Server 2022

**Target:** CIS Level 1, Windows Server 2022

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

- **Scheduled runs** — rebuild and re-scan on a schedule to catch CIS benchmark updates
- **CVE threshold automation** — integrate with Red Hat Security API to populate `cvss_deny_threshold`
- **SBOM generation** — produce and sign SBOMs at build time, populate `sbom_ref`
- **Multi-region AMI publishing** — promote validated AMIs across AWS regions
