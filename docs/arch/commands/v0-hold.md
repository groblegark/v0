# v0-hold

**Purpose:** Pause operation phase transitions.

## Workflow

1. Find operation state
2. Set `held=true` and `held_at` timestamp
3. Operation completes current work then stops

## Usage

```bash
v0 hold auth           # Put on hold
v0 resume auth         # Release hold
```

When held, the operation won't advance to the next phase.
