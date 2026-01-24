# Plan: Default Branch to 'agent'

## Overview

Change the default development branch from 'main' to 'agent'. When `v0 init` is run without specifying a branch, the system will:
1. Set `V0_DEVELOP_BRANCH="agent"` explicitly in `.v0.rc`
2. Create an `agent` branch if one does not already exist (locally or on the remote)

## Project Structure

Key files to modify:
```
lib/core/config.sh      # v0_detect_develop_branch(), v0_init_config()
tests/unit/v0-common.bats  # Update tests for new default behavior
```

## Dependencies

No new dependencies required. Uses existing git commands for branch creation.

## Implementation Phases

### Phase 1: Update Default Branch Detection

**File:** `lib/core/config.sh:163-182`

Modify `v0_detect_develop_branch()` to return `agent` as the default instead of `main`:

```bash
v0_detect_develop_branch() {
  local remote="${1:-origin}"

  # Check for local develop branch
  if git branch --list develop 2>/dev/null | grep -q develop; then
    echo "develop"
    return 0
  fi

  # Check for remote develop branch
  if git ls-remote --heads "${remote}" develop 2>/dev/null | grep -q develop; then
    echo "develop"
    return 0
  fi

  # Default to agent (not main)
  echo "agent"
}
```

**Verification:** Run detection function with no develop branch present, confirm returns "agent".

### Phase 2: Update Default in v0_load_config()

**File:** `lib/core/config.sh:99`

Change the default fallback:

```bash
# Before:
V0_DEVELOP_BRANCH="main"

# After:
V0_DEVELOP_BRANCH="agent"
```

**Verification:** Source config without .v0.rc present, check V0_DEVELOP_BRANCH equals "agent".

### Phase 3: Create Agent Branch if Missing

**File:** `lib/core/config.sh` inside `v0_init_config()`

After branch detection/selection, add logic to create the agent branch if it doesn't exist:

```bash
v0_init_config() {
  local repo_path="${1:-.}"
  local develop_branch="${2:-}"
  local git_remote="${3:-origin}"

  # ... existing setup ...

  # Auto-detect branch if not specified
  if [[ -z "${develop_branch}" ]]; then
    develop_branch="$(v0_detect_develop_branch "${git_remote}")"
  fi

  # Create agent branch if it doesn't exist (only for 'agent' branch)
  if [[ "${develop_branch}" == "agent" ]]; then
    v0_ensure_agent_branch "${git_remote}"
  fi

  # ... rest of function ...
}
```

Add new helper function:

```bash
# Ensure agent branch exists, creating from current HEAD if needed
v0_ensure_agent_branch() {
  local remote="${1:-origin}"

  # Check if agent branch exists locally
  if git branch --list agent 2>/dev/null | grep -q agent; then
    return 0
  fi

  # Check if agent branch exists on remote
  if git ls-remote --heads "${remote}" agent 2>/dev/null | grep -q agent; then
    # Fetch and create local tracking branch
    git fetch "${remote}" agent 2>/dev/null || true
    git branch agent "${remote}/agent" 2>/dev/null || true
    return 0
  fi

  # Create new agent branch from current HEAD (typically main)
  local base_branch
  base_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

  git branch agent "${base_branch}" 2>/dev/null || {
    echo "Warning: Could not create agent branch" >&2
    return 1
  }

  echo "Created 'agent' branch from '${base_branch}'"
}
```

**Verification:**
- Run `v0 init` in repo without agent branch → agent branch created
- Run `v0 init` in repo with existing agent branch → no error, branch preserved

### Phase 4: Update .v0.rc Template Generation

**File:** `lib/core/config.sh:226-233` (approximate)

Update the smart commenting logic to use "agent" as the new default:

```bash
# Before:
if [[ "${develop_branch}" != "main" ]]; then
  branch_line="V0_DEVELOP_BRANCH=\"${develop_branch}\""
else
  branch_line="# V0_DEVELOP_BRANCH=\"main\"  # (default)"
fi

# After:
if [[ "${develop_branch}" != "agent" ]]; then
  branch_line="V0_DEVELOP_BRANCH=\"${develop_branch}\""
else
  branch_line="V0_DEVELOP_BRANCH=\"${develop_branch}\""  # Always explicit for agent
fi
```

Per the requirements: "set the default branch to agent explicitly in the .v0.rc" — always write the branch even when it's the default.

**Verification:** Run `v0 init`, check .v0.rc contains `V0_DEVELOP_BRANCH="agent"` (not commented).

### Phase 5: Update Tests

**File:** `tests/unit/v0-common.bats`

Update test cases around lines 256-287 and 671-737:

1. Change tests expecting "main" default to expect "agent"
2. Add test case for agent branch creation
3. Verify .v0.rc explicitly contains agent branch setting

Example test updates:

```bash
@test "v0_detect_develop_branch returns agent when no develop branch exists" {
  # ... setup without develop branch ...
  run v0_detect_develop_branch
  assert_output "agent"
}

@test "v0_init_config creates agent branch if missing" {
  # ... setup without agent branch ...
  run v0_init_config "."
  # Verify agent branch was created
  run git branch --list agent
  assert_output --partial "agent"
}

@test "v0_init_config writes explicit agent branch to .v0.rc" {
  run v0_init_config "."
  run grep "V0_DEVELOP_BRANCH" .v0.rc
  assert_output 'V0_DEVELOP_BRANCH="agent"'
}
```

**Verification:** `make test` passes all cases.

## Key Implementation Details

### Branch Creation Strategy

When creating the `agent` branch:
1. Check local branches first (fastest)
2. Check remote branches second (requires network)
3. Create from current HEAD as last resort

This ensures:
- Existing agent branches are respected
- Remote-only agent branches are tracked properly
- New projects get a fresh agent branch from main/master

### Explicit vs Commented Configuration

Unlike other settings that are commented when matching defaults, `V0_DEVELOP_BRANCH="agent"` will always be written explicitly. This makes the configuration self-documenting and ensures clarity about the intended workflow.

### Backward Compatibility

- Existing projects with `.v0.rc` already have their `V0_DEVELOP_BRANCH` set (or defaulted to main)
- This change only affects new `v0 init` runs
- Projects wanting to use `main` can run `v0 init --develop main`

## Verification Plan

1. **Unit tests:** `make test` - all existing and new tests pass
2. **Lint:** `make lint` - no shellcheck warnings
3. **Integration test (manual):**
   - Create fresh git repo
   - Run `v0 init`
   - Verify: `agent` branch exists
   - Verify: `.v0.rc` contains `V0_DEVELOP_BRANCH="agent"`
4. **Existing project test:**
   - Re-init existing project with `--develop main`
   - Verify: Respects explicit override
5. **Full check:** `make check` passes
