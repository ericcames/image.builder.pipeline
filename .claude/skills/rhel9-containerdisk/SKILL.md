---
name: rhel9-containerdisk
description: "Build and publish the CIS-hardened RHEL 9 containerDisk for OpenShift Virtualization. Runs playbooks/build_cis_containerdisk.yml — uses the Red Hat Image Builder API with guest-image type, wraps the qcow2 as a containerDisk, pushes to quay.io/zigfreed/rhel9-cis-l1-golden. TRIGGER when: the user asks to build or rebuild the RHEL 9 containerDisk, asks about Phase 1.7, asks how RHEL images get to OpenShift Virt, hits errors from the guest-image compose or podman push, or wants to validate the Image Builder API response for qcow2 output. SKIP: if the user wants the AMI pipeline (build_cis_image.yml), the Windows containerDisk (windows-image-build skill), or the consumer side in sales.demos."
---

# rhel9-containerdisk

Phase 1.7 of the roadmap: the same CIS L1 RHEL 9 image the AMI pipeline
produces, wrapped as a containerDisk for OpenShift Virtualization.

**This is the producer half.** The consumer — pointing a cluster's
DataImportCron at the published tag — is a separate PR in
[sales.demos](https://github.com/ericcames/sales.demos). The contract is one
string: `quay.io/zigfreed/rhel9-cis-l1-golden:<date>`.

## How it works

```
Red Hat Image Builder API
  image_type: "guest-image"  (not "aws")
        |
        v  qcow2 download
  Containerfile: FROM scratch / COPY disk.qcow2 /disk/disk.img
        |
        v  podman build + push
  quay.io/zigfreed/rhel9-cis-l1-golden:YYYYMMDD-HHMM
```

Same CIS L1 profile and package customizations as the AMI. Image Builder runs
OpenSCAP at build time. No AWS credentials needed — only the RH offline token
and a Quay login.

## Preflight

```bash
# 1. RH offline token
python3 -c "
import configparser, os
cfg = configparser.ConfigParser()
cfg.read(os.path.expanduser('~/.ansible.cfg'))
token = cfg.get('galaxy_server.rh_certified', 'token')
print('OK       RH token (%d chars)' % len(token)) if len(token) > 20 \
    else print('FAIL     token too short')
"

# 2. podman available
podman --version

# 3. Quay login exists
podman login --get-login quay.io \
  && echo "OK       Quay login" \
  || echo "MISSING  run: podman login quay.io"

# 4. In the right directory
test -f playbooks/build_cis_containerdisk.yml \
  && echo "OK       in the image.builder.pipeline repo" \
  || echo "FAIL     wrong directory"
```

## Validate API response (first time or after changes)

Before a full run, validate the guest-image compose response structure. This
starts a real compose (~15-30 min) but lets you see the raw JSON to confirm
`wait_for_compose.py` parses it correctly.

```bash
python3 - <<'PY'
import configparser, json, os, urllib.parse, urllib.request

cfg = configparser.ConfigParser()
cfg.read(os.path.expanduser("~/.ansible.cfg"))
offline_token = cfg.get("galaxy_server.rh_certified", "token")

# Exchange for access token
body = urllib.parse.urlencode({
    "grant_type": "refresh_token",
    "client_id": "cloud-services",
    "refresh_token": offline_token,
}).encode()
req = urllib.request.Request(
    "https://sso.redhat.com/auth/realms/redhat-external"
    "/protocol/openid-connect/token",
    data=body,
    headers={"Content-Type": "application/x-www-form-urlencoded"},
    method="POST",
)
access_token = json.load(
    urllib.request.urlopen(req, timeout=30)
)["access_token"]
print(f"OK  access token ({len(access_token)} chars)")

# Start guest-image compose
compose_body = json.dumps({
    "distribution": "rhel-9",
    "image_requests": [{
        "architecture": "x86_64",
        "image_type": "guest-image",
        "upload_request": {"type": "aws.s3", "options": {}}
    }],
    "customizations": {
        "packages": ["aide", "firewalld", "systemd-journal-remote"],
        "openscap": {
            "profile_id":
                "xccdf_org.ssgproject.content_profile_cis_server_l1"
        }
    }
}).encode()
req = urllib.request.Request(
    "https://console.redhat.com/api/image-builder/v1/compose",
    data=compose_body,
    headers={
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    },
    method="POST",
)
compose_id = json.load(
    urllib.request.urlopen(req, timeout=30)
)["id"]
print(f"OK  compose started: {compose_id}")
print(f"\nPoll with:")
print(f"  RH_OFFLINE_TOKEN='<token>' python3 "
      f"playbooks/scripts/wait_for_compose.py {compose_id}")
print(f"\nOr check raw response:")
print(f"  curl -s -H 'Authorization: Bearer <token>' "
      f"https://console.redhat.com/api/image-builder/v1"
      f"/composes/{compose_id} | python3 -m json.tool")
PY
```

Then poll with `wait_for_compose.py`:

```bash
OFFLINE_TOKEN=$(python3 -c "
import configparser, os
cfg = configparser.ConfigParser()
cfg.read(os.path.expanduser('~/.ansible.cfg'))
print(cfg.get('galaxy_server.rh_certified', 'token'))
")

RH_OFFLINE_TOKEN="$OFFLINE_TOKEN" python3 \
  playbooks/scripts/wait_for_compose.py <compose-id> \
  | python3 -m json.tool
```

Expected output for guest-image:

```json
{
    "compose_id": "<uuid>",
    "image_url": "https://...",
    "image_type": "guest-image",
    "status": "success"
}
```

If the field path is wrong, fix the `options.get("url")` line in
`wait_for_compose.py` (around line 115) to match the actual response.

## Run

**Eric runs this himself** — it hits the Red Hat Image Builder API and pushes
to Quay.

```bash
# QUAY_REPO defaults to quay.io/zigfreed/rhel9-cis-l1-golden
ansible-playbook playbooks/build_cis_containerdisk.yml
```

Override the Quay repo if needed:

```bash
QUAY_REPO=quay.io/zigfreed/rhel9-cis-l1-golden \
  ansible-playbook playbooks/build_cis_containerdisk.yml
```

The playbook takes ~20-35 minutes: Image Builder compose (~15-25 min), qcow2
download (~2 GB, ~2-5 min), podman build + push (~3-5 min).

## Verify

```bash
# 1. Build output written
cat output/rhel9-containerdisk/build_output.json | python3 -m json.tool

# 2. Image on Quay with correct OCI labels
podman pull quay.io/zigfreed/rhel9-cis-l1-golden:<tag>
podman inspect quay.io/zigfreed/rhel9-cis-l1-golden:<tag> \
  | python3 -c "
import json, sys
labels = json.load(sys.stdin)[0].get('Config', {}).get('Labels', {})
for k in sorted(labels):
    print(f'  {k}: {labels[k]}')
"

# 3. Cleanup happened (no leftover qcow2 or Containerfile)
ls -la output/rhel9-containerdisk/
```

Expected OCI labels:

| Label | Value |
|---|---|
| `com.redhat.cis.pipeline` | `image-builder-pipeline` |
| `com.redhat.cis.os` | `rhel9` |
| `com.redhat.cis.level` | `L1` |
| `com.redhat.cis.compose-id` | Image Builder compose UUID |
| `org.opencontainers.image.created` | ISO 8601 timestamp |
| `org.opencontainers.image.source` | `https://github.com/ericcames/image.builder.pipeline` |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| 401 from Red Hat SSO | Hub token missing or expired in `~/.ansible.cfg` | Rotate at console.redhat.com -> Automation Hub -> Connect to Hub |
| `podman login --get-login quay.io` fails | No Quay login | `podman login quay.io` |
| `wait_for_compose.py` exits 3 with "neither ami nor url" | Image Builder API response structure changed | Poll manually with curl, check `image_status.upload_status.options`, fix the key in `wait_for_compose.py` |
| Compose fails at Image Builder | CIS profile or package not available for the distro | Check `stderr` from `wait_for_compose.py` for the Image Builder error |
| `podman push` denied | Quay repo does not exist or login expired | Create `rhel9-cis-l1-golden` repo on quay.io, re-login |
| `get_url` timeout on qcow2 download | Presigned URL expired (compose took too long) | Re-run the playbook; the URL is valid for limited time after compose |

## Where this sits

1. **This skill** — produce the RHEL 9 containerDisk, push to Quay.
2. `sales.demos` — consumer side: `link_rhel9_image.yml` creates a
   DataImportCron pointing at the published tag.
3. `docs/design.md` §10 — the containerDisk contract.
