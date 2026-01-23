# Status Optimize: Consolidate jq Calls in v0-status

## Overview

Optimize `bin/v0-status` by consolidating jq calls where beneficial. Currently has ~21 jq calls across different use cases. The goal is to reduce redundant file reads while preserving the efficiency of batch processing (jq -s) for multi-file operations.

## Analysis Summary

| Category | Count | Strategy |
|----------|-------|----------|
| Multi-file jq -s (batch) | 2 | Keep - already efficient |
| Queue file reads | 9 | Consolidate within scope |
| Individual state reads | 3 | Evaluate sm_read_state_fields |
| wk tool calls | 6 | Out of scope |
| Already optimized | 1 | No change |

**Key insight**: `sm_read_state_fields` is efficient for reading multiple fields from a *single* state file. For multi-file operations, `jq -s` remains more efficient as it spawns one process for all files vs. N processes.

## Project Structure

```
bin/v0-status           # Main file to modify
lib/state-machine.sh    # sm_read_state_fields (already exists)
tests/unit/v0-status.bats  # Existing tests to verify
```

## Dependencies

- jq (existing)
- state-machine.sh functions (existing)

## Implementation Phases

### Phase 1: Consolidate Queue File Reads in Main List Loop

**Current** (lines 692, 764): Two separate jq calls per operation inside the loop
```bash
# Line 692: Queue entry status
queue_entry_status=$(jq -r ".entries[] | select(.operation == \"${name}\") | .status" "${queue_file}")

# Line 764: Merge queue updated_at
mq_updated=$(jq -r ".entries[] | select(.operation == \"${name}\" and .status == \"completed\") | .updated_at // empty" "${mergeq_file}")
```

**Optimized**: Pre-fetch queue data into associative array before loop
```bash
# Before loop - single jq call
declare -A queue_status_map queue_updated_map
if [[ -f "${mergeq_file}" ]]; then
  while IFS=$'\t' read -r op status updated; do
    queue_status_map["${op}"]="${status}"
    queue_updated_map["${op}"]="${updated}"
  done < <(jq -r '.entries[] | [.operation, .status, (.updated_at // "")] | @tsv' "${mergeq_file}" 2>/dev/null)
fi

# Inside loop - simple lookup
queue_entry_status="${queue_status_map[${name}]:-}"
mq_updated="${queue_updated_map[${name}]:-}"
```

**Savings**: Reduces 2×N jq calls to 1 jq call (where N = operation count)

### Phase 2: Consolidate Merge Queue Section Reads

**Current** (lines 815, 920-923, 940, 946): Four separate jq reads of same queue file
```bash
# Line 815
merges_pending=$(jq -r '.entries[] | select(.status == "pending" or .status == "processing") | .operation' ...)

# Lines 920-923
read -r processing pending < <(jq -r '[([.entries[] | select(.status == "processing")] | length), ...]' ...)

# Lines 940, 946 (duplicated)
jq -r '.entries[] | select(.status == "pending" or .status == "processing") | "\(.status)\t\(.operation)"' ...
```

**Optimized**: Single read at section start, reuse data
```bash
# Single read with all needed data
declare -A mergeq_entries
mergeq_raw=""
if [[ -f "${mergeq_queue_file}" ]]; then
  mergeq_raw=$(jq -r '.entries[] | select(.status == "pending" or .status == "processing") | "\(.status)\t\(.operation)"' "${mergeq_queue_file}" 2>/dev/null)
fi

# Derive counts and lists from raw data
processing_count=$(echo "${mergeq_raw}" | grep -c "^processing" || echo 0)
pending_count=$(echo "${mergeq_raw}" | grep -c "^pending" || echo 0)
merges_pending=$(echo "${mergeq_raw}" | cut -f2)
```

**Savings**: Reduces 4 jq calls to 1

### Phase 3: Merge Max Name Calculation with Main Processing

**Current** (lines 633, 771-787): Two separate jq -s invocations on same files
```bash
# Line 633: Just to get names for max length
done < <(jq -rs '.[] | .name' "${state_files[@]}")

# Line 771: Full processing
done < <(jq -rs 'sort_by(.created_at) | .[] | [.name, ...] | @tsv' "${state_files[@]}")
```

**Optimized**: Combine into single pass
```bash
# Single jq -s that outputs both max_name_len and operation data
# First line: max name length; remaining lines: operation data
while IFS=$'\t' read -r line_type data rest; do
  if [[ "${line_type}" = "META" ]]; then
    max_name_len="${data}"
    [[ ${max_name_len} -lt 8 ]] && max_name_len=8
  else
    # Process operation: line_type is actually 'name'
    name="${line_type}"
    # ... rest of processing
  fi
done < <(jq -rs '
  (reduce .[] as $op (0; [., ($op.name | length)] | max)) as $max_len |
  "META\t\($max_len)\t",
  (sort_by(.created_at) | .[] | [.name, ...] | @tsv)
' "${state_files[@]}")
```

