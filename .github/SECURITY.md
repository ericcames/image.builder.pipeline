# Security Policy

## Scope

This is an **automation pipeline** for building CIS-hardened images (AMIs and containerDisks) and generating compliance data. It contains no production credentials, no customer data, and no live service endpoints. All sensitive values (Red Hat tokens, AWS credentials, OpenShift credentials, Quay credentials) are resolved at runtime from local config, environment variables, and GitHub Actions secrets — never committed.

## Supported Versions

Only the latest commit on `main` is maintained.

## Reporting a Vulnerability

Because this is a demo/automation repo with no production exposure, **open a public GitHub issue** to report any security concerns. There is no need for private disclosure.

When reporting, include:

- A description of the issue
- The file(s) affected
- Any suggested fix if you have one

## What Should Never Be Committed

As a reminder — these are never committed to this repo:

- Credentials, tokens, or passwords of any kind
- Red Hat offline tokens (belong in `~/.ansible.cfg` or GitHub Actions secrets only)
- AWS credentials (belong in environment variables only)
- OpenShift/Kubernetes credentials (`K8S_AUTH_HOST`, `K8S_AUTH_API_KEY` — environment variables only)
- Quay.io credentials (belong in `podman login` session or GitHub Actions secrets only)
- Inventory files other than `inventories/sample/` (all others are gitignored)
- `docs/aws-environment.md` (gitignored — local environment notes)

If you spot any of the above committed by mistake, open an issue immediately.
