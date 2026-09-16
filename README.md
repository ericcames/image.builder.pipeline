# image.builder.pipeline

The image factory. It builds CIS-hardened machine images — and, just as
deliberately, the evidence that they *are* hardened.

Hardening an image is the straightforward half. Proving it stayed hardened is
the half that gets asked about with a customer in the room.

| | |
|---|---|
| **For** | Anyone who needs a hardened base image *and* the compliance evidence behind it |
| **Produces** | CIS L1 containerDisks and AMIs, a single-node OpenShift installer, and `data.json` policy data |
| **Docs** | **[Image Factory on the docs site](https://ericcames.github.io/sales.demos-docs/image-factory/)** — architecture, evidence, operations, and how it extends |
| **Status** | RHEL 9 and Windows Server 2022 shipping — see [What it produces](#-what-it-produces) |

**This repo is the producer**, and the dependency only ever runs outward:
[sales.demos](https://github.com/ericcames/sales.demos) consumes the images,
[rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries)
consumes the compliance data, and nothing here depends on either.

## 📦 What it produces

| Output | Where it goes | Evidence |
|---|---|---|
| **[RHEL 9 CIS L1 containerDisk](https://ericcames.github.io/sales.demos-docs/image-factory/rhel9/)** | `quay.io/zigfreed/rhel9-cis-l1-golden` — **published, public** | Hardened by Image Builder at compose time; rebuilt monthly |
| **[Windows 2022 CIS L1 containerDisk](https://ericcames.github.io/sales.demos-docs/image-factory/windows/)** | `quay.io/zigfreed/win2k22-cis-l1-golden` — **published, private** | **27 of 27** on a booted clone; the label is [gated by an offline read of the disk](https://ericcames.github.io/sales.demos-docs/image-factory/compliance-evidence/) |
| **[RHEL 9 CIS L1 AMI](https://ericcames.github.io/sales.demos-docs/image-factory/rhel9/)** | **published** to AWS, shared from Red Hat's account `463606842039` | OpenSCAP **98.07** against a 95 gate — 254 pass, 5 fail, all 5 documented exempt |
| **[Single-node OpenShift installer](https://ericcames.github.io/sales.demos-docs/image-factory/sno-kit/)** | **Not published — generated locally** | Booted on a NUC: OCP 4.22.13, all Day 0 operators `Succeeded`; stock RHCOS 186/188 |

> [!IMPORTANT]
> Only the first three are published. The SNO ISO is built on the machine that
> needs it, because the OpenShift pull secret is embedded in its Ignition
> config — so it can never be published. An installer *kit* image was designed
> and
> [decided against](https://ericcames.github.io/sales.demos-docs/image-factory/sno-kit/#why-this-is-not-published-to-quay)
> (#138): the kit is text already in this public repo, and nothing consumes it
> that needs a registry.

## 🚀 Getting started

🎯 **Consuming the images?** You do not need this repo. The AMIs and
containerDisks are published, and the only thing binding a consumer to this repo
is **one image tag**. Go to
[sales.demos](https://github.com/ericcames/sales.demos) — it points a cluster at
a published containerdisk and never builds one.

🛠️ **Building or publishing an image?** New machine, or a fresh clone? **Start
with the `first-time` skill.** It validates every local prerequisite and touches
no AWS or Red Hat API doing it:

```bash
git clone https://github.com/ericcames/image.builder.pipeline.git
cd image.builder.pipeline
claude .
# then:  /first-time
```

[`.claude/skills/first-time/SKILL.md`](.claude/skills/first-time/SKILL.md) is
written to be *run* as a skill, but its Step 0 audit is a plain shell block —
paste it into a terminal and work down the list by hand if you do not have
Claude Code.

### Prerequisites

- A Red Hat account with Image Builder access (console.redhat.com)
- The Red Hat offline token in `~/.ansible.cfg` under
  `[galaxy_server.rh_certified]` as `token=` — the same token as Automation Hub,
  and the one authoritative copy
- AWS credentials **in the environment**, for the AMI path only
- Collections: `ansible-galaxy collection install -r collections/requirements.yml -p ./collections`

> [!CAUTION]
> **Credentials go in the environment, never in a file.** There is no
> credentials file to create. A `docs/aws-environment.md` used to be documented
> here for "local notes"; it held a live key in plaintext, and the practice is
> retired. AWS credentials will move into a vault-encrypted `secrets.yml` when
> that work lands.

### Running a build

```bash
# RHEL 9 containerDisk — needs only the RH token and a Quay login
podman login quay.io
ansible-playbook playbooks/build_cis_containerdisk.yml

# RHEL 9 AMI — needs live AWS credentials
export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=<your_aws_account_id>
ansible-playbook -i inventories/sample/ playbooks/build_cis_image.yml
ansible-playbook -i inventories/sample/ playbooks/deploy_and_scan.yml
ansible-playbook -i inventories/sample/ playbooks/generate_policy_data.yml

# Windows 2022 — needs a KubeVirt sandbox cluster; refuses to run against demo
export K8S_AUTH_HOST=https://api.<cluster>:6443
export K8S_AUTH_API_KEY=<bearer-token>
export WINDOWS_ADMIN_PASSWORD=<password>
ansible-playbook playbooks/build_windows_image.yml
ansible-playbook playbooks/publish_windows_containerdisk.yml

# Single-node OpenShift installer ISO — local, never published
ansible-playbook playbooks/build_sno_installer.yml
```

Full runbook, failure modes and secret rotation:
[Operations](https://ericcames.github.io/sales.demos-docs/image-factory/operations/).

## 🧩 Extending it to another OS, benchmark or hypervisor

Every image here is a point in **OS × benchmark × target**, and the factory has
got further on some axes than others. The short version:

- **Hypervisor / cloud is the cheapest axis.** Image Builder emits `vsphere`,
  `azure`, `gcp` and `guest-image` from the same blueprint API — for a RHEL
  guest, a new target is one `image_type` value.
- **Benchmark is a string on RHEL and a flag on Windows.** What is *not* cheap
  is the exempt list: exemptions are specific to an OS, a benchmark and a
  target, and a new combination needs its own curated set with written reasons.
- **OS is the blocked one**, on something small: `build_cis_containerdisk.yml`
  hardcoded what `build_cis_image.yml` parameterised.

[**Extending it**](https://ericcames.github.io/sales.demos-docs/image-factory/extending/)
has the full table, names the exact variables, and ends with the known gaps —
including that Windows has no scheduled rebuild.

## 🧰 Claude skills

Workflows here are packaged as skills under `.claude/skills/`.

| Skill | Does |
|---|---|
| `first-time` | Validates every local prerequisite on a new machine |
| `collections-sync` | Pins, installs and verifies the Ansible collections |
| `dev-workflow` | The mandatory issue → branch → PR → merge cycle |
| `rhel9-containerdisk` | Builds the RHEL 9 CIS L1 containerDisk |
| `windows-image-build` | Builds the Windows Server 2022 containerDisk |
| `ami-build` | Builds the CIS L1 hardened RHEL AMI via Image Builder |

**These skills are only reachable from a session started here.** For anything
touching a cluster, start Claude in `sales.demos` instead — its `.mcp.json` is
project-scoped and this repo has no MCP servers. A session started there can
`cd` here and run these playbooks anyway, so starting there is strictly better
in one direction only. Open a second session here to use the skills.

## ⚙️ CI and automation

| Workflow | Trigger | What it does |
|---|---|---|
| [`lint.yml`](.github/workflows/lint.yml) | Push / PR to `main` | yamllint + ansible-lint |
| [`containerdisk-rebuild.yml`](.github/workflows/containerdisk-rebuild.yml) | Monthly (1st, 06:00 UTC) + manual | Rebuilds the RHEL 9 CIS L1 containerDisk and pushes to Quay.io |

The scheduled rebuild keeps the containerDisk current with RHEL errata and CIS
benchmark updates with nobody remembering to do it. It is also the **only**
scheduled build — the reason is credentials, and the consequence is in
[Extending it](https://ericcames.github.io/sales.demos-docs/image-factory/extending/#known-gaps-named).

```bash
gh workflow run "Rebuild RHEL 9 CIS containerDisk"
```

> [!NOTE]
> **Lint-green means nothing here.** CI does not execute a playbook. Every
> defect found during the Windows phase was found by running it; `ansible-lint`
> passed at the production profile through all of them.

## 🗂️ Quay.io repositories

| Image | Repo | Why |
|---|---|---|
| `rhel9-cis-l1-golden` | **public** | Freely redistributable; consumers pull it with no pull secret |
| `win2k22-cis-l1-golden` | **private** | Microsoft licensing prohibits public redistribution of Windows media |

The private repository is entitled through an Unlimited Repositories
subscription, active to **2027-08-14**. `publish_windows_containerdisk.yml`
asks the registry whether the repository is public and **refuses to publish
Windows media to a public one** — the licensing constraint is a guard in code,
not a note.

## 🔗 Related repositories

| Repo | Receives | Contract |
|---|---|---|
| [sales.demos](https://github.com/ericcames/sales.demos) | RHEL AMIs and both containerDisks | AMI tags (`docs/design.md` §9); a containerdisk tag (§10) |
| [rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries) | `data.json` under `golden_images/` | `docs/design.md` §6 |
| [sales.demos-docs](https://github.com/ericcames/sales.demos-docs) | This repo's documentation | The [Image Factory section](https://ericcames.github.io/sales.demos-docs/image-factory/) |

**The Windows golden image is deliberately split across two repos.** Building and
publishing it is [#24](https://github.com/ericcames/image.builder.pipeline/issues/24)
here; pointing a cluster at the published image is
[sales.demos#3](https://github.com/ericcames/sales.demos/issues/3). Both halves
have shipped, and **the only thing binding them is one string.**

That split is the rule in [`CLAUDE.md`](CLAUDE.md): *"Producer/consumer across
repos is intentional. Different audiences, different lifecycles."*

## 📚 Where everything else lives

| Question | Answer |
|---|---|
| How does any of this work? | [The docs site](https://ericcames.github.io/sales.demos-docs/image-factory/) |
| What is the cross-repo contract? | [`docs/design.md`](docs/design.md) — cited by section number from three repos |
| What is planned? | [`ROADMAP.md`](ROADMAP.md) |
| Why does a convention exist? | [`CLAUDE.md`](CLAUDE.md) |
| What changed and when? | `git log`, plus the [closed issues](https://github.com/ericcames/image.builder.pipeline/issues?q=is%3Aissue+is%3Aclosed). The per-PR changelog was retired in [#119](https://github.com/ericcames/image.builder.pipeline/issues/119); its history is [archived](https://ericcames.github.io/sales.demos-docs/reference/history/) |
| How do I contribute? | [`CONTRIBUTING.md`](CONTRIBUTING.md) |

## ⚖️ License

MIT — see [LICENSE](LICENSE)
