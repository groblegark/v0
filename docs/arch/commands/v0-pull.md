# v0-pull

**Purpose:** Pull changes from agent branch into user branch.

## Workflow

1. Resolve target branch (current or specified)
2. Fetch latest from agent branch
3. Attempt merge
4. Optionally resolve conflicts with Claude

## Usage

```bash
v0 pull                  # Pull into current branch
v0 pull main             # Pull into main branch
v0 pull --resolve        # Pull with LLM conflict resolution
```

## Options

| Option | Description |
|--------|-------------|
| `--resolve` | If conflicts exist, run Claude to resolve them (foreground) |

## Conflict Resolution

When conflicts occur:
- Without `--resolve`: Aborts and shows instructions
- With `--resolve`: Launches Claude to resolve conflicts interactively

## Related

- [v0-push](v0-push.md) - Push changes to agent
- [v0-merge](v0-merge.md) - Merge branches
