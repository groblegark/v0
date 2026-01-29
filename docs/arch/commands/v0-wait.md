# v0 wait

Wait for an operation, issue, or roadmap to complete.

## Usage

```bash
v0 wait <target> [--timeout <duration>] [--quiet]
```

## Target Resolution

The target can be:

| Format | Example | Description |
|--------|---------|-------------|
| Operation name | `auth` | Wait for operation "auth" |
| Issue ID | `v0-abc123` | Wait for issue (auto-detected by pattern) |
| Roadmap name | `api-rewrite` | Wait for roadmap |
| Explicit issue | `--issue v0-xyz` | Explicit issue ID (for edge cases) |

Issue IDs are auto-detected when the argument matches the project's issue
pattern (`${ISSUE_PREFIX}-[a-z0-9]+`).

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Completed successfully |
| 1 | Failed or cancelled |
| 2 | Timeout expired |
| 3 | Target not found |

## Examples

```bash
# Wait for operation
v0 wait auth

# Wait for bug fix (auto-detects issue ID)
v0 wait v0-bug123

# Wait with timeout
v0 wait v0-chore456 --timeout 30m

# Script usage with exit code check
if v0 wait auth --quiet; then
  echo "Auth feature merged"
fi
```

## Implementation Details

### Issue Pattern Detection

Issue IDs follow the pattern defined by wok configuration:
- Pattern: `${ISSUE_PREFIX}-[a-z0-9]+`
- Example with `prefix = "v0"`: `v0-abc123`, `v0-7f8e9d`

The detection uses regex matching against `v0_issue_pattern()` output.

### State File Locations

| Work Type | State Path | Key Fields |
|-----------|------------|------------|
| Operation | `${BUILD_DIR}/operations/<name>/state.json` | `phase`, `epic_id` |
| Bug Fix | `${BUILD_DIR}/fix/<id>/state.json` | `status`, `issue_id` |
| Chore | `${BUILD_DIR}/chore/<id>/state.json` | `status`, `issue_id` |
| Roadmap | `${BUILD_DIR}/roadmaps/<name>/state.json` | `phase`, `idea_id` |

### Terminal States by Type

| Work Type | Success State | Failure States |
|-----------|---------------|----------------|
| Operation | `merged` | `cancelled`, `failed` |
| Bug/Chore | `pushed`, `completed` | - |
| Roadmap | `completed` | `failed`, `interrupted` |

### Polling Interval

Wait polls every 2 seconds, consistent with other v0 monitoring patterns.

### wok Fallback

If no local state exists for an issue ID, wait checks wok directly:
- `done` or `closed` status -> success (exit 0)
- `todo` or `in_progress` -> keep waiting
- Issue not found -> error (exit 3)

## Resolution Order

When given a positional argument:

1. **Operation lookup**: Check `${BUILD_DIR}/operations/<name>/state.json`
2. **Roadmap lookup**: Check `${BUILD_DIR}/roadmaps/<name>/state.json`
3. **Issue ID detection**: If matches `${ISSUE_PREFIX}-[a-z0-9]+` pattern
   - Search operations by `epic_id`
   - Search fixes by directory name
   - Search chores by directory name
   - Search roadmaps by `idea_id`
   - Fall back to wok status query
