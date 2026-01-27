# v0-archive

**Purpose:** Move stale archived plans to an icebox worktree.

## Workflow

1. Find archived plans older than N days (default: 7)
2. Setup icebox worktree on `v0/plans` branch
3. Move plans to icebox worktree
4. Commit changes in both icebox and main repo

## Usage

```bash
v0 archive                # Archive plans older than 7 days
v0 archive --days 30      # Archive plans older than 30 days
v0 archive --all          # Archive all plans in archive/
v0 archive --dry-run      # Preview what would be archived
v0 archive --force        # Skip confirmation prompts
```

## Options

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Show what would be archived without moving |
| `-d, --days N` | Archive plans older than N days (default: 7) |
| `-a, --all` | Archive all plans (ignores age) |
| `-f, --force` | Skip confirmation prompts |

## Related

- [v0-plan](v0-plan.md) - Create plans
- [v0-tree](v0-tree.md) - Worktree management
