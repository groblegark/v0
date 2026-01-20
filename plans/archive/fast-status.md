# Fast Status Implementation Plan

## Overview

Optimize `v0 status` from ~1.0s to <0.2s by eliminating performance bottlenecks in the status command. The current implementation suffers from:

1. **Network I/O**: `git ls-remote` calls per merge-queued operation (500ms-2s each)
2. **Excessive jq calls**: 10+ jq invocations per operation file
3. **External process spawning**: `wk list`, `pgrep`, `tmux has-session` per worker
4. **N+1 query pattern**: Recently completed bugs/chores fetch each item individually

Target: Sub-200ms execution for the example output (~20 operations, 5 workers).

## Project Structure

```
v0/
├── bin/
│   ├── v0-status              # Main status command (refactor target)
│   └── v0-status-fast         # Optional: new optimized version during dev
├── lib/
│   ├── v0-common.sh           # Shared config (unchanged)
│   ├── coffee-common.sh       # Wake lock utilities (unchanged)
│   ├── nudge-common.sh        # Nudge worker utilities (unchanged)
│   └── status-cache.sh        # NEW: Caching layer for status data
└── .v0/
    └── build/
        └── .status-cache/     # NEW: Runtime cache directory
            ├── branches.json  # Cached git branch existence
            └── workers.json   # Cached worker states
```

## Dependencies

- **jq** (existing) - JSON processing
- **bash 4+** (existing) - Associative arrays for in-memory caching
- No new external dependencies required

## Implementation Phases

### Phase 1: Batch jq Operations (Target: -200ms)

**Goal**: Replace 10+ jq calls per operation with a single jq invocation that extracts all fields.

**Current code** (`v0/bin/v0-status` lines 520-529):
```bash
for state_file in "${BUILD_DIR}"/operations/*/state.json; do
  name=$(jq -r '.name' "${state_file}")
  phase=$(jq -r '.phase' "${state_file}")
  machine=$(jq -r '.machine // "unknown"' "${state_file}")
  # ... 7 more jq calls
done
```

**Optimized approach**:
```bash
for state_file in "${BUILD_DIR}"/operations/*/state.json; do
  # Single jq call extracts all fields as tab-separated values
  read -r name phase machine session worker_pid op_type after held merge_status merge_queued created_at < <(
    jq -r '[.name, .phase, .machine // "unknown", .tmux_session // "",
           .worker_pid // "", .type // "build", .after // "", .held // "",
           .merge_status // "", .merge_queued // "", .created_at // ""] | @tsv' \
      "${state_file}"
  )
done
```

**Verification**:
- Run `time v0 status` before/after
- Expected improvement: 200-300ms reduction

---

### Phase 2: Eliminate git ls-remote Calls (Target: -500ms)

**Goal**: Remove network calls entirely from status display. Branch existence can be inferred from operation state.

**Current code** (`v0/bin/v0-status` lines 619, 861):
```bash
if git ls-remote --heads origin "${name}" 2>/dev/null | grep -q "${name}"; then
  # Branch exists on remote
fi
```

**Optimized approach**:
- If `merge_status == "merged"` → already merged, no check needed
- If `phase == "completed" && merge_queued == true` → assume branch exists (it was queued)
- If `phase == "executing"` → worker is active, branch exists
- Only ambiguous case: `phase == "completed"` without merge info → show "pending" status

```bash
# Infer branch status from operation state - no network calls
case "${phase}:${merge_status}" in
  *:merged)           branch_display="(merged)" ;;
  *:merging)          branch_display="(merging...)" ;;
  *:conflict)         branch_display="(== CONFLICT ==)" ;;
  completed:*)        branch_display="" ;;  # Awaiting merge
  *)                  branch_display="" ;;
esac
```

**Verification**:
- Run `time v0 status` - should drop to ~400ms
- Verify merge status indicators still appear correctly

---

### Phase 3: Batch Worker Status Checks (Target: -100ms)

**Goal**: Consolidate worker status checks into parallel operations.

