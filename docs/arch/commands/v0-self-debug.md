# v0-self-debug

**Purpose:** Generate debug reports for failed operations.

## Workflow

1. Collect state and logs for target
2. Package into debug report
3. Write to `.v0/build/debug/` or stdout

## Usage

```bash
v0 self debug auth     # Debug specific operation
v0 self debug fix      # Debug fix worker
v0 self debug mergeq   # Debug merge queue
```
