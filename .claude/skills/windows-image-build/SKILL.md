---
name: windows-image-build
description: "Build the CIS-hardened Windows Server 2022 golden image on OpenShift Virtualization, for publication as a containerDisk that sales.demos consumes. Covers where the media comes from, the unattended build, and the 180-day expiry that has to travel with the artifact. Runs playbooks/build_windows_image.yml. TRIGGER when: the user asks to build, rebuild or publish the Windows image, asks about the Windows containerDisk, autounattend, virtio drivers or sysprep, asks where the Windows ISO comes from, asks whether the evaluation media has expired, hits a build that hangs on the edition-selection screen, or finds one sitting at \"Press any key to boot from CD or DVD\". SKIP: if the user wants to point a cluster AT an already-published image — that is the consumer half, sales.demos#3 and its ocpvirt-windows-image skill — or wants the RHEL AMI pipeline, which is build_cis_image.yml."
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
| No keypress — re-master the ISO onto `efisys_noprompt.bin` | **Merged** ([#40](https://github.com/ericcames/image.builder.pipeline/issues/40)) |
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

**The cluster fetches the ISO, not this machine.** `windows_iso_source` defaults
to `url` and CDI imports straight from Microsoft's fwlink. Measured (#36):
**~246 MiB/s cluster-side against ~1 MiB/s uploading from a laptop** — 25 seconds
against about 75 minutes for the same 4.7 GB. There is nothing to download by
hand.

That fwlink redirects to `software-static.download.prss.microsoft.com`. Verified
values, pinned as `windows_iso_sha256` and checked before the media is used:

| | |
|---|---|
| URL | `https://go.microsoft.com/fwlink/p/?LinkID=2195280` |
| Size | `5,044,094,976` bytes |
| SHA256 | `3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325` |

The `upload` path remains for a cluster with no egress, and only then do you
need a local copy:

```bash
mkdir -p ~/Downloads/windows-iso && cd ~/Downloads/windows-iso
curl -L --fail -C - -o SERVER_EVAL_x64FRE_en-us.iso \
  "https://go.microsoft.com/fwlink/p/?LinkID=2195280"

ansible-playbook -i inventories/sample/ playbooks/build_windows_image.yml \
  -e windows_iso_source=upload -e windows_iso_remaster=false \
  -e windows_iso_path=~/Downloads/windows-iso/SERVER_EVAL_x64FRE_en-us.iso \
  -e windows_eval_expires=$(date -u -d '+180 days' +%Y-%m-%d)
```

**`~/iso` is a regular file on this machine, not a directory** — do not use it as
a download target.

### Nobody has to press a key ([#40](https://github.com/ericcames/image.builder.pipeline/issues/40))

The stock ISO's UEFI boot image asks **"Press any key to boot from CD or DVD"**
with a ~5 second timeout, and when nobody answers, the console just sits there —
so a build that needs a human is indistinguishable from a build that is merely
slow. It cost a wasted 25-minute run before anyone noticed.

Microsoft ships `efisys_noprompt.bin` beside `efisys.bin` for exactly this. A pod
on the cluster fetches the ISO, verifies the checksum, and **overwrites the El
Torito boot image with the no-prompt twin**, then serves the result over HTTP;
CDI imports from that Service instead of from Microsoft. **Only the URL
differs** — the import path, the DataVolume, the VM and `autounattend.xml` are
the ones already verified.

**It is a byte-exact patch, not a rebuild** ([#44](https://github.com/ericcames/image.builder.pipeline/issues/44)).
The two boot images are the same size on this medium (1,474,560), and the hidden
El Torito image is a byte-identical copy of `efisys.bin` — so 720 sectors are
overwritten at one LBA and **the UDF filesystem is left exactly as Microsoft
shipped it**. Nothing is written until the bytes at the computed address are
proved to be the prompting image, so a misread catalogue fails rather than
corrupts.

**The medium is UDF, and that is why it needs `guestfish`.** `sources/install.wim`
is 4,340,202,461 bytes — past ISO 9660's 4 GiB single-extent limit — so the ISO
9660 tree is a stub holding one 135-byte file. `xorriso` reads with libisofs,
which has no UDF support; the first attempt at this used it and extracted one
node. libguestfs boots a kernel that *does* have a UDF driver, which is why Red
Hat's `modify-windows-iso-file` uses it and asks for `devices.kubevirt.io/kvm`.

- It is on by default. `-e windows_iso_remaster=false` returns you to the stock
  ISO and a keypress.
- It needs `windows_iso_source=url`, and says so rather than ignoring you: the
  pod fetches from `windows_iso_url` and cannot re-master a file that exists
  only on your laptop.
- The DataVolume records which media it holds as
  `image-factory/iso-variant: noprompt|stock`. **A `Succeeded` import of the
  wrong variant is re-imported** — phase alone cannot tell a re-mastered disk
  from a prompting one, and both report success.
- The pod runs three stages, because no single image can do all of it: `fetch`
  (curl + checksum, on `tekton-tasks` — the guestfish image ships **no CA
  bundle**), `remaster` (guestfish + the KVM device), then `serve` (python3,
  which the guestfish image also lacks). The KVM device is an extended resource
  from KubeVirt's device plugin, **not** a privileged securityContext — the pod
  still runs under `restricted-v2` as an arbitrary non-root UID.
- The pod, its Service, its ConfigMap and its scratch PVC are deleted as soon as
  the import succeeds.

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
image names inside `sources/install.wim` **on the specific ISO the cluster
imports** — which is pinned, both as `windows_iso_url` and as
`windows_iso_sha256`, so the list below holds until someone changes one of them.
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

To re-check after pointing `windows_iso_url` somewhere else — the only reason to
fetch a copy by hand:

```bash
curl -L --fail -o /tmp/win.iso "<the new windows_iso_url>"
7z e -so /tmp/win.iso sources/install.wim > /tmp/install.wim \
  && python3 playbooks/scripts/wim_images.py /tmp/install.wim
```

## Preflight Check

```bash
# 1. The cluster can reach Microsoft's fwlink (it, not you, fetches the media)
curl -sSI -o /dev/null -w '%{http_code}\n' -L "https://go.microsoft.com/fwlink/p/?LinkID=2195280"

# 2. Which cluster? This MUST be sandbox — the playbook refuses demo.
echo "${K8S_AUTH_HOST:-<unset>}"

# 3. Credentials are exported (design.md §4 — nothing is stored in this repo)
[ -n "$K8S_AUTH_API_KEY" ] && echo "token set" || echo "K8S_AUTH_API_KEY missing"
[ -n "$WINDOWS_ADMIN_PASSWORD" ] && echo "admin password set" || echo "WINDOWS_ADMIN_PASSWORD missing"

# 4. virtctl — needed only on the windows_iso_source=upload path
virtctl version --client >/dev/null 2>&1 && echo "virtctl ok" || echo "virtctl missing"

# 5. Collections
ansible-galaxy collection list 2>/dev/null | grep kubernetes.core
```

## Run

**Eric runs this himself** — it touches a real cluster and takes about thirty
minutes.

```bash
export K8S_AUTH_HOST="https://api.<sandbox-cluster>:6443"
export K8S_AUTH_API_KEY="<token>"
export WINDOWS_ADMIN_PASSWORD="<password baked into the image>"

ansible-playbook -i inventories/sample/ playbooks/build_windows_image.yml \
  -e windows_eval_expires=$(date -u -d '+180 days' +%Y-%m-%d)
```

**Nothing to watch**, which is what #40 bought. Roughly: re-master a few
minutes, import about two, install about twenty. Anything much past thirty
minutes is stuck rather than slow — start with the re-master pod's log, then the
VNC console.

And the teardown, which ships with it:

```bash
ansible-playbook -i inventories/sample/ playbooks/build_windows_image.yml \
  -e windows_build_state=absent
```

## Verify against the cluster, not the recap

```bash
oc get vm,vmi,dv -n image-factory-windows

# Which media the build actually used. 'noprompt' is a re-mastered import;
# anything else means someone will have to press a key.
oc get dv win2k22-build-iso -n image-factory-windows \
  -o jsonpath='{.metadata.annotations.image-factory/iso-variant}{"\n"}'
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
| VM never leaves `Provisioning` | The blank DataVolume or the ISO DataVolume is still importing — and on the default path the ISO DataVolume waits on the re-master pod before it can start | `oc get dv -n image-factory-windows`, then `oc get pod win2k22-build-remaster -n image-factory-windows`. 4.7 GB in and 4.7 GB out |
| `virtctl image-upload` fails | `cdi-uploadproxy` Route unreachable | `oc get route cdi-uploadproxy -n openshift-cnv` |
| Build refuses to start, naming the demo cluster | `K8S_AUTH_HOST` points at demo | Intentional. Builds run on sandbox. |
| Console sits at "Press any key to boot from CD or DVD" | The import holds stock media, not re-mastered | Check the `iso-variant` annotation above; re-run with `windows_iso_remaster=true` |
| Playbook stops on the re-master with pod logs attached | The re-master failed — bad checksum, no `efisys_noprompt.bin`, boot images of unequal size, or the bytes at the El Torito address were not the prompting image | Both initContainer logs are in the failure. The pod is left in place; `oc logs win2k22-build-remaster -c fetch` and `-c remaster` |
| Re-master pod never becomes Ready | Still downloading (`-c fetch`), or libguestfs is booting its appliance (`-c remaster`) | `oc logs -f win2k22-build-remaster -c fetch -n image-factory-windows` |
| Re-master fails with "the bytes at LBA … are not efi/microsoft/boot/efisys.bin" | A different medium, laid out differently | Deliberate refusal, not a bug. Nothing was written. Re-check `windows_iso_url` and `windows_iso_sha256` |

## Where this sits

1. **This skill** — build the image on sandbox.
2. PR 2 — harden it with `ansible-lockdown/Windows-2022-CIS`, capture audit evidence.
3. PR 3 — export, wrap as a containerdisk, push to private quay.
4. `sales.demos` `ocpvirt-windows-image` — point a cluster at the published tag.
