# Fix Mayor Directory Approach

## Overview

The mayor currently runs Claude from a temporary directory (`/tmp/v0-mayor-$$`) which breaks access to `v0` commands because the temp directory has no `.v0.rc` file. This plan refactors the mayor to run from the project directory (`V0_ROOT`) while still providing a fresh settings configuration each invocation.

## Problem Analysis

**Current Behavior:**
1. Mayor creates temp directory: `${TMPDIR:-/tmp}/v0-mayor-$$`
2. Writes `settings.local.json` to `${MAYOR_SETTINGS_DIR}/.claude/`
3. Changes to temp directory: `cd "${MAYOR_SETTINGS_DIR}"`
4. Runs Claude with `--settings ".claude/settings.local.json"`

**Why This Fails:**
- `v0 status` (in SessionStart hooks) calls `v0_load_config()` which walks up looking for `.v0.rc`
- Temp directory has no `.v0.rc`, so `v0 status` fails
- The error "No v0 project is initialized" appears in Claude's context

**Original Intent:**
- Run from project directory with `--settings` pointing to a different file
- Temp directory was added later to "reset" the settings file on each run (unnecessary complexity)

## Project Structure

```
bin/
  v0-mayor              # Main file to modify
packages/cli/lib/
  v0-common.sh          # v0_load_config used for V0_ROOT detection
  prompts/mayor.md      # Mayor prompt (no changes needed)
tests/
  v0-mayor.bats         # Tests to verify/update
```

## Dependencies

No external dependencies needed. Uses existing:
- `v0_load_config()` from packages/cli/lib/v0-common.sh
- Standard bash utilities (mkdir, cat, exec)

## Implementation Phases

### Phase 1: Load Project Config

**Goal:** Detect `V0_ROOT` before running Claude.

**Changes to `bin/v0-mayor`:**

```bash
# Before line 47 (after parsing args), add:
# Load project config to get V0_ROOT
if ! v0_load_config false; then
    echo "Error: Not in a v0 project directory. Run 'v0 init' first." >&2
    exit 1
fi
```

**Verification:**
- Run `v0 mayor --help` - should still work
- Run `v0 mayor` from project dir - should load config without error
- Run `v0 mayor` from non-project dir - should show clear error

### Phase 2: Write Settings to Project Directory

**Goal:** Replace temp directory with direct write to `V0_ROOT/.claude/`.

**Changes to `bin/v0-mayor`:**

Remove lines 50-52 (temp dir creation):
```bash
# DELETE:
MAYOR_SETTINGS_DIR="${TMPDIR:-/tmp}/v0-mayor-$$"
mkdir -p "${MAYOR_SETTINGS_DIR}/.claude"
```

Replace with:
```bash
# Ensure .claude directory exists in project root
MAYOR_SETTINGS_DIR="${V0_ROOT}"
mkdir -p "${MAYOR_SETTINGS_DIR}/.claude"
```

Update settings file path (line 54):
```bash
# Write fresh settings for this mayor session
cat > "${MAYOR_SETTINGS_DIR}/.claude/settings.mayor.json" <<'SETTINGS'
...
SETTINGS
```

Note: Using `settings.mayor.json` instead of `settings.local.json` to avoid conflicts with project settings.

**Verification:**
- Check `V0_ROOT/.claude/settings.mayor.json` exists after running mayor
- Verify settings content matches expected JSON

### Phase 3: Remove Temp Directory Logic

**Goal:** Clean up unnecessary temp directory code.

**Changes to `bin/v0-mayor`:**

1. Remove wok workspace linking (lines 86-92) - no longer needed since we're in project dir:
```bash
# DELETE entirely:
# Initialize wok workspace link if v0 project has wok tracking
# This allows the mayor to create/manage bugs from the temp directory
if [[ -d "${V0_DIR}/.wok" ]]; then
  ...
fi
```

2. Remove cleanup trap (lines 94-98):
```bash
# DELETE:
cleanup() {
  rm -rf "${MAYOR_SETTINGS_DIR}"
}
trap cleanup EXIT
```

3. Remove cd to temp dir (line 103):
```bash
# CHANGE:
cd "${MAYOR_SETTINGS_DIR}"
# TO:
cd "${V0_ROOT}"
```

**Verification:**
- No temp directories created in `/tmp/v0-mayor-*`
- No orphan temp directories after mayor exits

### Phase 4: Update Claude Invocation

**Goal:** Run Claude from project directory with correct settings path.

**Changes to `bin/v0-mayor` (line 104):**

```bash
# CHANGE:
exec claude --model "${MODEL}" --settings ".claude/settings.local.json" "${PROMPT}" "$@"
# TO:
exec claude --model "${MODEL}" --settings ".claude/settings.mayor.json" "${PROMPT}" "$@"
```

**Verification:**
- Claude launches with correct settings
- SessionStart hooks run successfully (`v0 status` works)
- All v0 commands accessible from mayor session

### Phase 5: Update Tests

**Goal:** Ensure tests pass with new directory approach.

**Changes to `tests/v0-mayor.bats`:**

Most tests check help output and prompt content - these should continue to work.

Add new test to verify project directory requirement:
```bash
@test "v0 mayor requires project directory" {
    # Run from non-project directory
    cd /tmp
    run "${PROJECT_ROOT}/bin/v0-mayor" 2>&1
    assert_failure
    assert_output --partial "Not in a v0 project directory"
}
```

Add test to verify settings file creation:
```bash
@test "v0 mayor creates settings.mayor.json" {
    # Would need to mock claude or check file creation
    # This may be covered by existing integration tests
    skip "Requires mocking claude invocation"
}
```

**Verification:**
- Run `scripts/test v0-mayor` - all tests pass

### Phase 6: Final Verification

**Goal:** End-to-end testing of the complete change.

**Manual Testing:**
1. `cd` to a v0 project directory
2. Run `v0 mayor`
3. Verify Claude starts without errors
4. Verify `v0 status` works in the mayor session
5. Verify `v0 fix "test bug"` dispatches correctly
6. Exit mayor and verify no orphan temp directories

**Automated Testing:**
- `make check` passes (lint + test + quench)

## Key Implementation Details

### Settings File Location

Using `settings.mayor.json` instead of `settings.local.json`:
- Avoids conflicts with project's own Claude settings
- Clear naming indicates this is mayor-specific
- Still gets overwritten each invocation (fresh settings)

### Session Persistence

Without the temp directory, Claude will use project directory for session identification:
- **Benefit:** Context persists between mayor invocations
- **Potential Issue:** User might want fresh sessions
- **Mitigation:** Can add `--no-resume` flag later if needed (not in scope)

### Error Handling

When not in a project directory:
- Clear error message: "Not in a v0 project directory. Run 'v0 init' first."
- Exit with code 1
- No partial state created

### Backwards Compatibility

- No breaking changes to command-line interface
- Same flags (`--model`, `--help`) work identically
- Mayor behavior from user perspective is unchanged (just works better)

## Verification Plan

1. **Unit Tests:**
   - `scripts/test v0-mayor` - all existing tests pass
   - New test for project directory requirement

2. **Integration Tests:**
   - Manual test: start mayor, run `v0 status`, dispatch a fix
   - Verify no temp directories in `/tmp/v0-mayor-*`

3. **Linting:**
   - `make lint` passes (ShellCheck)

4. **Full Suite:**
   - `make check` passes all checks
