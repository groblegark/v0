# v0-mayor

**Purpose:** Launch Claude as an interactive orchestration assistant.

## Workflow

1. Load project configuration
2. Create mayor-specific Claude settings
3. Launch Claude with orchestration context
4. Session is primed with project status

## Usage

```bash
v0 mayor                 # Start mayor session
v0 mayor --model sonnet  # Use faster model
```

## Options

| Option | Description |
|--------|-------------|
| `--model <model>` | Override model (default: opus) |

## Capabilities

The mayor runs interactively (no worktree, no tmux) and helps you:
- Plan and dispatch features
- Queue bug fixes
- Process chores
- Monitor worker status
- Organize and prioritize work

## Session Hooks

On session start and before compacting, the mayor receives:
- `v0 prime` - Quick-start guide
- `v0 status` - Current worker status
- `wok ready` - Ready issues (if available)

## Related

- [v0-status](v0-status.md) - Show status
- [v0-plan](v0-plan.md) - Create plans