**Current code** (scattered across lines 379-496, 683-750):
```bash
tmux has-session -t "${fix_session}" 2>/dev/null && fix_worker_running=true
fix_polling_pid=$(pgrep -f "while true.*${fix_session}" 2>/dev/null || true)
tmux has-session -t "${chore_session}" 2>/dev/null && chore_worker_running=true
chore_polling_pid=$(pgrep -f "while true.*${chore_session}" 2>/dev/null || true)
# ... repeated for each worker type
```

**Optimized approach**:
```bash
# Single tmux call to list all sessions
all_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

# Check worker sessions via string matching (no process spawning)
[[ "${all_sessions}" == *"v0-${PROJECT}-worker-fix"* ]] && fix_worker_running=true
[[ "${all_sessions}" == *"v0-${PROJECT}-worker-chore"* ]] && chore_worker_running=true

# Single pgrep for all polling daemons
all_polling=$(pgrep -af "while true.*v0-${PROJECT}" 2>/dev/null || true)
fix_polling_pid=$(echo "${all_polling}" | grep "worker-fix" | awk '{print $1}')
chore_polling_pid=$(echo "${all_polling}" | grep "worker-chore" | awk '{print $1}')
```

**Verification**:
- Worker statuses display correctly for all 5 worker types
- No functional regression in status display

---

### Phase 4: Remove Recently Completed Section from Default View (Target: -150ms)

**Goal**: The "recently completed" bugs/chores section uses N+1 queries via `wk`. Make it opt-in.

**Current behavior**: Always calls `get_completed_bugs()` and `get_completed_chores()` which execute:
- `wk list --status done --limit N`
- Then `wk show <id>` for each returned item

**Optimized approach**:
- Remove recently completed from default `v0 status` output
- Add `--recent` flag to show recently completed items
- This section adds visual noise and is rarely actionable

```bash
# Only fetch if explicitly requested
if [[ "${show_recent}" == "true" ]]; then
  completed_bugs=$(get_completed_bugs 72)
  completed_chores=$(get_completed_chores 72)
  # ... display section
fi
```

**Alternative**: If recently completed must stay, cache `wk list` output:
```bash
# Cache wk results for 60 seconds
wk_cache_file="/tmp/v0-${PROJECT}-wk-cache.json"
if [[ ! -f "${wk_cache_file}" ]] || [[ $(find "${wk_cache_file}" -mmin +1 2>/dev/null) ]]; then
  wk list --type bug,chore --status done --limit 10 --json > "${wk_cache_file}"
fi
```

**Verification**:
- `v0 status` completes without recently completed section
- `v0 status --recent` shows the section (if implemented)

---

### Phase 5: Optimize Merge Queue Reading (Target: -50ms)

**Goal**: Read merge queue file once, extract all needed data in single jq pass.

**Current code** (lines 96, 718-719):
```bash
entries=$(jq -r '.entries[] | select(.status == "pending" or .status == "processing")' ...)
processing=$(jq '[.entries[] | select(.status == "processing")] | length' ...)
pending=$(jq '[.entries[] | select(.status == "pending")] | length' ...)
```

**Optimized approach**:
```bash
# Single jq call extracts all merge queue stats
if [[ -f "${mergeq_queue_file}" ]]; then
  read -r processing pending total < <(
    jq -r '[
      ([.entries[] | select(.status == "processing")] | length),
      ([.entries[] | select(.status == "pending")] | length),
      (.entries | length)
    ] | @tsv' "${mergeq_queue_file}"
  )
fi
```

**Verification**:
- Merge worker status displays correct counts
- Queue processing/pending numbers match actual queue state

---

### Phase 6: Operation State Pre-loading (Target: -100ms)

**Goal**: Read all operation state files in a single pass using process substitution.