**Savings**: Reduces 2 jq -s calls to 1

### Phase 4: Optimize get_merged_operations

**Current** (line 272-287): Loop with individual jq per state file
```bash
for state_file in "${BUILD_DIR}/operations"/*/state.json; do
  read -r name merge_status merged_at < <(
    jq -r '[.name, (.merge_status // "null"), (.merged_at // "null")] | @tsv' "${state_file}"
  )
  # filter and output
done
```

**Optimized**: Single jq -s for all files
```bash
if compgen -G "${BUILD_DIR}/operations/*/state.json" > /dev/null; then
  jq -rs --arg cutoff "${cutoff_time}" '
    .[] | select(.merge_status == "merged" and .merged_at != null) |
    "\(.name)|\(.merged_at)"
  ' "${BUILD_DIR}"/operations/*/state.json 2>/dev/null | while IFS='|' read -r name merged_at; do
    # Just need timestamp filtering now
    merged_epoch=$(timestamp_to_epoch "${merged_at}")
    [[ -n "${merged_epoch}" ]] && [[ "${merged_epoch}" -ge "${cutoff_time}" ]] && echo "${name}|${merged_at}"
  done | sort -t'|' -k2 -r
fi
```

**Savings**: Reduces N jq calls to 1

### Phase 5: Extend show_status Batch Read

**Current**: sm_read_state_fields reads 18 fields, but 2 more are read separately
- Line 1033: `merge_commit` read via sm_read_state
- Line 1236: `merge_error` read via sm_read_state

**Optimized**: Add these to the batch read
```bash
IFS=$'\t' read -r phase op_type feature_id machine session current_issue \
  last_activity merge_queued merge_status merged_at after eager worker_pid \
  worker_log worker_started_at error_msg held held_at worktree merge_commit merge_error <<< \
  "$(sm_read_state_fields "${NAME}" phase type epic_id machine tmux_session \
     current_issue last_activity merge_queued merge_status merged_at \
     after eager worker_pid worker_log worker_started_at error held held_at worktree \
     merge_commit merge_error)"
```

**Savings**: Reduces 2 sm_read_state calls to 0 (absorbed into existing batch)

## Key Implementation Details

### Bash 3.2 Compatibility

The codebase targets bash 3.2 (macOS default). Associative arrays require bash 4+. Alternative approach for Phase 1-2:

```bash
# Use newline-separated key=value pairs instead of associative arrays
queue_data=$(jq -r '.entries[] | "\(.operation)=\(.status)=\(.updated_at // "")"' "${queue_file}")

# Lookup function
lookup_queue_status() {
  local op="$1"
  echo "${queue_data}" | grep "^${op}=" | cut -d= -f2
}
```

Or use file-based caching:
```bash
# Cache to temp file once
queue_cache=$(mktemp)
jq -r '.entries[] | [.operation, .status, (.updated_at // "")] | @tsv' "${queue_file}" > "${queue_cache}"

# Lookup via grep
queue_entry_status=$(grep "^${name}"$'\t' "${queue_cache}" | cut -f2)
```

### Error Handling

All jq calls should preserve existing `2>/dev/null || true` patterns to handle missing files gracefully.

## Verification Plan

1. **Unit tests**: Run existing tests
   ```bash
   make test-file FILE=tests/unit/v0-status.bats
   ```

2. **Manual testing**: Compare output before/after
   ```bash
   # Create test operations
   v0 feature test1
   v0 feature test2 --after test1

   # Compare outputs
   v0 status --list > /tmp/before.txt
   # Apply changes
   v0 status --list > /tmp/after.txt
   diff /tmp/before.txt /tmp/after.txt
   ```

3. **Performance testing**: Measure with many operations
   ```bash
   time v0 status --list --no-hints
   ```

4. **Linting**:
   ```bash
   make lint
   ```

## Summary of Expected Savings

| Phase | Before | After | Reduction |
|-------|--------|-------|-----------|
| 1 | 2×N calls | 1 call | 2N-1 |
| 2 | 4 calls | 1 call | 3 |
| 3 | 2 jq -s | 1 jq -s | 1 |
| 4 | N calls | 1 call | N-1 |
| 5 | 2 calls | 0 calls | 2 |

For a typical run with 5 operations: ~20 jq calls reduced to ~5 jq calls.
