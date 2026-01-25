# Implementation Plan: `--after` Argument for v0 fix/chore

## Overview

Add an `--after` argument to `v0 fix` and `v0 chore` commands that accepts comma-separated issue IDs. When specified, the created bug/chore will be marked as blocked by those issues using wok's dependency system (`wk dep <id> blocked-by <deps>`). This hides the issue from `wk ready` until dependencies are resolved.

Unlike `v0 feature/plan/etc`, this does NOT store state internally - it leverages wok's native dependency tracking.

## Project Structure

Files to modify:
```
bin/v0-fix       # Add --after argument parsing and wk dep call
bin/v0-chore     # Add --after argument parsing and wk dep call
```

Files for testing:
```
tests/v0-fix.bats     # Add tests for --after flag
tests/v0-chore.bats   # Add tests for --after flag (if exists, else create)
```

## Dependencies

- `wk dep` command from wok (already available)
- No new external dependencies required

## Implementation Phases

### Phase 1: Update `v0 fix` Argument Parsing

**Goal:** Parse `--after` arguments and merge multiple occurrences.

**Changes to `bin/v0-fix`:**

1. Add `AFTER_IDS` array variable at top of script
2. Replace simple case dispatch with a while-loop argument parser
3. Collect `--after` values (comma-separated) into the array
4. Pass remaining args to `report_bug`

**Pattern:**
```bash
# Before main dispatch, parse arguments
AFTER_IDS=()
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --after)
      # Split comma-separated IDs and add to array
      IFS=',' read -ra ids <<< "$2"
      AFTER_IDS+=("${ids[@]}")
      shift 2
      ;;
    --after=*)
      IFS=',' read -ra ids <<< "${1#--after=}"
      AFTER_IDS+=("${ids[@]}")
      shift
      ;;
    --start|--stop|--status|--logs|--err|--history|--history=*|-h|--help)
      # Handle flags that don't take bug description
      # (existing case logic)
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Restore positional parameters for existing dispatch logic
set -- "${POSITIONAL[@]}"
```

### Phase 2: Integrate Dependencies in `report_bug`

**Goal:** After creating a bug, add `blocked-by` dependencies if `--after` was specified.

**Changes to `report_bug()` function:**

```bash
report_bug() {
  local input="$*"
  # ... existing title/description extraction ...

  # ... existing wk new bug call ...

  id=$(echo "${output}" | grep -oE "$(v0_issue_pattern)" | head -1)

  # ... existing error handling ...

  # NEW: Add blocked-by dependencies if --after was specified
  if [[ ${#AFTER_IDS[@]} -gt 0 ]]; then
    if ! wk dep "${id}" blocked-by "${AFTER_IDS[@]}" 2>/dev/null; then
      echo "Warning: Failed to add dependencies"
    else
      echo "  Blocked by: ${AFTER_IDS[*]}"
    fi
  fi

  echo -e "${C_GREEN}Created bug:${C_RESET} ${C_CYAN}${id}${C_RESET}"
  # ... rest of function ...
}
```

### Phase 3: Update `v0 chore` with Same Pattern

**Goal:** Apply identical changes to `v0 chore`.

Replicate Phase 1 and Phase 2 changes in `bin/v0-chore`:
1. Add argument parsing loop before main dispatch
2. Update `report_chore()` to add dependencies

### Phase 4: Update Usage/Help Text

**Goal:** Document the new `--after` flag.

Update `usage()` function in both scripts:

```bash
usage() {
  cat <<EOF
Usage: v0 fix [options] <description>
       v0 fix --status | --start | --stop | --logs | --history

Report bugs and manage the bug-fixing worker.

Options:
  --after <ids>   Block this bug until specified issues complete
                  Accepts comma-separated IDs (e.g., v0-123,v0-456)
                  Can be specified multiple times to add more blockers
  --start         Start the worker (auto-starts on bug report)
  --stop          Stop the worker
  --status        Show worker status and queued bugs
  ...
EOF
}
```

### Phase 5: Add Tests

**Goal:** Verify `--after` functionality works correctly.

**Tests for `tests/v0-fix.bats`:**