**Optimized approach**:
```bash
# Collect all state files and process in batch
mapfile -t state_files < <(printf '%s\n' "${BUILD_DIR}"/operations/*/state.json 2>/dev/null)

if [[ ${#state_files[@]} -gt 0 ]]; then
  # Single jq invocation processes all files
  all_ops=$(jq -s '
    [.[] | {
      name: .name,
      phase: .phase,
      machine: (.machine // "unknown"),
      session: (.tmux_session // ""),
      worker_pid: (.worker_pid // ""),
      type: (.type // "build"),
      after: (.after // ""),
      held: (.held // ""),
      merge_status: (.merge_status // ""),
      merge_queued: (.merge_queued // false),
      created_at: (.created_at // "")
    }]
  ' "${state_files[@]}")

  # Iterate over pre-parsed JSON
  for i in $(seq 0 $(($(echo "$all_ops" | jq 'length') - 1))); do
    read -r name phase machine session worker_pid op_type after held merge_status merge_queued created_at < <(
      echo "$all_ops" | jq -r ".[$i] | [.name, .phase, .machine, .session, .worker_pid, .type, .after, .held, .merge_status, .merge_queued, .created_at] | @tsv"
    )
    # ... process operation
  done
fi
```

**Verification**:
- All 20 operations display correctly
- Status indicators (blocked, completed, merged) accurate

## Key Implementation Details

### Performance Budget

| Component | Current | Target | Technique |
|-----------|---------|--------|-----------|
| jq parsing | ~300ms | ~50ms | Batch extraction |
| git ls-remote | ~500ms | 0ms | State inference |
| Worker checks | ~150ms | ~30ms | Single tmux/pgrep |
| wk queries | ~200ms | 0ms | Remove/cache |
| Merge queue | ~50ms | ~10ms | Single jq pass |
| **Total** | ~1000ms | ~100ms | |

### Critical Patterns

**Tab-separated value extraction**:
```bash
read -r field1 field2 field3 < <(jq -r '[.a, .b, .c] | @tsv' file.json)
```

**Null-safe field access**:
```bash
jq -r '.field // "default"'  # Returns "default" if null
```

**Session existence via string matching** (faster than tmux has-session):
```bash
sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
[[ "${sessions}" == *"target-session"* ]] && exists=true
```

### Files to Modify

1. **`v0/bin/v0-status`** - Primary refactor target
   - Lines 520-600: Operation parsing loop
   - Lines 379-496: Worker status functions
   - Lines 267-338: Recently completed section
   - Lines 683-750: Worker display section

### Backward Compatibility

- All existing command-line flags must continue to work
- Output format must remain identical (same columns, spacing, colors)
- Worker status display unchanged
- Operation state semantics preserved

## Verification Plan

### Unit Tests (per phase)

1. **Phase 1**: `time bash -c 'for f in .v0/build/operations/*/state.json; do jq ... done'`
2. **Phase 2**: Verify merge status indicators match git state
3. **Phase 3**: Compare worker statuses with manual `tmux ls` check
4. **Phase 4**: Confirm `--recent` flag works if implemented
5. **Phase 5**: Verify merge queue counts match `v0 mergeq --list`
6. **Phase 6**: Confirm all operations listed with correct states

### Integration Test

```bash
# Baseline measurement
time v0 status > /tmp/status-before.txt

# After each phase
time v0 status > /tmp/status-after.txt

# Verify output equivalence (ignoring timing-sensitive fields)
diff <(grep -v 'pid:' /tmp/status-before.txt) <(grep -v 'pid:' /tmp/status-after.txt)
```

### Performance Acceptance Criteria

```bash
# Must complete in under 200ms
time_ms=$(TIMEFORMAT='%R'; { time v0 status > /dev/null; } 2>&1 | awk '{print $1 * 1000}')
[[ ${time_ms%.*} -lt 200 ]] && echo "PASS" || echo "FAIL: ${time_ms}ms"
```

### Edge Cases to Verify

- Empty operations directory (no state files)
- Missing merge queue file
- All workers stopped
- Operations with missing/null fields in state.json
- Large number of operations (50+)
- Network unavailable (should not affect status)
