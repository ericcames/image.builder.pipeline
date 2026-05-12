# image.builder.pipeline — Claude Project Context

## What this repo is

Ansible pipeline that builds CIS-hardened RHEL AMIs via Red Hat Image Builder,
scans them with OpenSCAP, and produces structured compliance data.

## Two consumers — both matter for every change

| Consumer | Receives | Audience |
|---|---|---|
| [`rego_policy_libraries`](https://github.com/ynotbhatc/rego_policy_libraries) | `data.json` files under `golden_images/` | OPA policy / compliance |
| [`demo.datacenter`](https://github.com/ericcames/demo.datacenter) (DC1) | AMIs themselves, via `data.aws_ami` name-filter | Demo platform |

If a change works for one consumer but breaks the other, it doesn't ship.

## Rules

### Architecture
- **Never merge this repo into demo.datacenter.** Producer/consumer across repos is intentional. Different audiences, different lifecycles.
- **OS-only AMIs.** Don't bake products (Satellite, app stacks) into the image. DC1 installs products on top via its own setup playbooks.
- **Same AWS account as DC1.** No cross-account AMI sharing logic.
- **Phase order is enforced.** Don't add L2 until L1 is end-to-end working. Don't add RHEL 8 until RHEL 9 is solid. Skipping phases creates compounding bugs.

### AMI tagging — this is the contract with DC1
- **Tag-based discovery, not name-based.** Consumers filter on `Pipeline` + `OS` + `CIS-Level` tags.
- **Required tags:** `Pipeline=image-builder-pipeline`, `OS=<os>`, `CIS-Level=L<n>`, `BuildDate=<ISO>`, `ComposeID=<uuid>`, `Name=<os>-cis-l<n>-<YYYYMMDD-HHMM>` (Name is human-readable; not a discovery key)
- Breaking the tag contract breaks DC1's `data "aws_ami"` filter — treat it as a versioned cross-repo contract.

### CIS levels
- **Satellite host OS:** CIS L1 only. L2 fights Satellite's installer (firewall, services on ports 80/443/5647/8000/8140/9090).
- **RHEL workload nodes:** L1 baseline; L2 available per workload group when L2 builds mature.
- See `docs/design.md` §9.5 for per-layer assignment.

### Hygiene
- **Always delete tokens.** Any playbook that creates a Red Hat or AAP token must delete it in an `always:` block.
- **Credentials never in repo.** RH token from `~/.ansible/ansible.cfg`; AWS via env vars; `docs/aws-environment.md` is gitignored for local notes.
- **Maintain CHANGELOG.md** for every PR — grouped by Added / Changed / Fixed.
- **One concern per PR** — group by shared root cause, not item count.
- **ansible.platform over ansible.controller** wherever possible. `ansible.controller` is legacy.

## Current state (2026-05-12)

- Phase 1 (RHEL 9 CIS L1) — **Complete.** Latest validated AMI `ami-0228edcda0bbb6c3a`, score 98.07 / gate 95, 5 curated exempt entries. Pipeline hardened against token expiration / OOM / cleanup-on-failure. See [`docs/cis-l1-rhel9-status.md`](docs/cis-l1-rhel9-status.md) for the snapshot.
- Phase 1.5 (DC1 integration) — tagging contract applied pipeline-side; DC1's `data.tf.j2` tag-filter swap is the remaining work
- Phase 2 (CIS L2, RHEL 8) — not started

See `ROADMAP.md` for the full plan.

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
| `docs/design.md` | Full design — §5 exempt controls, §6 OPA consumer, §9 DC1 consumer + AMI contract |
| `docs/cis-l1-rhel9-status.md` | Latest validated compliance snapshot |
| `inventories/sample/` | Template inventory; copy to `inventories/<customer>-<platform>/` |
| `output/<platform>/` | Per-platform outputs: `build_output.json`, `scap/`, `data.json` |

## Related repos

- `~/git-repos/demo.datacenter` — AMI consumer; integration point is `roles/infrastructure/files/variables.tf`
- `~/git-repos/aap.as.code` — broader demo platform; DC1 ROADMAP lives there
