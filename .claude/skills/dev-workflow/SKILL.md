---
name: dev-workflow
description: Mandatory development cycle for this repo — issue, branch, PR, merge
---

# Development Workflow

Every change follows this cycle. No exceptions.

```
Open issue → branch from main → implement → open PR (Closes #N) → CI green → merge → delete branch
```

## Steps

1. **Open a GitHub issue first.** Label it (`gh label list`). Describe what and
   why. No implementation without an issue.

2. **Branch from `main`.** Naming: `<type>-<issue>-<slug>`
   (e.g. `fix-22-token-path`, `feat-21-windows-containerdisk`).
   Types: `feat`, `fix`, `docs`, `chore`, `refactor`.

3. **Implement.** Update `CHANGELOG.md` (Added / Changed / Fixed). Maintain the
   consumer contracts — every change must hold for all consumers listed in
   CLAUDE.md.

4. **Open a PR.** Include `Closes #<number>` in the body. Summary + test plan.
   Use `gh pr create --head <branch>` rather than relying on checkout state.

5. **CI must pass.** Required status checks: `yamllint`, `ansible-lint`.

6. **Merge.** Claude has standing authorization to merge green PRs without asking.
   After merge: `git checkout main && git pull && git branch -d <branch>`.

## Multi-session safety

This working tree may be shared by multiple Claude sessions. Before committing:

- Re-run `git branch --show-current` to confirm you're on your branch.
- Prefer `git add <explicit paths>` over `git add -A`.
- If you see uncommitted changes you didn't make, do not discard them.

## One concern per PR

Group changes by shared root cause, not by item count. The test: would you revert
these together? If yes, ship them together. Behavior changes and anything risky
stay isolated regardless.
