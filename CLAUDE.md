# image.builder.pipeline — Claude Project Context

## What this repo is

Ansible pipeline that builds CIS-hardened RHEL AMIs via Red Hat Image Builder,
scans them with OpenSCAP, and produces structured compliance data.

## Consumers — every change must hold for all of them

| Consumer | Receives | Contract | Audience |
|---|---|---|---|
| [`rego_policy_libraries`](https://github.com/ynotbhatc/rego_policy_libraries) | `data.json` files under `golden_images/` | Schema in `docs/design.md` §6 | OPA policy / compliance |
| [`sales.demos`](https://github.com/ericcames/sales.demos) | AMIs, via `data.aws_ami` tag-filter | `Pipeline` + `OS` + `CIS-Level` tags (§9) | Demo platform |
| [`sales.demos`](https://github.com/ericcames/sales.demos) | Windows containerDisk on Quay.io | One string — a containerdisk tag | OpenShift Virt demos |

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

### Hygiene
- **Always delete tokens.** Any playbook that creates a Red Hat or AAP token must delete it in an `always:` block.
- **Credentials never in repo.** RH token from `~/.ansible.cfg`; AWS via env vars; `docs/aws-environment.md` is gitignored for local notes.
- **Maintain CHANGELOG.md** for every PR — grouped by Added / Changed / Fixed.
- **One concern per PR** — group by shared root cause, not item count.
- **ansible.platform over ansible.controller** wherever possible. `ansible.controller` is legacy.

## Current state (2026-09-04)

- Phase 1 (RHEL 9 CIS L1) — **Complete.** Latest validated AMI `ami-0228edcda0bbb6c3a`, score 98.07 / gate 95, 5 curated exempt entries. Pipeline hardened against token expiration / OOM / cleanup-on-failure. See [`docs/cis-l1-rhel9-status.md`](docs/cis-l1-rhel9-status.md) for the snapshot.
- Phase 1.5 (consumer integration) — tagging contract applied pipeline-side; `sales.demos` tag-filter swap is the remaining work
- Phase 2 (CIS L2, RHEL 8) — not started
- Phase 3 (Windows containerDisk) — direction set: CIS-hardened Windows Server 2022 as containerDisk on Quay.io (#21). Producer work tracked in `sales.demos#193`, consumer in `sales.demos#3`.

See `ROADMAP.md` for the full plan.

## Workflow

- **`main` is protected** — PRs always required, even for the repo owner. CI checks (`yamllint`, `ansible-lint`) must pass.
- **Branch naming:** `<type>-<issue>-<slug>` (e.g. `fix-22-token-path`, `feat-21-windows-containerdisk`)
- **Working tree is shared by multiple Claude sessions.** Re-run `git branch --show-current` immediately before `git add` and `git commit`. Prefer `git add <explicit paths>` over `git add -A`. Use `gh pr create --head <branch>` rather than relying on checkout state.
- **Standing merge authorization:** Claude may merge green PRs without asking.
- **Document before fixing:** open a GitHub issue before code changes.
- See `.claude/skills/dev-workflow/SKILL.md` for the full development cycle.

## Where things live

| File | Purpose |
|---|---|
| `playbooks/build_cis_image.yml` | Image Builder API integration, AMI compose |
| `playbooks/deploy_and_scan.yml` | EC2 deploy, SCAP result extraction |
| `playbooks/generate_policy_data.yml` | XCCDF → `data.json`; merges curated + auto-emitted exempts |
| `playbooks/scripts/wait_for_compose.py` | Token-refreshing Image Builder poll helper (#4) |
| `playbooks/tasks/cleanup_aws.yml` | AWS teardown, included from scan play's `always:` (#6) |
| `playbooks/vars/exempt_controls.yml` | Curated exempt entries with canonical reasons |
| `playbooks/filter_plugins/xccdf.py` | XCCDF parser; emits score, severity breakdown, P3 candidates |
| `docs/design.md` | Full design — §5 exempt controls, §6 OPA consumer, §9 downstream consumers + AMI contract |
| `docs/cis-l1-rhel9-status.md` | Latest validated compliance snapshot |
| `inventories/sample/` | Template inventory; copy to `inventories/<customer>-<platform>/` |
| `output/<platform>/` | Per-platform outputs: `build_output.json`, `scap/`, `data.json` |

## Related repos

- `~/git-repos/sales.demos` — AMI and containerDisk consumer; demo platform with MCP servers for OpenShift sandbox/demo environments
