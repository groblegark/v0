# v0-decompose

**Purpose:** Convert a plan file into trackable issues.

## Workflow

1. Verify plan file exists and is committed
2. Launch Claude to parse plan and create issues
3. Label all issues with `plan:<name>`
4. Auto-commit plan with epic ID
5. Transition to `queued` phase and hold

## Usage

```bash
v0 decompose plans/auth.md
```

After decomposition, review issues then run `v0 resume <name>`.
