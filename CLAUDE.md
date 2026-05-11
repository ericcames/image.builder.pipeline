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

### AMI naming — this is the contract with DC1
- **Name pattern:** `{os}-cis-l{level}-{YYYYMMDD-HHMM}` — example `rhel9-cis-l1-20260511-1430`
- **Required tags:** `Pipeline=image-builder-pipeline`, `OS=<os>`, `CIS-Level=L<n>`, `BuildDate=<ISO>`, `ComposeID=<uuid>`
- Breaking the name pattern breaks DC1's `roles/infrastructure/files/variables.tf` filter — treat it as a versioned cross-repo contract.

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

## Current state (2026-05-11)

- Phase 1 (RHEL 9 CIS L1) — **end-to-end run completed 2026-05-11** (AMI `ami-068ff0ada2adefba5`, score 94.94 vs gate 95). Open follow-ups: #4 token-expiration in poll, #5 t3.micro OOM, #6 cleanup-on-failure, #7 score-vs-gate tuning
- Phase 1.5 (DC1 integration) — not started; pipeline doesn't yet apply naming/tagging contract
- Phase 2 (CIS L2, RHEL 8) — not started

See `ROADMAP.md` for the full plan.

## Where things live

| File | Purpose |
|---|---|
| `playbooks/build_cis_image.yml` | Image Builder API integration, AMI compose |
| `playbooks/deploy_and_scan.yml` | EC2 deploy, SCAP result extraction |
| `playbooks/generate_policy_data.yml` | XCCDF → `data.json` (skeleton) |
| `docs/design.md` | Full design — §6 OPA consumer, §9 DC1 consumer + AMI contract |
| `inventories/sample/` | Template inventory; copy to `inventories/<customer>-<platform>/` |
| `output/<platform>/` | Per-platform outputs: `build_output.json`, `scap/`, `data.json` |

## Related repos

- `~/git-repos/demo.datacenter` — AMI consumer; integration point is `roles/infrastructure/files/variables.tf`
- `~/git-repos/aap.as.code` — broader demo platform; DC1 ROADMAP lives there
