# v0-push

**Purpose:** Reset agent branch to match user branch.

## Workflow

1. Resolve source branch (current or specified)
2. Check for divergence with agent branch
3. Push (force if --force and diverged)

## Usage

```bash
v0 push                  # Push current branch to agent
v0 push main             # Push main to agent
v0 push --force          # Force push (overwrites agent commits)
```

## Options

| Option | Description |
|--------|-------------|
| `-f, --force` | Force push even if agent has new commits |

## Divergence Handling

If the agent branch has commits not in your branch:
- Shows the divergence diff
- Requires `--force` to overwrite agent commits
- Warns about what will be lost

## Related

- [v0-pull](v0-pull.md) - Pull changes from agent