```bash
@test "v0 fix --after creates bug with dependency" {
  # Create a blocking issue first
  run wk new task "Blocking task"
  blocker_id=$(echo "$output" | grep -oE 'v0-[0-9]+')

  # Create bug with --after
  run v0 fix --after "$blocker_id" "Bug blocked by task"
  assert_success
  assert_output --partial "Blocked by:"

  # Extract new bug ID
  bug_id=$(echo "$output" | grep -oE 'v0-[0-9]+' | tail -1)

  # Verify dependency exists
  run wk show "$bug_id"
  assert_output --partial "blocked-by"
  assert_output --partial "$blocker_id"
}

@test "v0 fix --after accepts comma-separated IDs" {
  run wk new task "Task 1"
  id1=$(echo "$output" | grep -oE 'v0-[0-9]+')
  run wk new task "Task 2"
  id2=$(echo "$output" | grep -oE 'v0-[0-9]+')

  run v0 fix --after "$id1,$id2" "Bug with multiple blockers"
  assert_success

  bug_id=$(echo "$output" | grep -oE 'v0-[0-9]+' | tail -1)
  run wk show "$bug_id"
  assert_output --partial "$id1"
  assert_output --partial "$id2"
}

@test "v0 fix merges multiple --after arguments" {
  run wk new task "Task 1"
  id1=$(echo "$output" | grep -oE 'v0-[0-9]+')
  run wk new task "Task 2"
  id2=$(echo "$output" | grep -oE 'v0-[0-9]+')

  run v0 fix --after "$id1" --after "$id2" "Bug with merged blockers"
  assert_success

  bug_id=$(echo "$output" | grep -oE 'v0-[0-9]+' | tail -1)
  run wk show "$bug_id"
  assert_output --partial "$id1"
  assert_output --partial "$id2"
}

@test "v0 fix bug not in ready list when blocked" {
  run wk new task "Blocking task"
  blocker_id=$(echo "$output" | grep -oE 'v0-[0-9]+')

  run v0 fix --after "$blocker_id" "Blocked bug"
  bug_id=$(echo "$output" | grep -oE 'v0-[0-9]+' | tail -1)

  # Bug should NOT appear in ready list
  run wk ready
  refute_output --partial "$bug_id"

  # Complete the blocker
  run wk done "$blocker_id"

  # Now bug should appear in ready list
  run wk ready
  assert_output --partial "$bug_id"
}
```

## Key Implementation Details

### Argument Parsing Strategy

The current scripts use a simple `case` statement on `$1`. To support `--after` mixed with positional args (the bug description), we need a proper argument parsing loop:

```bash
# Key pattern: separate flag parsing from dispatch
AFTER_IDS=()
ACTION=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --after)     AFTER_IDS+=("${2//,/ }"); shift 2 ;;
    --after=*)   AFTER_IDS+=("${1#--after=}"); shift ;;
    --start)     ACTION="start"; shift ;;
    --stop)      ACTION="stop"; shift ;;
    # ... other flags ...
    *)           POSITIONAL+=("$1"); shift ;;
  esac
done

# Then dispatch based on ACTION or positional args
case "${ACTION:-report}" in
  start)  start_worker ;;
  stop)   stop_worker ;;
  report) report_bug "${POSITIONAL[*]}" ;;
esac
```

### Handling Invalid Issue IDs

The `wk dep` command will fail if an issue ID doesn't exist. We should:
1. Let `wk dep` handle validation
2. Show a warning but don't fail the bug creation
3. The bug is still created, just without the dependency

### No State Storage Required

Unlike `v0 feature --after`, which stores blocking info in state files and implements a state machine:
- We use `wk dep blocked-by` which persists in wok's database
- `wk ready` automatically filters blocked issues
- No resume/polling logic needed - wok handles it

## Verification Plan

1. **Unit verification:**
   ```bash
   # Create blocker
   wk new task "Blocker"  # Returns v0-1

   # Create blocked bug
   v0 fix --after v0-1 "Test bug"  # Returns v0-2

   # Verify dependency
   wk show v0-2  # Should show blocked-by: v0-1
   wk ready      # Should NOT show v0-2

   # Complete blocker
   wk done v0-1
   wk ready      # Should now show v0-2
   ```

2. **Run test suite:**
   ```bash
   scripts/test v0-fix v0-chore
   ```

3. **Run full check:**
   ```bash
   make check
   ```

4. **Manual testing scenarios:**
   - `v0 fix --after v0-1 "description"` - single blocker
   - `v0 fix --after v0-1,v0-2 "description"` - comma-separated
   - `v0 fix --after v0-1 --after v0-2 "description"` - multiple flags merged
   - `v0 fix --after nonexistent "description"` - invalid ID warning
   - `v0 chore --after v0-1 "description"` - same for chores
