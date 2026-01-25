# Background Pruning Implementation Plan

## Overview

Implement background log and queue pruning so that `v0 prune` exits quickly while actual pruning happens asynchronously. Pruning will also run periodically (every 1 hour) via a daemon process. The `v0 shutdown` command will block until any active pruning completes to ensure clean shutdown.

## Project Structure

```
packages/core/lib/
  pruning.sh           # Existing: v0_prune_logs, v0_prune_mergeq (unchanged)
  prune-daemon.sh      # NEW: Daemon control functions

bin/
  v0-prune             # MODIFY: Start background daemon instead of blocking
  v0-prune-daemon      # NEW: Long-running daemon process
  v0-shutdown          # MODIFY: Wait for prune daemon before exit

packages/core/tests/
  prune-daemon.bats    # NEW: Unit tests for daemon functions

tests/
  v0-prune-daemon.bats # NEW: Integration tests for daemon behavior
```

## Dependencies

No new external dependencies. Uses existing tools:
- `nohup` - Background process execution
- `kill` - Signal handling
- `date` - Time calculations
- `sleep` - Periodic scheduling

## Implementation Phases

### Phase 1: Create Prune Daemon Library

Create `packages/core/lib/prune-daemon.sh` with daemon control functions following the established pattern from `packages/mergeq/lib/daemon.sh`.

**Functions to implement:**

```bash
# PID file: ${BUILD_DIR}/.prune-daemon.pid
# Lock file: ${BUILD_DIR}/.prune-daemon.lock (for run-once exclusion)
# Log file: ${BUILD_DIR}/logs/prune-daemon.log

# Check if daemon is running
prune_daemon_running() {
  if [[ -f "${PRUNE_DAEMON_PID_FILE}" ]]; then
    local pid
    pid=$(cat "${PRUNE_DAEMON_PID_FILE}")
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      return 0
    fi
    rm -f "${PRUNE_DAEMON_PID_FILE}"
  fi
  return 1
}

# Get daemon PID
prune_daemon_pid()

# Start the daemon
prune_daemon_start()

# Stop the daemon gracefully
prune_daemon_stop()

# Wait for daemon to complete (for shutdown)
prune_daemon_wait()

# Signal daemon to run now (skip to next cycle)
prune_daemon_trigger()
```

**Verification:** Unit tests in `packages/core/tests/prune-daemon.bats`

### Phase 2: Create Prune Daemon Binary

Create `bin/v0-prune-daemon` - a long-running process that:
1. Runs pruning immediately on start
2. Sleeps for 1 hour
3. Repeats until signaled to stop

**Daemon behavior:**

```bash
#!/bin/bash
# Main loop
while true; do
  # Acquire lock to prevent concurrent pruning
  exec 200>"${PRUNE_LOCK_FILE}"
  if flock -n 200; then
    # Run pruning
    v0_prune_mergeq
    v0_prune_logs
    flock -u 200
  fi

  # Sleep for 1 hour (interruptible)
  # Use trap to handle SIGUSR1 for immediate re-run
  # Use trap to handle SIGTERM for graceful exit
  sleep 3600 &
  wait $!
done
```

**Signal handling:**
- `SIGTERM`: Graceful shutdown (finish current prune, exit)
- `SIGUSR1`: Wake immediately (for `v0 prune` to trigger immediate run)

**Verification:** Can start daemon manually and observe periodic runs in log

### Phase 3: Modify v0-prune for Background Execution

Update `bin/v0-prune` to:
1. Start the prune daemon if not running
2. Signal daemon to run immediately (SIGUSR1)
3. Exit quickly without waiting for completion

**Changes:**

```bash
# At end of v0-prune, replace synchronous calls:

# Old (blocking):
# v0_prune_mergeq
# v0_prune_logs

# New (background):
if [[ -n "${DRY_RUN}" ]]; then
  # Dry-run still runs synchronously to show output
  v0_prune_mergeq --dry-run
  v0_prune_logs --dry-run
else
  prune_daemon_start  # Start if not running
  prune_daemon_trigger  # Signal immediate run
  echo "Pruning logs in background..."
fi
```

