# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- `playbooks/vars/exempt_controls.yml` — curated exempt list with canonical reasons for AWS-inherent CIS rules (`grub2_password`, `ensure_root_password_configured`, `partition_for_tmp`). Merged into `data.json` at generate time; curated entries take precedence over parser-auto-emitted candidates. Closes #11
- Initial repository structure, MIT License, Contributor Covenant Code of Conduct
- README with architecture overview and quick start
- ROADMAP — Phase 1 (RHEL 9 L1), Phase 1.5 (DC1 integration), Phase 2 (L2 / RHEL 8), Phase 3 (Windows), Phase 4 (other platforms)
- `docs/design.md` — full pipeline design, including §6 (OPA consumer) and §9 (demo.datacenter consumer / AMI naming contract)
- `playbooks/build_cis_image.yml` — Image Builder API integration: token exchange, blueprint creation, compose trigger, polling, AMI capture
- `playbooks/deploy_and_scan.yml` — EC2 deploy, SCAP result extraction, fresh OpenSCAP scan fallback when build-time results are missing
- `playbooks/generate_policy_data.yml` — XCCDF results parser, hardening-score computation, `data.json` generator per `docs/design.md` §3
- `playbooks/filter_plugins/xccdf.py` — namespace-agnostic XCCDF parser; returns rule counts, severity breakdown, hardening score (pass / (pass + fail), excluding N/A and notchecked), and AWS exempt-control candidates (auto-emitted for low-severity failures)
- Sample inventory — Red Hat offline token via `~/.ansible/ansible.cfg`, AWS credentials via env vars
- `collections/requirements.yml` pinning `amazon.aws` to 11.2.0
- `.gitignore` covering credentials, collections, and generated output
- GitHub Actions lint workflow (ansible-lint, yamllint)
- Project-level `CLAUDE.md` capturing repo conventions and the two-consumer contract

### Changed
- Dynamic VPC and subnet discovery instead of relying on default VPC
- Async oscap execution for long-running scans
- IdentitiesOnly=yes for SSH; unique per-run EC2 instance names
- CI lint workflow restored to green (closes #2): `.yamllint` relaxes `line-length` to 120 (Ansible community norm); `ansible/ansible-lint` action bumped `v24 → v26` for `ansible-core` 2.19 compatibility
- `build_cis_image.yml`: build-output dict moved to a `vars:` block (was a 224-char inline Jinja expression)
- Phase 1 end-to-end run completed 2026-05-11 — first real RHEL 9 CIS L1 AMI through the full pipeline. Score 94.94 vs gate 95; follow-ups tracked in #4, #5, #6, #7

### Fixed
- AMI region taken from compose result instead of assumed
- `network_interfaces` deprecation in `amazon.aws` module
- Empty `TARGET_PLATFORM` env var handled with default filter
- Duplicate vars block in `deploy_and_scan.yml` merged
- `generate_policy_data.yml` now reads `scap/scap-results.xml` (matches the path `deploy_and_scan.yml` writes)
- `build_cis_image.yml` no longer fails mid-compose when the access token expires — polling moved to `scripts/wait_for_compose.py` which refreshes the token every iteration. Closes #4
- `deploy_and_scan.yml` default instance type bumped `t3.micro → t3.medium`; the smaller size OOMs reliably during the RHEL 9 SCAP scan. Closes #5
- `deploy_and_scan.yml` cleanup now lives in a `block:`/`always:` so AWS resources are torn down even when the scan task fails. Closes #6
