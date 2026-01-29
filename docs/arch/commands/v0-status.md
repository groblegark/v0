# v0-status

**Purpose:** Show operation and worker status.

## Workflow

1. List operations with phase and status
2. Show worker status (fix, chore, mergeq)
3. Show coffee/nudge daemon status

## Usage

```bash
v0 status              # Overview
v0 status auth         # Specific operation
v0 status --fix        # Fix worker details
v0 status --merge      # Merge queue details
v0 status --blocked    # Show waiting operations
v0 status --json       # Output as JSON
```
