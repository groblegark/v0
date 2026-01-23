# v0-merge

**Purpose:** Merge a worktree branch to main.

## Workflow

1. Verify worktree has commits
2. Fetch latest main
3. Attempt merge (fast-forward or regular)
4. If conflict and `--resolve`: launch Claude to fix
5. Push merged main
6. Delete feature branch

## Usage

```bash
v0 merge /path/to/worktree           # Merge worktree
v0 merge /path/to/worktree --resolve # Auto-resolve conflicts
v0 merge fix/PROJ-abc123             # Merge by branch name
```
