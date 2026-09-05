# image.builder.pipeline — Claude Project Context

## What this repo is

Ansible pipeline that builds CIS-hardened RHEL AMIs via Red Hat Image Builder,
scans them with OpenSCAP, and produces structured compliance data.

## Consumers — every change must hold for all of them

| Consumer | Receives | Contract | Audience |
|---|---|---|---|
| [`rego_policy_libraries`](https://github.com/ynotbhatc/rego_policy_libraries) | `data.json` files under `golden_images/` | Schema in `docs/design.md` §6 | OPA policy / compliance |
| [`sales.demos`](https://github.com/ericcames/sales.demos) | AMIs, via `data.aws_ami` tag-filter | `Pipeline` + `OS` + `CIS-Level` tags (§9) | Demo platform |
| [`sales.demos`](https://github.com/ericcames/sales.demos) | RHEL 9 containerDisk on Quay.io | One string — a containerdisk tag (§10) | OpenShift Virt demos |
| [`sales.demos`](https://github.com/ericcames/sales.demos) | Windows containerDisk on Quay.io | One string — a containerdisk tag (§10) | OpenShift Virt demos |

If a change works for one consumer but breaks another, it doesn't ship.

## Rules

### Architecture
- **Never merge this repo into sales.demos.** Producer/consumer across repos is intentional. Different audiences, different lifecycles.
- **OS-only AMIs.** Don't bake products (Satellite, app stacks) into the image. Consumers install products on top via their own setup playbooks.
- **Image Builder uses its own AWS account.** AMIs are built in Red Hat's service account (`463606842039`) and shared with the consumer account via `share_with_accounts`. Consumers filter on `owners = ["463606842039"]`, not `owners = ["self"]`.
- **Phase order is enforced.** Don't add L2 until L1 is end-to-end working. Don't add RHEL 8 until RHEL 9 is solid. Skipping phases creates compounding bugs.

### AMI tagging — this is the contract with downstream consumers
- **Tag-based discovery, not name-based.** Consumers filter on `Pipeline` + `OS` + `CIS-Level` tags.
- **Required tags:** `Pipeline=image-builder-pipeline`, `OS=<os>`, `CIS-Level=L<n>`, `BuildDate=<ISO>`, `ComposeID=<uuid>`, `Name=<os>-cis-l<n>-<YYYYMMDD-HHMM>` (Name is human-readable; not a discovery key)
- Breaking the tag contract breaks consumers' `data "aws_ami"` filters — treat it as a versioned cross-repo contract.

### CIS levels
- **Satellite host OS:** CIS L1 only. L2 fights Satellite's installer (firewall, services on ports 80/443/5647/8000/8140/9090).
- **RHEL workload nodes:** L1 baseline; L2 available per workload group when L2 builds mature.
- See `docs/design.md` §9.5 for per-layer assignment.

### Verification — every defect in Phase 3 was found by running it, none by lint

Six defects in one day on #24 (#42, #44, #46, #50, #54, and the export token).
`ansible-lint` passed at the production profile through all of them. These are
the rules that came out of it, and each one is paid for.

- **Lint-green means nothing here.** It does not execute. A playbook that has
  never run is unverified, however clean the diff.
- **Verify against the real input, not a fixture you built with the tool under
  test.** #44: a synthetic ISO built by `xorriso -as mkisofs` proved `xorriso`
  could read it. The real Windows medium is UDF and `xorriso` read one node
  out of it.
- **Verify with the same tool the code uses.** The export's token secret is
  named in `status.tokenSecretRef`; `virtctl` sets `spec` itself, so checking
  by hand with `virtctl` exercised a path the playbook never takes.
- **The part you did not have to re-run is the part that breaks.** #46: a fix
  re-verified with `ISO_URL=file://`, because the media was already local,
  shipped with the HTTPS path untested. The guestfish image has no CA bundle.
- **Read a moving indicator twice before concluding "slow".** #50: Windows Setup
  restarted for four hours with the progress bar advancing. 51%, then 82%, then
  **49%**. One reading cannot tell progress from a loop.
- **A rate computed from an assumption is not a measurement.** The same four
  hours produced "~3 min per percentage point, so the storage is the
  bottleneck", which was void and had already been repeated to the user.
- **Before removing a manual step, ask what it does on the paths you are not
  looking at.** #50 again: "press any key" was the last manual step *and* the
  thing stopping an infinite install loop.
- **When a fix removes the reason for an older fix, revert the older one in the
  same PR.** #36 put the install CD first *because* of that prompt; #40 removed
  the prompt and left the boot order.
- **Write the guard in the PR that finds the need for it.** #44 and #46 were
  each caught in seconds by a guard added in the previous PR. #50 had no guard
  and cost four hours; it has one now.
- **A `no_log: true` task that fails reports `censored` and tells you nothing.**
  Keep `no_log` where the result carries a secret — and put asserts either side
  of it that fail with real messages.

### Hygiene
- **Always delete tokens.** Any playbook that creates a Red Hat or AAP token must delete it in an `always:` block.
- **Credentials never in repo.** RH token from `~/.ansible.cfg`; AWS via env vars; `docs/aws-environment.md` is gitignored for local notes.
- **Maintain CHANGELOG.md** for every PR — grouped by Added / Changed / Fixed.
- **One concern per PR** — group by shared root cause, not item count.
- **ansible.platform over ansible.controller** wherever possible. `ansible.controller` is legacy.

## Current state (2026-09-05)

- Phase 1 (RHEL 9 CIS L1) — **Complete.** Latest validated AMI `ami-0228edcda0bbb6c3a`, score 98.07 / gate 95, 5 curated exempt entries. Pipeline hardened against token expiration / OOM / cleanup-on-failure. See [`docs/cis-l1-rhel9-status.md`](docs/cis-l1-rhel9-status.md) for the snapshot.
- Phase 1.5 (consumer integration) — tagging contract applied pipeline-side; `sales.demos` tag-filter swap is the remaining work
- Phase 1.7 (RHEL 9 containerDisk) — **Complete.** First image `quay.io/zigfreed/rhel9-cis-l1-golden:20260905-0411`. Monthly scheduled rebuild via GitHub Actions (`containerdisk-rebuild.yml`). See `docs/design.md` §10 for the containerDisk contract.
- Phase 2 (CIS L2, RHEL 8) — not started
- Phase 3 (Windows containerDisk) — **In progress.** Unattended build playbook shipped (`build_windows_image.yml`, #24); ISO re-master for no-keypress boot done (#40); skill documented. CIS hardening, sysprep, and Quay publish still pending. Consumer is `sales.demos#3`, already shipped.

See `ROADMAP.md` for the full plan.

## Workflow

- **`main` is protected** — PRs always required, even for the repo owner. CI checks (`yamllint`, `ansible-lint`) must pass via `.github/workflows/lint.yml`.
- **Scheduled builds** — `.github/workflows/containerdisk-rebuild.yml` rebuilds the RHEL 9 containerDisk monthly (1st of month, 06:00 UTC). Manual trigger via `workflow_dispatch`. See `docs/operations.md` for the runbook.
- **Branch naming:** `<type>-<issue>-<slug>` (e.g. `fix-22-token-path`, `feat-21-windows-containerdisk`)
- **Working tree is shared by multiple Claude sessions.** Re-run `git branch --show-current` immediately before `git add` and `git commit`. Prefer `git add <explicit paths>` over `git add -A`. Use `gh pr create --head <branch>` rather than relying on checkout state.
- **Standing merge authorization:** Claude may merge green PRs without asking.
- **Document before fixing:** open a GitHub issue before code changes.
- See `.claude/skills/dev-workflow/SKILL.md` for the full development cycle.

## Skills

| Skill | Purpose |
|---|---|
| `.claude/skills/dev-workflow/` | Mandatory development cycle — issue, branch, PR, merge |
| `.claude/skills/collections-sync/` | Pin, install, verify Ansible collections in `collections/requirements.yml` |
| `.claude/skills/first-time/` | Prerequisite validation — Hub token, collections, AWS credential pattern |
| `.claude/skills/rhel9-containerdisk/` | Build and publish the RHEL 9 CIS L1 containerDisk (Phase 1.7) |
| `.claude/skills/windows-image-build/` | Build the Windows Server 2022 containerDisk (Phase 3) |

## Where things live

| File | Purpose |
|---|---|
| `playbooks/build_cis_image.yml` | Image Builder API integration, AMI compose |
| `playbooks/build_cis_containerdisk.yml` | Image Builder guest-image → containerDisk → Quay push |
| `playbooks/deploy_and_scan.yml` | EC2 deploy, SCAP result extraction |
| `playbooks/generate_policy_data.yml` | XCCDF → `data.json`; merges curated + auto-emitted exempts |
| `playbooks/scripts/wait_for_compose.py` | Token-refreshing Image Builder poll helper (#4) |
| `playbooks/tasks/cleanup_aws.yml` | AWS teardown, included from scan play's `always:` (#6) |
| `playbooks/vars/exempt_controls.yml` | Curated exempt entries with canonical reasons |
| `playbooks/filter_plugins/xccdf.py` | XCCDF parser; emits score, severity breakdown, P3 candidates |
| `docs/design.md` | Full design — §5 exempt controls, §6 OPA consumer, §9 AMI contract, §10 containerDisk contract |
| `playbooks/build_windows_image.yml` | Windows Server 2022 unattended build for Phase 3 containerDisk |
| `playbooks/templates/autounattend.xml.j2` | Windows unattended install answer file template |
| `playbooks/scripts/remaster_iso.sh` | Windows ISO no-keypress boot patch (El Torito byte-exact overwrite) |
| `playbooks/scripts/fetch_iso.sh` | Windows ISO fetch helper for the re-master pod |
| `playbooks/scripts/wim_images.py` | WIM image name parser for `windows_image_name` validation |
| `docs/cis-l1-rhel9-status.md` | Latest validated compliance snapshot |
| `docs/operations.md` | Operational runbook — manual rebuild, secret rotation, troubleshooting |
| `.github/workflows/lint.yml` | CI lint gate (yamllint + ansible-lint) on push/PR to main |
| `.github/workflows/containerdisk-rebuild.yml` | Monthly scheduled RHEL 9 containerDisk rebuild + manual dispatch |
| `inventories/sample/` | Template inventory; copy to `inventories/<customer>-<platform>/` |
| `output/<platform>/` | Per-platform outputs: `build_output.json`, `scap/`, `data.json` |

## Related repos

- `~/git-repos/sales.demos` — AMI and containerDisk consumer; demo platform with MCP servers for OpenShift sandbox/demo environments
