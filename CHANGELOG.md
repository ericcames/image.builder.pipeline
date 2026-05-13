# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed
- `docs/design.md` §9.1 and `ROADMAP.md` AMI ownership contract — Red Hat Image Builder is a **hosted service** that builds AMIs in its own service account (`463606842039`) and shares them with the consumer account via the API's `share_with_accounts` field. The consumer never owns the AMI, only receives launch permission. Previous text claimed "pipeline and DC1 share one AWS account; no cross-account sharing" and prescribed `owners = ["self"]` for the DC1 data source — both wrong. Surfaced when [demo.datacenter PR #14](https://github.com/ericcames/demo.datacenter/pull/14) ran end-to-end and `terraform plan` returned "no results" against the shared AMI.

### Added
- GitHub community health files: `CONTRIBUTING.md`, `.github/SECURITY.md`, `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`, `.github/pull_request_template.md` — tailored to pipeline context, ROADMAP phases, and the two-consumer contract


- `playbooks/vars/exempt_controls.yml` — curated exempt list with canonical reasons for AWS-inherent CIS rules (`grub2_password`, `ensure_root_password_configured`, `partition_for_tmp`). Merged into `data.json` at generate time; curated entries take precedence over parser-auto-emitted candidates. Closes #11
- `build_cis_image.yml` Image Builder customizations.packages list — installs `aide`, `firewalld`, `systemd-journal-remote` at build time. First experiment toward closing the CIS L1 packaging gaps tracked in #10
- Two more curated exempts (closes #12): `file_permission_user_init_files` (P2; rule targets deployed-system user homes, not the image artifact) and `sshd_limit_user_access` (P3; SSH access policy is a consumer decision)
- `docs/cis-l1-rhel9-status.md` — snapshot of the latest validated compliance state (AMI, score, exempt rules, reproduction steps, validation history). Linked from README's platform table
- Project docs synced to Phase 1 completion state: ROADMAP marks Phase 1 Complete with all new tasks logged; CLAUDE.md current-state paragraph updated; design.md §3 `data.json` example replaced with a real entry instead of placeholder text
- Phase 1.5: pipeline applies the AMI tagging contract (6 tags: `Pipeline`, `OS`, `CIS-Level`, `BuildDate`, `ComposeID`, `Name`) via `amazon.aws.ec2_tag` after compose. Design changed from name-based to tag-based discovery — `docs/design.md` §9.1-9.2 rewritten. DC1's eventual filter becomes a tag filter, not a name filter
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