**Verification:** `v0 prune` exits in < 1 second, logs show pruning happens after

### Phase 4: Modify v0-shutdown to Block on Prune

Update `bin/v0-shutdown` to wait for the prune daemon to finish before exiting.

**Changes:**

```bash
# After all other shutdown steps, before final message:

if prune_daemon_running; then
  echo "Waiting for background pruning to complete..."
  prune_daemon_wait  # Blocks until daemon exits or finishes current run
fi

# Then do final synchronous prune to catch anything new
v0_prune_mergeq
v0_prune_logs
```

**Verification:** `v0 shutdown` waits if daemon is mid-prune

### Phase 5: Integration Testing

Create comprehensive tests in `tests/v0-prune-daemon.bats`:

```bash
@test "v0 prune exits quickly" {
  # Start some work that creates logs
  # Run v0 prune, assert it exits in < 2 seconds
}

@test "background pruning runs after v0 prune" {
  # Create old log entries
  # Run v0 prune
  # Wait briefly, verify logs are pruned
}

@test "v0 shutdown waits for pruning" {
  # Start prune daemon with simulated slow work
  # Run v0 shutdown
  # Verify it waited for daemon
}

@test "periodic pruning every hour" {
  # Use mocked sleep or time injection
  # Verify daemon runs at 1-hour intervals
}
```

**Verification:** `scripts/test v0-prune-daemon` passes

### Phase 6: Update package.sh and Documentation

1. Add `prune-daemon.sh` to `packages/core/package.sh` PKG_EXPORTS
2. Update any help text in commands
3. Ensure `make check` passes

## Key Implementation Details

### PID/Lock File Locations

```bash
PRUNE_DAEMON_PID_FILE="${BUILD_DIR}/.prune-daemon.pid"
PRUNE_DAEMON_LOCK_FILE="${BUILD_DIR}/.prune-daemon.lock"
PRUNE_DAEMON_LOG_FILE="${BUILD_DIR}/logs/prune-daemon.log"
```

### Signal-Based Wake Mechanism

Use `SIGUSR1` to wake the daemon from sleep:

```bash
# In daemon main loop:
trap 'continue' SIGUSR1
trap 'cleanup; exit 0' SIGTERM

while true; do
  do_prune
  sleep 3600 &
  SLEEP_PID=$!
  wait $SLEEP_PID || true  # Interrupted by signal
done
```

```bash
# In prune_daemon_trigger:
prune_daemon_trigger() {
  if prune_daemon_running; then
    kill -USR1 "$(prune_daemon_pid)"
  fi
}
```

### Graceful Wait for Shutdown

The `prune_daemon_wait` function should:
1. Send SIGTERM to daemon
2. Wait for PID file to disappear (daemon exited)
3. Timeout after reasonable period (30s)

```bash
prune_daemon_wait() {
  if ! prune_daemon_running; then
    return 0
  fi

  local pid
  pid=$(prune_daemon_pid)
  kill -TERM "${pid}" 2>/dev/null

  # Wait up to 30 seconds
  local count=0
  while [[ -f "${PRUNE_DAEMON_PID_FILE}" ]] && [[ $count -lt 30 ]]; do
    sleep 1
    count=$((count + 1))
  done
}
```

### Dry-Run Mode Stays Synchronous

When `v0 prune --dry-run` is used, pruning must run synchronously to show output. Only actual pruning runs in background.

### Existing Pruning Functions Unchanged

The `v0_prune_logs` and `v0_prune_mergeq` functions in `packages/core/lib/pruning.sh` remain unchanged. The daemon simply calls them.

## Verification Plan

1. **Unit tests:** `scripts/test core` - tests prune-daemon.sh functions
2. **Integration tests:** `scripts/test v0-prune-daemon` - tests end-to-end behavior
3. **Manual testing:**
   - `v0 prune` exits quickly
   - `tail -f ${BUILD_DIR}/logs/prune-daemon.log` shows activity
   - `v0 shutdown` waits for in-progress prune
4. **Full test suite:** `make check` passes
