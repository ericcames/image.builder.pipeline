# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed
- **`spec.running: true` restarted the VM after sysprep, booting the generalized image into OOBE** (#37). `running` is a *desired state*, not one-shot: when the guest powered itself off at the end of `sysprep /generalize /oobe /shutdown`, KubeVirt started it straight back up. **This is the most dangerous defect found so far, because it produces a disk that looks fine and is not** — OOBE consumes the generalization, and a "golden image" that was never generalized surfaces much later as cloned VMs colliding on SIDs and machine names. Caught only because someone had the console open. Replaced with `runStrategy: Once`, which starts the VMI exactly once and leaves the VM `Stopped` when the guest halts — also making "wait for Stopped" a real completion signal rather than a race it could never win.

### Fixed
- **The ISO was transferred the wrong way across the network** (#36). The playbook had the operator's machine download 4.7 GB from Microsoft and push the same 4.7 GB back up a domestic uplink. Measured: **~1 MiB/s up, ~75 min**, against **~246 MiB/s** for CDI importing directly on the cluster — **117 s end to end, verified**. `windows_iso_source` now defaults to `url` and CDI imports via `source.http`; the `upload` path remains for a cluster with no egress. **This was not a bug** — the code did what it said. It was the wrong shape, and only a stopwatch revealed it.
- **The virtio-win image reference was wrong three ways** (#36): the repo is `virtio-win-rhel9` not `virtio-win`, it *refuses* the `:latest` tag so an untagged reference cannot pull at all, and CNV pins it by digest which moves with the CNV version. No hardcoded string stays correct. The playbook now reads the `virtio-win` ConfigMap that HCO publishes in `openshift-cnv`, which is right on any cluster at any version; `virtio_win_image` remains an override for air-gapped mirrors.
- **Boot order put the blank root disk ahead of the install CD** (#36), so EFI tried an empty disk first and fell through to a prompt nobody could answer.
- `cnv_namespace` was referenced as `win_cnv_namespace`, a variable that never existed. **`ansible-lint` passes this at the production profile** — undefined runtime variables are not something static analysis catches, which is worth remembering when a lint-green playbook has never been executed.

### Fixed
- **`virtctl` ignored `K8S_AUTH_*` and silently targeted `localhost:8080`** (#33). Those are the *python* client's variables, consumed by `kubernetes.core`; `virtctl` is a Go client that reads a kubeconfig or its own flags. The play-level `environment:` block covered every `kubernetes.core` task and nothing else — invisible until the playbook actually ran, which #29 said in as many words had not happened. Fixed with a mode `0600` kubeconfig written to a temp file and deleted in an `always:` block; `--token` would have worked and would have put the bearer token in the process list where any local user can read it with `ps`.
- **The ISO upload deadlocked on `WaitForFirstConsumer` storage** — `cannot upload to DataVolume in PendingPopulation phase`. The PVC will not bind until a pod consumes it, and the upload needs it bound first. `--force-bind` is the imperative twin of the `cdi.kubevirt.io/storage.bind.immediate.requested` annotation. Measured on sandbox: the default class is `ocs-external-storagecluster-ceph-rbd`, WFFC.
- **The idempotence check tested existence rather than success, and that was the dangerous one.** A failed upload leaves the DataVolume behind in `PendingPopulation`, so a re-run that only asked "does it exist?" would have skipped the upload and installed Windows from an **empty disk** — a broken image that looks like a successful build. The playbook now reads the DataVolume's phase, deletes a non-`Succeeded` one, and re-uploads.

### Added
- `playbooks/build_cis_containerdisk.yml` — builds RHEL 9 CIS L1 qcow2 via Image Builder `guest-image` type, wraps as containerDisk, pushes to private Quay.io repo. Closes #21
- `wait_for_compose.py` handles guest-image compose results (download URL) in addition to AMI compose results — backward-compatible
- `docs/design.md` §10 — containerDisk contract for OpenShift Virtualization: distribution model, OCI labels, credential pattern, compliance evidence strategy. Parallel to §9's AMI contract
- `ROADMAP.md` Phase 1.7 — RHEL 9 CIS L1 containerDisk
- `.claude/skills/rhel9-containerdisk/SKILL.md` — preflight, API validation, run, verify, and troubleshooting for the RHEL 9 containerDisk build
- `.claude/skills/windows-image-build/SKILL.md` — the Windows build had no skill, so its preflight existed only as asserts inside the playbook, discovered one failure at a time. Covers acquiring the media, the run, verification that asks the cluster rather than trusting the recap, and the teardown. Closes #30
- `playbooks/scripts/wim_images.py` — prints the image names inside a `.wim` by parsing the WIM header's XML resource. **`windows_image_name` must match one of those names exactly**; get it wrong and Windows Setup stops on the edition-selection screen, which reads as a hang because there is no console output to explain it.
- `README.md` now lists the four skills. There was no skills section at all, despite three already existing.

### Changed
- `windows_iso_sha256` now **defaults to the verified checksum** rather than empty, on the same reasoning `execution-environment.yml` pins terraform: a factory that does not know what it consumed cannot say what it produced. Pass `-e windows_iso_sha256=''` to skip.
- `build_windows_image.yml` records the four WIM images the evaluation ISO actually contains, so the `windows_image_name` default is documented as verified rather than assumed.

### Verified
- Windows Server 2022 evaluation ISO, from Microsoft's own fwlink (`LinkID=2195280`, redirecting to `software-static.download.prss.microsoft.com`): **5,044,094,976 bytes**, SHA256 `3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325`, volume `SSS_X64FREE_EN-US_DV9`.
- `sources/install.wim` holds 4 images. `Windows Server 2022 SERVERSTANDARD` is index 2, the Desktop Experience variant — which is what the playbook already defaulted to, now confirmed instead of guessed. Every `EDITIONID` is `ServerStandardEval` / `ServerDatacenterEval`, which is how evaluation media is told apart from licensed media at a glance.
- The full preflight chain runs green against the real ISO — state, connection, demo-cluster refusal, inputs, checksum match, `virtctl` — failing only at the first cluster API call, which is as far as it can get without a live cluster.

### Added
- `playbooks/build_windows_image.yml` + `playbooks/templates/autounattend.xml.j2` — unattended Windows Server 2022 build for the Phase 3 containerDisk. **PR 1 of 3 on #24: build only, unhardened.** Hardening is PR 2, export and publish are PR 3.
- **Built on the cluster, not on a laptop.** #21 flags "a local libvirt/KVM scan path — new hypervisor dependency" as its High-risk item; a KubeVirt cluster *is* a hypervisor, so this avoids that dependency rather than incurring it, and the image is exercised by KubeVirt before any consumer sees it. Plain `VirtualMachine` objects driven with `kubernetes.core`, the same way this repo already drives EC2 with `amazon.aws` — **no operator is installed**, so there is no cross-repo dependency on the consumer's cluster configuration.
- **The answer file is delivered as a ConfigMap.** KubeVirt renders a `configMap` volume as an iso9660 CD and Windows Setup reads `autounattend.xml` from removable media, so no ISO-authoring tool is needed on the machine running the playbook.
- **Sysprep is flag-guarded.** `windows_sysprep_at_first_logon` defaults true so PR 1 finishes without a WinRM round trip and stays free of the Windows collections. PR 2 sets it false and syspreps after hardening — generalizing first would throw the hardening away.
- `collections/requirements.yml` pins `kubernetes.core` 6.4.0, matching sales.demos so producer and consumer cannot disagree about the client library.
- `docs/design.md` §4 documents `K8S_AUTH_HOST`, `K8S_AUTH_API_KEY` and `WINDOWS_ADMIN_PASSWORD` — env vars, consistent with the model that section already states. Nothing is read from sales.demos' vault.
- **The playbook refuses to build on the demo cluster.** Builds run on sandbox; demo consumes the published tag and never hosts a build. Asserted rather than merely documented, because a 45-minute Windows install on a cluster someone is presenting from is the mistake worth making impossible.
- **`windows_eval_expires` is required.** Evaluation media expires after 180 days and an expired Windows guest nags and then shuts down hourly. The date is asserted, stamped onto the VM as a label, and printed at the end so it reaches the run-sheet.

### Fixed
- `ROADMAP.md` Phase 3 and `CLAUDE.md` tracked the Windows producer as `sales.demos#193`. That issue was **transferred into this repo** and is now [#24](https://github.com/ericcames/image.builder.pipeline/issues/24), so the roadmap asserted "permanent home is this repo" while the tracker pointed elsewhere. GitHub redirects a transferred issue so neither link was broken, but the reference read as "the work lives in the other repo" — the opposite of the decision Phase 3 records — and sent a reader out of this repository to be bounced back into it. `sales.demos` updated its 24 references in its PR #200. Closes #25
- `build_cis_image.yml` token lookup path — was reading from frozen `~/.ansible/ansible.cfg` (stale Oct 2025 token) instead of active `~/.ansible.cfg`. Latent bug that would 401 on next token rotation. Closes #22
- Stale "Same AWS account as DC1" claim in CLAUDE.md — Image Builder builds in service account `463606842039` and shares with the consumer account; CLAUDE.md now matches the corrected design.md §9.1
- `docs/design.md` §9.1 and `ROADMAP.md` AMI ownership contract — Red Hat Image Builder is a **hosted service** that builds AMIs in its own service account (`463606842039`) and shares them with the consumer account via the API's `share_with_accounts` field. The consumer never owns the AMI, only receives launch permission. Previous text claimed "pipeline and DC1 share one AWS account; no cross-account sharing" and prescribed `owners = ["self"]` for the DC1 data source — both wrong. Surfaced when [demo.datacenter PR #14](https://github.com/ericcames/demo.datacenter/pull/14) ran end-to-end and `terraform plan` returned "no results" against the shared AMI.

### Changed
- All cross-repo references updated: `aap.as.code` and `demo.datacenter` → [`sales.demos`](https://github.com/ericcames/sales.demos) throughout CLAUDE.md, ROADMAP.md, README.md, CONTRIBUTING.md, and `docs/design.md` §9
- `docs/design.md` §9 header renamed from "Integration with demo.datacenter (DC1)" to "Downstream consumers" — the mechanism is consumer-agnostic
- Phase 3 roadmap rewritten: Windows Server 2022 will ship as a CIS-hardened containerDisk on Quay.io, not an AWS AMI. Tracked in #21
- CLAUDE.md consumer table expanded to three rows (rego_policy_libraries, sales.demos AMIs, sales.demos containerDisks)
- Branch naming convention aligned with `sales.demos`: `<type>-<issue>-<slug>` replaces `<type>/<description>`
- CONTRIBUTING.md updated: `main` is now protected, PRs always required

### Added
- `.claude/skills/collections-sync/SKILL.md` — pin, install, and verify Ansible collections; audit script detects drift between pinned and installed versions. Closes #27
- `.claude/skills/first-time/SKILL.md` — prerequisite validation for new sessions: Hub token in `~/.ansible.cfg`, collections, AWS credential pattern, troubleshooting table
- CLAUDE.md skills table listing all three Claude agent skills
- `.claude/skills/dev-workflow/SKILL.md` — mandatory development cycle for Claude agents working in this repo
- CLAUDE.md workflow section — documents protected `main`, branch naming, multi-session safety, standing merge authorization
- `main` branch protection: required CI checks (`yamllint`, `ansible-lint`), PRs required, enforce admins, no force pushes

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
