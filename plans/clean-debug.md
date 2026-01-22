# Implementation Plan: Remove tmux capture from log output

## Overview

Remove all `tmux capture-pane` usage from the idle detection loops in v0-feature and v0-feature-worker. This functionality captures terminal output to detect when Claude agents go idle, but it's noisy and never provides useful debugging information. Replace with simpler file modification time-based idle detection.

## Project Structure

Files to modify:
```
bin/
  v0-feature           # Lines 785, 939 - idle detection using tmux capture
  v0-feature-worker    # Lines 238, 377 - idle detection using tmux capture
lib/
  debug-common.sh      # Lines 105, 111 - comments referencing tmux captures
```

## Dependencies

None - this is a removal/simplification of existing functionality.

## Implementation Phases

### Phase 1: Replace tmux capture in v0-feature-worker (Plan Phase)

**File**: `bin/v0-feature-worker`
**Location**: Lines 228-252 (run_plan_phase monitoring loop)

**Current approach** (~line 238):
```bash
CURRENT_OUTPUT=$(tmux capture-pane -t "${PLAN_SESSION}" -p 2>/dev/null | tail -5 | md5sum)
if [[ "${CURRENT_OUTPUT}" = "${LAST_OUTPUT}" ]]; then
  IDLE_COUNT=$((IDLE_COUNT + 1))
  ...
fi
LAST_OUTPUT="${CURRENT_OUTPUT}"
```

**New approach**: Use plan file modification time to detect idle:
```bash
CURRENT_MTIME=$(stat -f %m "${PLAN_FILE}" 2>/dev/null || stat -c %Y "${PLAN_FILE}" 2>/dev/null || echo "0")
if [[ "${CURRENT_MTIME}" = "${LAST_MTIME}" ]]; then
  IDLE_COUNT=$((IDLE_COUNT + 1))
  ...
fi
LAST_MTIME="${CURRENT_MTIME}"
```

**Changes needed**:
1. Replace `LAST_OUTPUT=""` with `LAST_MTIME=""`
2. Determine plan file path before the loop (or use the existing condition)
3. Replace tmux capture with stat on the plan file

### Phase 2: Replace tmux capture in v0-feature-worker (Decompose Phase)

**File**: `bin/v0-feature-worker`
**Location**: Lines 368-392 (decompose phase monitoring loop)

**Current approach** (~line 377):
```bash
CURRENT_OUTPUT=$(tmux capture-pane -t "${FEATURE_SESSION}" -p 2>/dev/null | tail -5 | md5sum)
```

**New approach**: Use plan file modification time:
```bash
CURRENT_MTIME=$(stat -f %m "${PLAN_FILE}" 2>/dev/null || stat -c %Y "${PLAN_FILE}" 2>/dev/null || echo "0")
```

**Changes needed**: Same pattern as Phase 1, but for the decompose/feature session loop.

### Phase 3: Replace tmux capture in v0-feature (Plan Phase)

**File**: `bin/v0-feature`
**Location**: Lines 775-799 (plan session monitoring loop)

**Current approach** (~line 785):
```bash
CURRENT_OUTPUT=$(tmux capture-pane -t "${PLAN_SESSION}" -p 2>/dev/null | tail -5 | md5sum)
```

**New approach**: Same file modification time pattern:
```bash
# Find which plan file exists
PLAN_FILE=""
if [[ -f "${TREE_DIR}/${V0_PLANS_DIR}/${NAME}.md" ]]; then
  PLAN_FILE="${TREE_DIR}/${V0_PLANS_DIR}/${NAME}.md"
elif [[ -f "${WORKTREE}/${V0_PLANS_DIR}/${NAME}.md" ]]; then
  PLAN_FILE="${WORKTREE}/${V0_PLANS_DIR}/${NAME}.md"
elif [[ -f "${PLANS_DIR}/${NAME}.md" ]]; then
  PLAN_FILE="${PLANS_DIR}/${NAME}.md"
fi

CURRENT_MTIME=$(stat -f %m "${PLAN_FILE}" 2>/dev/null || stat -c %Y "${PLAN_FILE}" 2>/dev/null || echo "0")
```

### Phase 4: Replace tmux capture in v0-feature (Decompose Phase)

**File**: `bin/v0-feature`
**Location**: Lines 930-954 (decompose session monitoring loop)

**Current approach** (~line 939):
```bash
CURRENT_OUTPUT=$(tmux capture-pane -t "${FEATURE_SESSION}" -p 2>/dev/null | tail -5 | md5sum)
```

**New approach**: Same file modification time pattern using `PLAN_FILE`.

### Phase 5: Update debug-common.sh comments

**File**: `lib/debug-common.sh`

Remove references to "tmux captures" in comments since tmux capture is no longer used:

**Line 105** - Change:
```bash
# This prevents tmux captures containing debug output from being included in logs
```
To:
```bash
# This prevents debug report YAML from being included when logs contain other debug output
```

**Line 111** - Change:
```bash
# This removes terminal color codes and cursor controls from tmux captures
```
To:
```bash
# This removes terminal color codes and cursor controls from log content
```

### Phase 6: Verification

Run tests to ensure idle detection still works:
```bash
make lint
make test
```

Manual verification:
1. Run a v0 feature with planning enabled
2. Verify the plan phase terminates correctly after idle
3. Verify the decompose phase terminates correctly after idle

## Key Implementation Details

### Why file mtime instead of tmux capture?

1. **Simplicity**: `stat` is available on all systems; no dependency on tmux pane state
2. **Reliability**: File modification time is a definitive signal that writing has stopped
3. **No noise**: Removes terminal escape sequences, cursor movements, and other tmux artifacts
4. **Same semantics**: If the file hasn't been modified in IDLE_THRESHOLD iterations (12+ seconds), the agent is done

### Cross-platform stat compatibility

The code already handles this elsewhere in the codebase:
```bash
# macOS uses -f %m, Linux uses -c %Y
stat -f %m "${FILE}" 2>/dev/null || stat -c %Y "${FILE}" 2>/dev/null
```

### Edge case: plan file not yet created

The idle detection loop already guards against this with:
```bash
if [[ -f "${PLAN_FILE}" ]]; then
  # ... idle detection here
fi
```

This remains unchanged - idle detection only runs after the file exists.

## Verification Plan

1. **Linting**: `make lint` - Ensure no shell script issues introduced
2. **Unit tests**: `make test` - Ensure existing tests pass
3. **Manual test**: Run `v0 feature test-feature "test prompt"` and verify:
   - Plan phase completes and terminates after idle
   - Decompose phase (if applicable) completes and terminates after idle
   - No tmux capture-related output in logs
