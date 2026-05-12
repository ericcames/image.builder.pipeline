# Security Policy

## Scope

This is an **automation pipeline** for building CIS-hardened AMIs and generating compliance data. It contains no production credentials, no customer data, and no live service endpoints. All sensitive values (Red Hat tokens, AWS credentials) are resolved at runtime from local config and environment variables and are never committed.

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
- Red Hat offline tokens (belong in `~/.ansible/ansible.cfg` only)
- AWS credentials (belong in environment variables only)
- Inventory files other than `inventories/sample/` (all others are gitignored)
- `docs/aws-environment.md` (gitignored — local environment notes)

If you spot any of the above committed by mistake, open an issue immediately.
