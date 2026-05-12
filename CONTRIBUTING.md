# Contributing

## Workflow

**Every change follows this sequence — no exceptions:**

```
Open issue → branch from main → implement → open PR (Closes #N) → merge → issue closes
```

1. **Open an issue first** — before writing a single line of code or making any change, open a GitHub issue describing what you're fixing or adding and why. No implementation without an issue.
2. **Branch from `main`** — use the naming pattern `<type>/<short-description>` (e.g. `fix/token-cleanup`, `feat/phase2-l2-blueprint`, `docs/exempt-controls`).
3. **One concern per PR** — group changes by shared root cause, not item count. The test: would you revert these together? If yes, ship them together. Behavior changes stay isolated regardless.
4. **Reference the issue** — include `Closes #<number>` in your PR description so the issue closes automatically on merge.
5. **PRs target `main`** — direct pushes to `main` are not blocked, but all non-trivial changes should go through a PR for traceability.
6. **Update CHANGELOG.md** — every PR must include a CHANGELOG entry grouped under Added / Changed / Fixed.

## Branch naming

| Prefix | When to use |
|--------|-------------|
| `feat/` | New capability or platform |
| `fix/` | Bug fix |
| `docs/` | Documentation only |
| `chore/` | Dependency updates, CI, housekeeping |
| `refactor/` | Code restructure with no behavior change |

## Commit messages

```
<type>: <short description>

<optional body explaining why, not what>
```

Types: `feat`, `fix`, `docs`, `refactor`, `chore`

## Code conventions

See [CLAUDE.md](CLAUDE.md) for full detail. Key rules:

- **`ansible.platform` over `ansible.controller`** — `ansible.controller` is legacy
- **Always delete tokens** — any playbook that creates a Red Hat or AAP token must delete it in an `always:` block
- **OS-only AMIs** — don't bake products (Satellite, app stacks) into the image
- **Phase order is enforced** — don't add Phase 2 work until Phase 1 is end-to-end solid; skipping phases creates compounding bugs

## Testing

Pipeline changes should be tested against a live run before opening a PR. Document what you ran and what you observed in the PR description. At minimum, state which playbook(s) you exercised and whether the pipeline completed cleanly.

For compliance-related changes, include the OpenSCAP score and whether it clears the 95-point gate.

## Sensitive data

Never commit:

- Credentials, tokens, or passwords of any kind
- Inventory files other than `inventories/sample/` (all others are gitignored)
- `docs/aws-environment.md` (gitignored — local notes only)

Red Hat offline tokens come from `~/.ansible/ansible.cfg`. AWS credentials come from environment variables. Neither belongs in this repo.
