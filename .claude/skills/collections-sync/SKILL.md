---
name: collections-sync
description: "Pin, install, and verify Ansible collections in collections/requirements.yml. TRIGGER when: the user asks to install or update collections, add a collection, pin or bump a version, or a playbook fails with 'couldn't resolve module/action' or a collection-version error. SKIP: if the user is adding a Python package, or only wants to run the CI lint gate."
---

# collections-sync

Keeps `collections/requirements.yml` honest: every collection pinned to an
exact version, installed to the recommended path, and verified to match.

This skill has **no playbook** — it touches the laptop's collection path, never
a remote environment.

## Rules

1. **Every collection is pinned to an exact version. Nothing floats.** A
   floating version means two machines resolve different code.
2. **Pins are set to versions that were actually run**, not the newest
   published. Bump deliberately, re-run the affected playbook, then commit.
3. **Collections install to `~/.ansible/collections` only.** Never into the repo.
4. **Never create a project-local `ansible.cfg`.** It shadows `~/.ansible.cfg`
   and breaks certified content installs.

## Preflight

```bash
# 1. ~/.ansible.cfg has a real Automation Hub token
grep -q 'galaxy_server.rh_certified' ~/.ansible.cfg 2>/dev/null \
  && grep -A3 'galaxy_server.rh_certified' ~/.ansible.cfg | grep -qE '^token=.+' \
  && echo "OK  ~/.ansible.cfg has an rh_certified token" \
  || echo "FAIL  ~/.ansible.cfg missing an rh_certified token — certified collections will not install"

# 2. requirements.yml exists
test -s collections/requirements.yml \
  && echo "OK  collections/requirements.yml" \
  || echo "FAIL  collections/requirements.yml missing"

# 3. Collections are not vendored into the repo
test -d collections/ansible_collections \
  && echo "FAIL  collections vendored in the repo — they belong in ~/.ansible/collections" \
  || echo "OK  no collections vendored in the repo"
```

## Audit: pinned vs installed

Run this first, always. It is read-only and tells you whether there is anything
to do.

```bash
python3 - <<'PY'
import subprocess, yaml, sys, re
req = yaml.safe_load(open("collections/requirements.yml"))["collections"]

out = subprocess.run(["ansible-galaxy", "collection", "list"],
                     capture_output=True, text=True).stdout
installed = {}
for line in out.splitlines():
    m = re.match(r"^([a-z0-9_]+\.[a-z0-9_]+)\s+([0-9][^\s]*)\s*$", line)
    if m and m.group(1) not in installed:
        installed[m.group(1)] = m.group(2)

bad = 0
for c in req:
    name = c["name"] if isinstance(c, dict) else c
    want = c.get("version") if isinstance(c, dict) else None
    have = installed.get(name)
    if want is None:
        print(f"UNPINNED  {name:38} installed {have or '(none)'}"); bad += 1
    elif have is None:
        print(f"MISSING   {name:38} pinned {want}, not installed"); bad += 1
    elif have != want:
        print(f"DRIFT     {name:38} pinned {want}, installed {have}"); bad += 1
    else:
        print(f"OK        {name:38} {want}")
print("\n" + ("Everything pinned and installed as specified."
              if not bad else f"{bad} item(s) need attention."))
sys.exit(0 if not bad else 1)
PY
```

## Pin

For each `UNPINNED` entry, add the installed version to
`collections/requirements.yml` as `version: "<exact>"`. If a collection is not
installed at all, install it first:

```bash
ansible-galaxy collection install <namespace.name>
ansible-galaxy collection list <namespace.name>
```

Never invent a version number. Never pin to a range (`>=`, `*`).

## Install

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

Add `--force` only when bumping a pin downward — `ansible-galaxy` will not
downgrade otherwise.

## Verify

**Re-run the audit block above after installing.** Do not report success on the
install command's exit code alone — `ansible-galaxy` can resolve a different
version than requested without failing. Report the audit output verbatim.

## When a pin changes

A version bump is a behavior change. Per CLAUDE.md and the dev-workflow skill:

- Open an issue first, label it.
- Test the pipeline with the new version before committing.
- Note the bump in `CHANGELOG.md`.
- One concern per PR — a bump ships on its own, not bundled with unrelated work.
