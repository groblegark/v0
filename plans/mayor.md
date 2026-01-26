# v0 mayor - Implementation Plan

## Overview

Add a `v0 mayor` command that launches Claude as an orchestration assistant. Unlike worker commands (build, fix, chore), mayor runs interactively in the current terminal without worktrees or tmux. The mayor is primed with project context and can help dispatch work to v0 workers.

## Project Structure

```
bin/
  v0-mayor                          # New command script
packages/cli/lib/
  prompts/
    mayor.md                        # Mayor prompt template
```

## Dependencies

- Existing v0 infrastructure (`v0-common.sh`)
- Claude CLI (`claude`)
- Optional: `wk` for issue tracking (graceful fallback if unavailable)

## Implementation Phases

### Phase 1: Create the mayor command script

Create `bin/v0-mayor` following the simple command pattern from `v0-talk`:

```bash
#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# v0-mayor - Launch Claude as orchestration assistant
# Usage: v0 mayor [args]

set -e

V0_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${V0_DIR}/packages/cli/lib/v0-common.sh"

usage() {
  v0_help <<'EOF'
Usage: v0 mayor [options] [claude-args...]

Launch Claude as an orchestration assistant for managing v0 workers.

The mayor runs interactively (no worktree, no tmux) and is primed with
project context to help you:
  - Plan and dispatch features
  - Queue bug fixes
  - Process chores
  - Monitor worker status
  - Organize and prioritize work

Options:
  --model <model>   Override model (default: opus)
  -h, --help        Show this help

Examples:
  v0 mayor                 # Start mayor session
  v0 mayor --model sonnet  # Use faster model
EOF
  exit 0
}

MODEL="opus"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done

PROMPT_FILE="${V0_DIR}/packages/cli/lib/prompts/mayor.md"
PROMPT="$(cat "${PROMPT_FILE}")"

exec claude --model "${MODEL}" "${PROMPT}" "$@"
```

**Verification:** Run `v0 mayor --help` and confirm usage displays correctly.

### Phase 2: Create the mayor prompt template

Create `packages/cli/lib/prompts/mayor.md` with instructions for the orchestration role:

```markdown
# Mayor Mode

You are the mayor - an orchestration assistant for managing v0 workers.

## Initial Setup

Run these commands to prime your context:

1. **v0 prime** - Quick-start guide for v0 workflows
2. **wk prime** - Load issue tracking context (if wk is available)

## Your Responsibilities

Help the user with:

### Dispatching Work
- `v0 feature <name> "<description>"` - Full feature pipeline
- `v0 fix "<bug description>"` - Submit to fix worker
- `v0 chore "<task>"` - Submit maintenance task
- `v0 plan <name> "<description>"` - Create plan only

### Monitoring Progress
- `v0 status` - Show all operations
- `v0 watch` - Continuous monitoring
- `v0 attach <type>` - Attach to worker session

### Managing Work
- `v0 cancel <name>` - Cancel operation
- `v0 hold <name>` - Pause before merge
- `v0 resume <name>` - Resume held operation

### Issue Tracking (if wk available)
- `wk list` - Show open issues
- `wk show <id>` - Issue details
- `wk new <type> "<title>"` - Create issue

## Guidelines

1. **Ask clarifying questions** before dispatching complex features
2. **Suggest breaking down** large requests into smaller features
3. **Check status** before starting new work to avoid overloading
4. **Use appropriate workers**: fix for bugs, chore for maintenance, feature for new functionality
5. **Help prioritize** when multiple items are pending

## Context Recovery

If you lose context (after compaction or long pause), run:
- `v0 prime` - Refresh v0 knowledge
- `wk prime` - Refresh issue context (if available)
- `v0 status` - See current state
```

**Verification:** Read the prompt file and confirm it contains the expected content.

### Phase 3: Add session hooks for automatic priming

Enhance the mayor to automatically configure Claude hooks that run `v0 prime` and `wk prime` on session events. Modify `bin/v0-mayor` to write a temporary settings file:

