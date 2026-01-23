# v0-plan

**Purpose:** Create implementation plans using Claude.

## Workflow

1. Create state tracking
2. Launch Claude in tmux (or directly with `--direct`)
3. Claude generates plan at `plans/<name>.md`
4. Auto-commit plan (unless `--draft`)
5. Transition to `planned` phase and hold

## Usage

```bash
v0 plan auth "Add user authentication"
v0 plan api "Build REST API" --foreground  # Run blocking
v0 plan test "Add tests" --draft           # Skip auto-commit
```

## Options

| Flag | Description |
|------|-------------|
| `--foreground` | Run blocking |
| `--direct` | Run without tmux (v0-plan-exec) |
| `--draft` | Skip auto-commit |
