# image.builder.pipeline

The image factory. It takes a Red Hat Image Builder blueprint and returns a
CIS-hardened machine image together with the evidence that it *is* hardened — an
AWS AMI or an OpenShift Virtualization containerDisk, plus OpenSCAP scan results
parsed into policy data that OPA can enforce against. Hardening an image is the
straightforward half. Proving it stayed hardened is the half that gets asked
about with a customer in the room, and that is what the scan and generate stages
are for.

| | |
|---|---|
| **For** | Anyone who needs a hardened base image *and* the compliance evidence behind it |
| **Produces** | CIS L1 AMIs, containerDisks on Quay.io, and `data.json` policy data |
| **Run it** | One `ansible-playbook` per stage — see [Getting started](#getting-started) |
| **Status** | RHEL 9 complete — OpenSCAP 98.07 against a 95-point gate. See [Supported platforms](#supported-platforms) |

**This repo is the producer**, and the dependency only ever runs outward:
[sales.demos](https://github.com/ericcames/sales.demos) consumes the images,
[rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries)
consumes the compliance data, and nothing here depends on either. See
[Related repositories](#related-repositories).

## Getting started

**Consuming the images?** You do not need this repo. The AMIs and containerDisks
are published, and the only thing binding a consumer to this repo is one image
tag. Go to [sales.demos](https://github.com/ericcames/sales.demos) — it points a
cluster at a published containerdisk and never builds one. Nothing below applies
to you.

**Building or publishing an image?** New machine, or a fresh clone? **Start with
the `first-time` skill.** It validates every local prerequisite — the Automation
Hub token, the collections, and the AWS credential pattern — and touches no AWS
or Red Hat API doing it:

```bash
git clone https://github.com/ericcames/image.builder.pipeline.git
cd image.builder.pipeline
claude .
# then:  /first-time
```

[`.claude/skills/first-time/SKILL.md`](.claude/skills/first-time/SKILL.md) is
written to be *run* as a skill in Claude Code, but its Step 0 audit is a plain
shell block — paste it into a terminal and work down the list by hand if you do
not have Claude Code.

### Prerequisites

- Red Hat account with Image Builder access (console.redhat.com)
- Red Hat offline token in `~/.ansible.cfg` under `[galaxy_server.rh_certified]` as `token=`
  (same token used for Automation Hub — obtain from console.redhat.com → Automation Hub → Connect to Hub → API token)
- AWS credentials with EC2 permissions
- Ansible collections (installed via requirements.yml)

```bash
ansible-galaxy collection install -r collections/requirements.yml -p ./collections
```

### AMI pipeline (AWS)

```bash
cp -r inventories/sample/ inventories/<customer>-<platform>/

export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=<your_aws_account_id>

ansible-playbook -i inventories/<customer>-<platform>/ playbooks/build_cis_image.yml
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/deploy_and_scan.yml
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/generate_policy_data.yml
```

### containerDisk pipeline (OpenShift Virt)

```bash
podman login quay.io                  # one-time setup
# QUAY_REPO defaults to quay.io/zigfreed/rhel9-cis-l1-golden
ansible-playbook playbooks/build_cis_containerdisk.yml
```

### Working across both repos

Most work needs only one. Some spans both — the edge / SNO demo does by
construction, since the installer ISO is built here and the cluster is
configured in `sales.demos`.

When it does, clone both and **start the agent in `sales.demos`, not here**: its
`.mcp.json` is project-scoped, so the cluster servers load only in a session
started there, and this repo has none. From there you can `cd` back here and run
these playbooks anyway.

**This repo's skills are the exception** — `first-time`, `dev-workflow`,
`rhel9-containerdisk`, `windows-image-build` are discovered from the directory
the agent starts in, so they are *not* reachable from a `sales.demos` session.
Open a second session here to use them.

The full version of this, including the clone commands, is in
[sales.demos' README](https://github.com/ericcames/sales.demos#working-across-the-factory-and-this-repo).
It is kept there rather than duplicated here, because that is where the session
is meant to start — and because the two copies had already begun to drift.

## Overview

This pipeline automates four stages:

1. **Build** — trigger a CIS-hardened image compose via the Red Hat Image Builder API (AMI or qcow2)
2. **Scan** — deploy the image to AWS and extract OpenSCAP results (AMI path)
3. **Generate** — parse SCAP results into `data.json` policy data files
4. **containerDisk** — wrap qcow2 as a containerDisk and push to Quay.io for OpenShift Virtualization

The output feeds directly into the `golden_images/` policy module in `rego_policy_libraries`,
populating approved baseline values, exempt controls, and compliance thresholds.

## Architecture

```
Red Hat Image Builder (console.redhat.com)
        │
        ├──────────────────────────┐
        ▼ AMI                     ▼ qcow2
   AWS EC2 (temp instance)   containerDisk wrap
        │                         │
        ▼ SCAP results            ▼ podman push
   OpenSCAP Parser           Quay.io
        │                         │
        ▼                         ▼
   data.json → rego_policy    DataImportCron →
   _libraries/golden_images/  OpenShift Virt VMs
```

## Supported platforms

| Platform | Output | CIS Benchmark | Status |
|----------|--------|--------------|--------|
| RHEL 9 | AMI | CIS Level 1 Server | **Phase 1 — Complete** (score 98.07 / 95 gate — see [status](docs/cis-l1-rhel9-status.md)) |
| RHEL 9 | containerDisk | CIS Level 1 Server | **Phase 1.7 — Complete** (public repo) |
| RHEL 8 | AMI | CIS Level 1 Server | Phase 2 |
| RHEL 10 | AMI | CIS Level 1 Server | Phase 2 — pending benchmark |
| Windows Server 2022 | containerDisk | CIS Level 1 | **Built and published** — 44 controls applied, consumed by `sales.demos` ([caveat](#the-windows-row-says-published-not-verified)) |

See [ROADMAP.md](ROADMAP.md) for full platform schedule and
[docs/cis-l1-rhel9-status.md](docs/cis-l1-rhel9-status.md) for the
latest RHEL 9 compliance snapshot.

### The Windows row says "published", not "verified"

The RHEL 9 row quotes a score because one exists: OpenSCAP 98.07 against a
95-point gate. The Windows row cannot, and the distinction is deliberate.

[#91](https://github.com/ericcames/image.builder.pipeline/issues/91) was a tag
labelled `cis.level=L1` whose disk was the unhardened build from two days
earlier — a publish repackaged a stale local `disk.qcow2` because the conversion
was guarded by `creates:` on a file cleanup never removed. The guest scored 9 of
27. **The label is therefore not evidence**, and neither is a green compliance
scan: `windows_compliance_fail_on_noncompliant` defaults to `false` in the
consumer, so that job reports a score rather than gating on one.

What *is* known about the current tag: it was built sixty-one minutes after the
#91 fix landed, so it is the first publish with the stale-artifact path removed,
and `sales.demos` reports the clone reaching the desktop with `win_ping`
succeeding from AAP.

To turn "published" into "verified", scan a guest as a gate:

```
Windows Day 1 - 4 Compliance Scan  -e windows_compliance_fail_on_noncompliant=true
```

Audit-tag evidence capture and the `data.json` generator are the two Phase 3
tasks still open — see [ROADMAP.md](ROADMAP.md).

## Claude skills

Workflows in this repo are packaged as skills under `.claude/skills/`.

| Skill | Does |
|---|---|
| `first-time` | Validates every local prerequisite on a new machine |
| `collections-sync` | Pins, installs and verifies the Ansible collections |
| `dev-workflow` | The mandatory issue → branch → PR → merge cycle |
| `rhel9-containerdisk` | Builds the RHEL 9 CIS L1 containerDisk (Phase 1.7) |
| `windows-image-build` | Builds the Windows Server 2022 containerDisk (Phase 3) |

## Output

Generated `data.json` files are written to `output/<platform>/data.json` and
should be copied into the appropriate `golden_images/` path in `rego_policy_libraries`.

## CI / Automation

| Workflow | Trigger | What it does |
|---|---|---|
| [`lint.yml`](.github/workflows/lint.yml) | Push / PR to `main` | yamllint + ansible-lint on `playbooks/` and `inventories/` |
| [`containerdisk-rebuild.yml`](.github/workflows/containerdisk-rebuild.yml) | Monthly (1st, 06:00 UTC) + manual | Rebuilds the RHEL 9 CIS L1 containerDisk and pushes to Quay.io |

The scheduled rebuild keeps the containerDisk fresh with RHEL errata and CIS
benchmark updates without operator intervention. Trigger a manual rebuild from
the Actions tab or via `gh workflow run "Rebuild RHEL 9 CIS containerDisk"`.
See [docs/operations.md](docs/operations.md) for the full operational runbook.

## Related repositories

This repo is the **producer**. Both links below are consumers — the dependency
runs outward from here.

| Repo | Receives | Contract |
|---|---|---|
| [sales.demos](https://github.com/ericcames/sales.demos) | RHEL AMIs and the Windows Server 2022 containerDisk | AMI tags (`docs/design.md` §9); a containerdisk tag for Windows |
| [rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries) | `data.json` compliance data under `golden_images/` | `docs/design.md` §6 |

**The Windows golden image is deliberately split across two repos.** Building and
publishing it is [#24](https://github.com/ericcames/image.builder.pipeline/issues/24)
here; pointing a cluster at the published image is
[sales.demos#3](https://github.com/ericcames/sales.demos/issues/3). Both halves
have shipped — `sales.demos` consumes a published tag today. **The only thing
binding them is one string — a containerdisk tag in a private quay repo.**

That split is the rule in `CLAUDE.md`: *"Producer/consumer across repos is
intentional. Different audiences, different lifecycles."* Hardening and
compliance evidence belong here; running demos belongs there.

## Quay.io repositories

| Image | Repo | Why |
|---|---|---|
| `rhel9-cis-l1-golden` | **public** | Freely redistributable; consumers pull it with no pull secret |
| `win2k22-cis-l1-golden` | **private** | Microsoft licensing prohibits public redistribution of Windows media |

The private repository is entitled through an Unlimited Repositories
subscription, active to **2027-08-14**. Consumers need a pull secret;
`sales.demos` creates one in `playbooks/link_windows_image.yml`.

> This section used to be a troubleshooting write-up for the free plan's zero
> private-repo allowance, with a screenshot of the Quay warning banner and
> instructions to open a support case. That was resolved; the write-up outlived
> it. Operational detail for the private repo lives in
> [docs/operations.md](docs/operations.md).

## License

MIT — see [LICENSE](LICENSE)
