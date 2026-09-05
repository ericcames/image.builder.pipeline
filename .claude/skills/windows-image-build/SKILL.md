---
name: windows-image-build
description: "Build the CIS-hardened Windows Server 2022 golden image on OpenShift Virtualization, for publication as a containerDisk that sales.demos consumes. Covers acquiring the evaluation ISO, the unattended build, and the 180-day expiry that has to travel with the artifact. Runs playbooks/build_windows_image.yml. TRIGGER when: the user asks to build, rebuild or publish the Windows image, asks about the Windows containerDisk, autounattend, virtio drivers or sysprep, asks where the Windows ISO comes from, asks whether the evaluation media has expired, or hits a build that hangs on the edition-selection screen. SKIP: if the user wants to point a cluster AT an already-published image — that is the consumer half, sales.demos#3 and its ocpvirt-windows-image skill — or wants the RHEL AMI pipeline, which is build_cis_image.yml."
---

# windows-image-build

Phase 3 of the roadmap: a CIS-hardened Windows Server 2022 image, published once
as a containerDisk so it outlives any cluster.

**This is the producer half.** The consumer — pointing an OpenShift
Virtualization cluster at the published tag — lives in
[sales.demos#3](https://github.com/ericcames/sales.demos/issues/3) and already
ships. The contract between them is one string: a containerdisk tag in a private
quay repo.

## Where the work is

| | Status |
|---|---|
| PR 1 — unattended build on the cluster | **Merged** (#29) |
| PR 2 — `ansible-lockdown/Windows-2022-CIS` hardening + audit evidence | Not started |
| PR 3 — export, containerdisk wrap, `podman push`, `design.md` §10 | Not started |

Tracked in [#24](https://github.com/ericcames/image.builder.pipeline/issues/24).

## Why this builds on a cluster and not on a laptop

[#21](https://github.com/ericcames/image.builder.pipeline/issues/21) flags *"a
local libvirt/KVM scan path — new hypervisor dependency"* as its High-risk item.
**A KubeVirt cluster is a hypervisor**, so building there avoids that dependency
instead of incurring it, and the image is exercised by KubeVirt before any
consumer sees it — which a laptop-built qcow2 never is.

**No operator is installed.** The playbook drives plain `VirtualMachine` objects
with `kubernetes.core`, exactly as this repo drives EC2 with `amazon.aws`. Red
Hat's `windows-efi-installer` Tekton pipeline would do the same job but would
mean installing OpenShift Pipelines into a cluster the *consumer* repo owns.

## The media, and the clock

Windows evaluation media is **not** fetched by the playbook: Microsoft's
Evaluation Center requires accepting terms, so a scripted download is fragile and
beside the point. Fetch it once.

```bash
mkdir -p ~/Downloads/windows-iso && cd ~/Downloads/windows-iso
curl -L --fail -C - -o SERVER_EVAL_x64FRE_en-us.iso \
  "https://go.microsoft.com/fwlink/p/?LinkID=2195280"
```

That fwlink is Microsoft's own entry point and redirects to
`software-static.download.prss.microsoft.com`. Verified values:

| | |
|---|---|
| Size | `5,044,094,976` bytes |
| SHA256 | `3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325` |
| Path expected by this skill | `~/Downloads/windows-iso/SERVER_EVAL_x64FRE_en-us.iso` |

**`~/iso` is a regular file on this machine, not a directory** — do not use it as
a download target.

### The 180-day clock is the thing people forget

Evaluation media expires 180 days **from installation**, not from download. An
expired Windows guest nags, then **shuts down hourly** — which will happen
mid-demo if nobody wrote the date down. So:

- `windows_eval_expires` is **required** by the playbook and asserted. It is not
  optional and there is no default, deliberately.
- It is stamped on the build VM as the `image-factory/eval-expires` label and
  printed at the end of the run.
- **It has to reach the demo run-sheet in `sales.demos`**, because that is where
  someone reads it before standing in front of a customer. A VM label in a
  namespace that no longer exists helps nobody.
- Rebuild before it lapses. Publishing a new date-tagged containerdisk and
  repointing `quay_windows_image` is the whole update path.

### `windows_image_name` must match the ISO exactly

The `<MetaData>` key `/IMAGE/NAME` in `autounattend.xml` is matched against the
image names inside `sources/install.wim` **on the specific ISO you downloaded**.
Get it wrong and Windows Setup stops on the edition-selection screen — which
looks like a hang, not a mismatch, because there is no console output to read.

Images in the ISO above:

```
  INDEX=1  NAME='Windows Server 2022 SERVERSTANDARDCORE'    Standard Evaluation
  INDEX=2  NAME='Windows Server 2022 SERVERSTANDARD'        Standard Evaluation (Desktop Experience)
  INDEX=3  NAME='Windows Server 2022 SERVERDATACENTERCORE'  Datacenter Evaluation
  INDEX=4  NAME='Windows Server 2022 SERVERDATACENTER'      Datacenter Evaluation (Desktop Experience)
```

The playbook defaults to `Windows Server 2022 SERVERSTANDARD` — index 2, the
Desktop Experience variant. `EDITIONID` on every image is `ServerStandardEval` /
`ServerDatacenterEval`, which is how you can tell evaluation media apart from
licensed media at a glance.

To re-check after downloading a different ISO:

```bash
7z e -so ~/Downloads/windows-iso/SERVER_EVAL_x64FRE_en-us.iso sources/install.wim \
  > /tmp/install.wim && python3 playbooks/scripts/wim_images.py /tmp/install.wim
```

## Preflight Check

```bash
# 1. The ISO is present and the right size
stat -c '%n %s bytes' ~/Downloads/windows-iso/SERVER_EVAL_x64FRE_en-us.iso

# 2. Which cluster? This MUST be sandbox — the playbook refuses demo.
echo "${K8S_AUTH_HOST:-<unset>}"

# 3. Credentials are exported (design.md §4 — nothing is stored in this repo)
[ -n "$K8S_AUTH_API_KEY" ] && echo "token set" || echo "K8S_AUTH_API_KEY missing"
[ -n "$WINDOWS_ADMIN_PASSWORD" ] && echo "admin password set" || echo "WINDOWS_ADMIN_PASSWORD missing"

# 4. virtctl, the one local tool the build needs
virtctl version --client >/dev/null 2>&1 && echo "virtctl ok" || echo "virtctl missing"

# 5. Collections
ansible-galaxy collection list 2>/dev/null | grep kubernetes.core
```

## Run

**Eric runs this himself** — it touches a real cluster and takes about
forty-five minutes.

```bash
export K8S_AUTH_HOST="https://api.<sandbox-cluster>:6443"
export K8S_AUTH_API_KEY="<token>"
export WINDOWS_ADMIN_PASSWORD="<password baked into the image>"

ansible-playbook -i inventories/sample/ playbooks/build_windows_image.yml \
  -e windows_iso_path=~/Downloads/windows-iso/SERVER_EVAL_x64FRE_en-us.iso \
  -e windows_eval_expires=$(date -u -d '+180 days' +%Y-%m-%d)
```

And the teardown, which ships with it:

```bash
ansible-playbook -i inventories/sample/ playbooks/build_windows_image.yml \
  -e windows_build_state=absent
```

## Verify against the cluster, not the recap

```bash
oc get vm,vmi,dv -n image-factory-windows
oc get vmi win2k22-build -n image-factory-windows \
  -o jsonpath='{.status.guestOSInfo}{"\n"}'
oc get vm win2k22-build -n image-factory-windows \
  -o jsonpath='{.status.printableStatus}{"\n"}'
```

A finished build reports `Stopped` — sysprep shuts the guest down. Before that,
`guestOSInfo` being populated is the signal that Setup finished and the QEMU
guest agent came up.

Watch the install itself over VNC if it appears stuck:

```bash
virtctl vnc win2k22-build -n image-factory-windows
```

## Reading the result

| Symptom | Cause | What to turn |
|---|---|---|
| Setup sits on "Select the operating system" | `windows_image_name` does not match a WIM image name | Re-read the image list above; pass `-e windows_image_name='<exact name>'` |
| "No drives were found" | virtio storage driver not loaded in WinPE | `-e windows_disk_bus=sata` is the documented fallback; then install virtio inside the guest |
| VM never leaves `Provisioning` | The blank DataVolume or the ISO DataVolume is still importing | `oc get dv -n image-factory-windows`; the ISO upload is ~4.7 GB |
| `virtctl image-upload` fails | `cdi-uploadproxy` Route unreachable | `oc get route cdi-uploadproxy -n openshift-cnv` |
| Build refuses to start, naming the demo cluster | `K8S_AUTH_HOST` points at demo | Intentional. Builds run on sandbox. |

## Where this sits

1. **This skill** — build the image on sandbox.
2. PR 2 — harden it with `ansible-lockdown/Windows-2022-CIS`, capture audit evidence.
3. PR 3 — export, wrap as a containerdisk, push to private quay.
4. `sales.demos` `ocpvirt-windows-image` — point a cluster at the published tag.
