---
name: dev-workflow
description: "Mandatory development cycle for this repo — issue, branch, worktree, PR, merge. TRIGGER when: the user asks how to make a change, wants to know the dev process, is about to commit to main directly, or asks about branching or PR conventions. SKIP: if the user wants first-time machine setup — that is first-time — or wants to run a pipeline playbook, which is the pipeline-specific skill."
---

# Development Workflow

Every change follows this cycle. No exceptions.

```
Open issue → worktree from main → implement → open PR (Closes #N) → CI green → merge → remove worktree
```

## Steps

1. **Open a GitHub issue first.** Label it (`gh label list`). Describe what and
   why. No implementation without an issue.

2. **Create a worktree.** Never edit in the main checkout — treat it as read-only.

   ```bash
   git worktree add -b <type>-<issue>-<slug> \
     ../image.builder.pipeline-<slug> main
   cd ../image.builder.pipeline-<slug>
   ```

   Naming: `<type>-<issue>-<slug>`
   (e.g. `fix-22-token-path`, `feat-21-windows-containerdisk`).
   Types: `feat`, `fix`, `docs`, `chore`, `refactor`.

3. **Implement.** Maintain the consumer contracts — every change must hold for
   all consumers listed in CLAUDE.md. There is no changelog to update (#119);
   say what changed and why in the issue and the PR body.

4. **Open a PR.** Include `Closes #<number>` in the body. Summary + test plan.
   Use `gh pr create --head <branch>` rather than relying on checkout state.

5. **CI must pass.** Required status checks: `yamllint`, `ansible-lint`.

6. **Merge and clean up.** Claude has standing authorization to merge green PRs
   without asking. After merge:

   ```bash
   cd /home/eames/git-repos/image.builder.pipeline
   git worktree remove ../image.builder.pipeline-<slug>
   git checkout main && git pull && git branch -d <branch>
   ```

## Multi-session safety

**Always use an isolated worktree for code changes.** The main checkout stays
on `main` and serves as the read-only home base. Git enforces that no two
worktrees can be on the same branch, so cross-session collisions are impossible.

Within a worktree, these habits remain as a safety net:

- Re-run `git branch --show-current` immediately before `git add` and `git commit`.
- Prefer `git add <explicit paths>` over `git add -A`.
- If you see uncommitted changes you didn't make, do not discard them.

## One concern per PR

Group changes by shared root cause, not by item count. The test: would you revert
these together? If yes, ship them together. Behavior changes and anything risky
stay isolated regardless.
