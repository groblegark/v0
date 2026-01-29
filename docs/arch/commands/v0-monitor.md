# v0-monitor

**Purpose:** Monitor worker queues for auto-shutdown.

## Workflow

1. Check if workers have pending work
2. Track how long all queues have been empty
3. If empty for threshold duration, trigger `v0 shutdown`

Used for unattended operation (e.g., overnight runs).
