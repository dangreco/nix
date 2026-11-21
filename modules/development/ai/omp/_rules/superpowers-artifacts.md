---
description: Keep Superpowers specs and plans ephemeral and uncommitted
alwaysApply: true
---
Superpowers design specs and implementation plans are scratch files, never repository docs. This is the user preference that overrides the `docs/superpowers/...` locations in brainstorming and writing-plans, and brainstorming's "committed".

- Spec: `<main>/.superpowers/specs/YYYY-MM-DD-<topic>-design.md`. Plan: `<main>/.superpowers/plans/YYYY-MM-DD-<feature-name>.md`.
- `<main>` is the main checkout, even when you are in a worktree, so the files outlive `wt remove`: `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`.
- Refer to them by absolute path in handoffs, plan headers and subagent prompts; executors work in `.worktrees/<branch>`.
- NEVER `git add` or commit them, NEVER copy them into `docs/` or any tracked path, and NEVER add `.superpowers/` to a repository's `.gitignore`: it is ignored globally.
- Delete the spec and plan once the work is merged or discarded. Keep them while a PR is open.
