---
description: Manage git worktrees only with worktrunk (wt)
alwaysApply: true
---
Git worktrees are managed only with worktrunk (`wt`). NEVER run `git worktree add|remove|move|prune`, and NEVER create worktrees with harness or skill fallbacks. When a skill says to create a worktree, use `wt`.

- Branch name: `<ticket>-<slug>` when the work has a ticket, issue or PR number (`42-fix-login`), otherwise `<slug>`. Use lowercase kebab-case with no `/`. The worktree path comes from the branch name, so never pass a path.
- Create: `wt switch --create <branch> --no-cd --yes --format json`. Add `--base <branch>` for a base other than the default branch. Work in the returned `path`, which is `<repo>/.worktrees/<branch>`.
- Existing branch or PR: `wt switch <branch> --no-cd --yes --format json` or `wt switch pr:<N> --no-cd --yes --format json`.
- List: `wt list --format json`.
- Remove: `wt remove <branch>`. It keeps unmerged branches and refuses dirty worktrees. `--force` and `--force-delete` need the user's approval.
- Cleanup is automatic. Creating a worktree fetches and then runs `wt step prune` in the background. That removes clean worktrees older than an hour whose changes are already in the remote default branch. Don't write expiry markers or cleanup scripts.
- `.worktrees/` is ignored globally. NEVER commit it or add it to a repository's `.gitignore`.
