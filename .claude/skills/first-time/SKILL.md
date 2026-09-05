---
name: first-time
description: "First-time prerequisite check for the image.builder.pipeline repo. Validates the Red Hat Automation Hub token, installed collections, and AWS credential pattern. TRIGGER when: the user is new to this repo, asks how to get started, says prerequisites are missing, or hits errors about 401, 'couldn't resolve module/action', or an empty offline token. SKIP: if setup is already done and the user wants to run the pipeline — Eric runs AWS-touching playbooks himself."
---

# first-time

Validates every local prerequisite for working in this repo. Run once per
machine or new Claude session when something looks wrong.

## Orientation

Print this once at the start:

```
Checking image.builder.pipeline prerequisites.

  1. Red Hat Automation Hub token    ~/.ansible.cfg
  2. Ansible collections             via /collections-sync
  3. AWS credentials pattern         env vars (operator provides)

Nothing here touches AWS or Red Hat APIs — it is all local validation.
```

## Step 0 — Audit everything at once

Read-only. Run it all, then work only on what is missing.

```bash
# 1. ~/.ansible.cfg exists and has the rh_certified token
grep -q 'galaxy_server.rh_certified' ~/.ansible.cfg 2>/dev/null \
  && grep -A3 'galaxy_server.rh_certified' ~/.ansible.cfg | grep -qE '^token=.+' \
  && echo "OK       Hub token in ~/.ansible.cfg" \
  || echo "MISSING  Hub token in ~/.ansible.cfg"

# 2. NOT using the frozen leftover
test -f ~/.ansible/ansible.cfg \
  && echo "WARNING  ~/.ansible/ansible.cfg exists (frozen leftover — do NOT use it)" \
  || echo "OK       no ~/.ansible/ansible.cfg"

# 3. No project-local ansible.cfg
test -f ansible.cfg \
  && echo "PROBLEM  project-local ansible.cfg present — it shadows ~/.ansible.cfg" \
  || echo "OK       no project-local ansible.cfg"

# 4. Collections installed
ansible-galaxy collection list amazon.aws 2>/dev/null | grep -q amazon.aws \
  && echo "OK       amazon.aws collection" \
  || echo "MISSING  amazon.aws collection"

# 5. In the right directory
test -f playbooks/build_cis_image.yml \
  && echo "OK       in the image.builder.pipeline repo" \
  || echo "PROBLEM  wrong directory"
```

## Step 1 — Red Hat Automation Hub token

`~/.ansible.cfg` needs a `galaxy_server.rh_certified` section with a token.
This token does two jobs:

1. `ansible-galaxy collection install` uses it for Red Hat certified content
2. `build_cis_image.yml` reads it at runtime via an `ini` lookup to authenticate
   with the Image Builder API

```bash
grep -A3 'galaxy_server.rh_certified' ~/.ansible.cfg | grep -qE '^token=.+' \
  && echo "token present" || echo "no token"
```

If missing, get one from **console.redhat.com -> Automation Hub -> Connect to
Hub -> Load token**, then add to `~/.ansible.cfg`:

```ini
[galaxy_server.rh_certified]
url=https://console.redhat.com/api/automation-hub/content/published/
auth_url=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token=<your token>
```

**Use `~/.ansible.cfg`, not `~/.ansible/ansible.cfg`.** The latter is a stale
leftover on some machines with a different (expired) token. The playbook reads
from `~/.ansible.cfg`.

**Never create a project-local `ansible.cfg`.** Ansible picks one config file
and does not merge — a local one shadows `~/.ansible.cfg` and breaks everything.

## Step 2 — Collections

Delegate to the skill that owns this:

```
/collections-sync
```

This pins, installs, and verifies that installed versions match
`collections/requirements.yml`.

## Step 3 — AWS credentials pattern

The pipeline playbooks need four AWS values, all provided as environment
variables:

```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION
AWS_ACCOUNT_ID
```

**Eric provides these himself.** Do not paste credentials, do not try to
configure AWS from a Claude session, and do not store them anywhere in the repo.
The playbooks read them via `lookup('ansible.builtin.env', ...)` at runtime.

If a playbook fails with an AWS auth error, tell the user to check their
exported env vars — do not attempt to diagnose or fix AWS credentials.

## Step 4 — Validate

Confirm the token lookup resolves (does not require AWS or an API call):

```bash
python3 -c "
import configparser, os, sys
cfg = configparser.ConfigParser()
cfg.read(os.path.expanduser('~/.ansible.cfg'))
try:
    token = cfg.get('galaxy_server.rh_certified', 'token')
    if len(token) > 20:
        print('token lookup OK (%d chars)' % len(token))
    else:
        print('token looks too short'); sys.exit(1)
except Exception as e:
    print('token lookup failed:', e); sys.exit(1)
"
```

## When everything passes

Tell the user setup looks good. Point them at the CLAUDE.md and ROADMAP.md for
orientation on the pipeline's current state and what work is in progress.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `couldn't resolve module/action` | Collections not installed | `/collections-sync` |
| 401 from Red Hat SSO | Hub token missing, expired, or read from wrong file | Step 1 — check `~/.ansible.cfg` |
| `Red Hat offline token not found` | `~/.ansible.cfg` missing the `[galaxy_server.rh_certified]` section | Step 1 |
| Token lookup returns empty string | Token line exists but value is blank | Re-copy from console.redhat.com |
| `ansible-galaxy` 401 on certified content | `~/.ansible.cfg` shadowed by a project-local `ansible.cfg` | Delete the project-local file |
| AWS auth errors | Env vars not exported | Step 3 — Eric provides these |