```bash
# Add to bin/v0-mayor before exec claude

# Create temporary settings for mayor session
MAYOR_SETTINGS_DIR="${V0_STATE_DIR:-.v0}/.mayor-session"
mkdir -p "${MAYOR_SETTINGS_DIR}/.claude"

cat > "${MAYOR_SETTINGS_DIR}/.claude/settings.local.json" <<'SETTINGS'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "v0 prime"},
          {"type": "command", "command": "wk prime 2>/dev/null || true"}
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "v0 prime"},
          {"type": "command", "command": "wk prime 2>/dev/null || true"}
        ]
      }
    ]
  }
}
SETTINGS

# Run claude with the settings directory
exec claude --model "${MODEL}" --settings-dir "${MAYOR_SETTINGS_DIR}" "${PROMPT}" "$@"
```

**Note:** This approach may need adjustment based on Claude CLI's `--settings-dir` behavior. Alternative: use environment variable or inherit from project `.claude/settings.local.json`.

**Verification:** Start mayor session, confirm hooks run `v0 prime` output appears.

### Phase 4: Integration testing

Add integration test `tests/v0-mayor.bats`:

```bash
#!/usr/bin/env bats
# Test v0 mayor command

load '../packages/test-support/helpers/test_helper'

setup() {
  setup_test_environment
}

teardown() {
  cleanup_test_environment
}

@test "v0 mayor --help shows usage" {
  run v0 mayor --help
  assert_success
  assert_output --partial "orchestration assistant"
  assert_output --partial "v0 feature"
}

@test "v0 mayor prompt file exists" {
  [[ -f "${V0_DIR}/packages/cli/lib/prompts/mayor.md" ]]
}

@test "v0 mayor prompt contains required sections" {
  run cat "${V0_DIR}/packages/cli/lib/prompts/mayor.md"
  assert_success
  assert_output --partial "v0 prime"
  assert_output --partial "wk prime"
  assert_output --partial "Dispatching Work"
}
```

**Verification:** Run `scripts/test v0-mayor` and confirm all tests pass.

## Key Implementation Details

### Model Selection

Default to `opus` for quality orchestration decisions. The mayor needs to:
- Understand complex feature requests
- Make good decomposition decisions
- Remember context across the session

Opus is appropriate for this interactive orchestration role.

### No Worktree or tmux

Unlike worker commands, mayor runs directly in the user's terminal:
- Interactive back-and-forth conversation
- User can see all output immediately
- No need for isolation (mayor doesn't modify code directly)
- Can be interrupted with Ctrl+C

### Graceful wk Fallback

The `wk` command is optional. The prompt and hooks should handle its absence:
- Use `wk prime 2>/dev/null || true` to suppress errors
- Prompt mentions "if wk available" for issue tracking features
- Core v0 functionality works without wk

### Settings Inheritance

Consider whether mayor should:
1. **Use project settings** - inherit from `.claude/settings.local.json`
2. **Use dedicated settings** - create temporary settings for session
3. **Merge both** - add hooks while keeping project settings

Option 3 is ideal but complex. Start with option 2 (dedicated settings) for simplicity.

## Verification Plan

1. **Unit verification (Phase 1)**
   - `v0 mayor --help` displays usage
   - `v0 mayor --model sonnet --help` accepts model flag

2. **Prompt verification (Phase 2)**
   - Prompt file exists at expected path
   - Contains all required sections
   - No syntax errors in markdown

3. **Hook verification (Phase 3)**
   - Start mayor session
   - Confirm `v0 prime` output appears
   - Verify `wk prime` runs (or fails silently if wk unavailable)

4. **Integration verification (Phase 4)**
   - All bats tests pass
   - `make lint` passes (shellcheck)
   - `make check` passes (full suite)

5. **Manual verification**
   - Start `v0 mayor`
   - Ask it to show v0 status
   - Ask it to queue a feature
   - Verify it understands the v0 workflow
