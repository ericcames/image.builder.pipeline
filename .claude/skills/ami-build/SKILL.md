---
name: ami-build
description: "Build a CIS L1 hardened RHEL AMI via Red Hat Image Builder, tag it for downstream consumers, and save the build output. This is the repo's original pipeline (Phase 1). Preflight only — Eric runs the AWS-touching playbook himself. Runs playbooks/build_cis_image.yml. TRIGGER when: the user asks to build a CIS-hardened AMI, wants to create a new golden image for AWS, asks about the Image Builder compose pipeline, or wants to know what prerequisites are needed. SKIP: if the user wants the containerDisk (RHEL 9 or Windows) — those are rhel9-containerdisk and windows-image-build — or wants to deploy/scan an existing AMI, which is deploy_and_scan.yml."
---

# ami-build

Build a CIS L1 hardened RHEL AMI via Red Hat's hosted Image Builder service.
The compose takes **15–25 minutes** depending on service load.

This skill contains **no logic**. All the work is in
[`playbooks/build_cis_image.yml`](../../../playbooks/build_cis_image.yml).

## What it does

1. Exchanges the Red Hat offline token for an access token via SSO.
2. Submits a compose request to `console.redhat.com/api/image-builder/v1` with
   the CIS L1 OpenSCAP profile and the required packages (aide, firewalld,
   systemd-journal-remote).
3. Waits for the compose to complete — `scripts/wait_for_compose.py` handles
   token refresh because composes outlive the 15-minute access token.
4. Tags the resulting AMI with the contract tags downstream consumers filter on.
5. Saves `build_output.json` to `output/<platform>/`.

## This is preflight only

**Eric runs the AWS-touching playbook himself.** This skill validates that
all prerequisites are in place and explains the process. Do not run the
playbook without explicit authorization — it creates AWS resources.

## AMI tagging — the contract with downstream consumers

Consumers (sales.demos, DC1) discover AMIs by tag, not by name:

| Tag | Value | Purpose |
|---|---|---|
| `Pipeline` | `image-builder-pipeline` | Distinguishes these from any other AMI |
| `OS` | `rhel9` or `rhel8` | Target platform |
| `CIS-Level` | `L1` | Hardening profile |
| `BuildDate` | ISO 8601 | When it was built |
| `ComposeID` | UUID | Traceability back to Image Builder |
| `Name` | `<os>-cis-l1-<YYYYMMDD-HHMM>` | Human-readable, not a discovery key |

Breaking the tag contract breaks consumers' `data "aws_ami"` filters.

## Preflight Check

```bash
test -f ~/.ansible.cfg \
  && echo "✅ ~/.ansible.cfg exists" \
  || echo "❌ ~/.ansible.cfg not found"

grep -q 'galaxy_server.rh_certified' ~/.ansible.cfg 2>/dev/null \
  && grep -A3 'galaxy_server.rh_certified' ~/.ansible.cfg | grep -qE '^token=.+' \
  && echo "✅ Red Hat offline token present" \
  || echo "❌ Red Hat offline token missing — https://console.redhat.com/ansible/automation-hub/token"

test -n "$AWS_ACCESS_KEY_ID" \
  && echo "✅ AWS_ACCESS_KEY_ID set" \
  || echo "❌ AWS_ACCESS_KEY_ID not set"

test -n "$AWS_SECRET_ACCESS_KEY" \
  && echo "✅ AWS_SECRET_ACCESS_KEY set" \
  || echo "❌ AWS_SECRET_ACCESS_KEY not set"

test -n "$AWS_ACCOUNT_ID" \
  && echo "✅ AWS_ACCOUNT_ID set" \
  || echo "❌ AWS_ACCOUNT_ID not set — the compose shares the AMI with this account"

python3 -c "import boto3" 2>/dev/null \
  && echo "✅ boto3 available" \
  || echo "❌ boto3 not installed — pip install boto3"

command -v ansible-playbook >/dev/null \
  && echo "✅ ansible-playbook $(ansible-playbook --version | head -1)" \
  || echo "❌ ansible-playbook not found"
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `TARGET_PLATFORM` (env var) | `rhel9` | Which OS to build — `rhel9` or `rhel8` |
| `AWS_DEFAULT_REGION` (env var) | `us-east-1` | AWS region for the AMI |
| `AWS_ACCOUNT_ID` (env var) | — | Account to share the AMI with |

## Run (Eric only)

```bash
TARGET_PLATFORM=rhel9 ansible-playbook -i localhost, playbooks/build_cis_image.yml
```

The `-i localhost,` is required — the playbook runs against localhost with
`connection: local`.

## What comes out

`output/<platform>/build_output.json`:

```json
{
  "compose_id": "<uuid>",
  "ami_id": "ami-<id>",
  "region": "us-east-1",
  "platform": "rhel9",
  "cis_profile": "xccdf_org.ssgproject.content_profile_cis_server_l1",
  "build_date": "<ISO 8601>"
}
```

## Next step

After the build completes:

```bash
ansible-playbook -i inventories/<customer>-<platform>/ playbooks/deploy_and_scan.yml
```

This deploys an EC2 instance from the new AMI, runs an OpenSCAP scan, and
produces the `data.json` compliance report for `rego_policy_libraries`.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `Red Hat offline token not found` | Token not in `~/.ansible.cfg` | Add it under `[galaxy_server.rh_certified]` |
| Compose status stays `pending` for > 30 min | Image Builder service backlog | Normal during peak hours; the wait helper handles it |
| `InvalidClientTokenId` or `AuthFailure` | AWS credentials invalid or expired | Refresh `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` |
| `AccessDenied` on `ec2:CreateTags` | IAM permissions insufficient | The tagger needs `ec2:CreateTags` on the AMI resource |
| Token refresh fails during compose wait | SSO endpoint unreachable | Check network; the helper retries but cannot recover from a sustained outage |

Never paste AWS credentials, Red Hat tokens, or account IDs into a commit
message, issue, or PR. This repo is public.
