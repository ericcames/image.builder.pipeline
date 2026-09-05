# Operations Runbook

Quick reference for common pipeline operations. For design details see
[design.md](design.md); for the development cycle see
`.claude/skills/dev-workflow/SKILL.md`.

---

## Manual containerDisk rebuild

The RHEL 9 CIS L1 containerDisk rebuilds automatically on the 1st of every
month at 06:00 UTC via `.github/workflows/containerdisk-rebuild.yml`. To
trigger an ad-hoc rebuild:

**GitHub UI:** Actions tab → "Rebuild RHEL 9 CIS containerDisk" → Run workflow
→ select `main` → Run workflow.

**CLI:**

```bash
gh workflow run "Rebuild RHEL 9 CIS containerDisk"
```

**Check status:**

```bash
gh run list --workflow=containerdisk-rebuild.yml --limit 5
```

**View logs for a specific run:**

```bash
gh run view <run-id> --log
```

Expected duration: 20-35 minutes (Image Builder compose ~15-25 min, qcow2
download ~2-5 min, podman build + push ~3-5 min).

---

## Secret rotation

Three GitHub Actions secrets power the scheduled containerDisk rebuild:

| Secret | Source | When to rotate |
|--------|--------|---------------|
| `RH_OFFLINE_TOKEN` | `~/.ansible.cfg` under `[galaxy_server.rh_certified]` | When the token expires (401 errors in scheduled runs) |
| `QUAY_USERNAME` | Quay.io username | When the account changes |
| `QUAY_PASSWORD` | Quay.io password or robot account token | When the password changes |

**Obtaining a new RH token:** console.redhat.com → Automation Hub → Connect to
Hub → API token. Update `~/.ansible.cfg` locally first, then sync to GitHub.

**Updating a secret:**

```bash
echo "<new-value>" | gh secret set RH_OFFLINE_TOKEN --repo ericcames/image.builder.pipeline
```

Or pipe from the config directly:

```bash
python3 -c "
import configparser, os
cfg = configparser.ConfigParser()
cfg.read(os.path.expanduser('~/.ansible.cfg'))
print(cfg.get('galaxy_server.rh_certified', 'token'))
" | gh secret set RH_OFFLINE_TOKEN --repo ericcames/image.builder.pipeline
```

**Verify secrets are set:**

```bash
gh secret list --repo ericcames/image.builder.pipeline
```

---

## Troubleshooting scheduled builds

| Symptom | Cause | Fix |
|---------|-------|-----|
| Fails at "Configure Red Hat token" | `RH_OFFLINE_TOKEN` secret missing or expired | Rotate the secret (see above) |
| Fails at "Log in to Quay.io" | `QUAY_USERNAME` or `QUAY_PASSWORD` wrong | Update secrets; verify locally with `podman login quay.io` first |
| Fails at compose wait (exit code 1) | Image Builder compose failed | Check stderr in the run log; may be transient — re-trigger |
| Fails at compose wait (exit code 2) | Compose timed out (>30 min) | Re-trigger; if persistent, check console.redhat.com for Image Builder status |
| Fails at `podman push` | Quay repo missing or auth expired | Verify repo exists at quay.io; re-login and update `QUAY_PASSWORD` |
| Succeeds but no new image on Quay | Tag mismatch or push silently failed | Check the run log for the pushed tag; verify with `podman pull quay.io/zigfreed/rhel9-cis-l1-golden:<tag>` |

---

## AMI pipeline (manual)

Eric runs this from his workstation. Not automated.

**Prerequisites:** AWS credentials exported, RH token in `~/.ansible.cfg`,
collections installed (`ansible-galaxy collection install -r collections/requirements.yml`).

```bash
export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=<account-id>

ansible-playbook playbooks/build_cis_image.yml         # ~20 min
ansible-playbook playbooks/deploy_and_scan.yml         # ~5 min
ansible-playbook playbooks/generate_policy_data.yml    # seconds
```

Duration: ~30 minutes total. Output at `output/rhel9/data.json`.

---

## Windows build (manual)

Eric runs this from his workstation. Requires an OpenShift sandbox cluster with
KubeVirt — builds never run on the demo cluster (the playbook enforces this).

**Prerequisites:** `K8S_AUTH_HOST` and `K8S_AUTH_API_KEY` exported,
`WINDOWS_ADMIN_PASSWORD` set.

```bash
export K8S_AUTH_HOST=https://api.<cluster>:6443
export K8S_AUTH_API_KEY=<bearer-token>
export WINDOWS_ADMIN_PASSWORD=<password>

ansible-playbook playbooks/build_windows_image.yml
```

Duration: ~30 minutes. The playbook handles ISO fetch, re-master, VM creation,
Windows Setup, and sysprep. See `.claude/skills/windows-image-build/SKILL.md`
for the full runbook.
