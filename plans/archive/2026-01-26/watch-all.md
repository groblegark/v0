# Implementation Plan: v0 watch --all

## Overview

Add a `--all` flag to `v0 watch` that displays status for all running v0 projects on the system in a single view. This enables users to monitor multiple projects from one terminal.

**Key changes:**
1. Track project roots in `~/.local/state/v0/${PROJECT}/.v0.root`
2. Register projects automatically when any v0 command runs
3. Clean up registration on `v0 stop --drop-workspace`
4. Add `--all` flag to `v0 watch` that discovers and displays all active projects

## Project Structure

Files to modify:
```
packages/core/lib/config.sh      # Add v0_register_project() function
bin/v0                           # Allow 'watch --all' without project, update standalone help
bin/v0-watch                     # Add --all flag handling
bin/v0-shutdown                  # Clean up .v0.root on --drop-workspace
README.md                        # Document --all in user guide
docs/arch/commands/v0-watch.md   # Document --all flag
docs/arch/SYSTEM.md              # Document .v0.root file
```

## Dependencies

None - uses existing infrastructure.

## Implementation Phases

### Phase 1: Add project registration function

**File:** `packages/core/lib/config.sh`

Add a function to register the project root, called after config is loaded:

```bash
# Register project root for system-wide discovery
# Creates ~/.local/state/v0/${PROJECT}/.v0.root
v0_register_project() {
  [[ -z "${V0_ROOT:-}" ]] && return 0
  [[ -z "${V0_STATE_DIR:-}" ]] && return 0

  local root_file="${V0_STATE_DIR}/.v0.root"

  # Create state dir if needed
  mkdir -p "${V0_STATE_DIR}"

  # Only write if different (avoid unnecessary disk writes)
  if [[ ! -f "${root_file}" ]] || [[ "$(cat "${root_file}" 2>/dev/null)" != "${V0_ROOT}" ]]; then
    echo "${V0_ROOT}" > "${root_file}"
  fi
}
```

### Phase 2: Call registration from v0_load_config

**File:** `packages/core/lib/config.sh` (~line 179, after exports)

Add call to register project at end of `v0_load_config()`:

```bash
  # Export for subprocesses
  export V0_ROOT PROJECT ISSUE_PREFIX REPO_NAME V0_STATE_DIR BUILD_DIR PLANS_DIR
  # ... existing exports ...

  # Register project root for system-wide discovery (v0 watch --all)
  v0_register_project
}
```

This ensures any command that calls `v0_load_config()` will register the project:
- `v0 start` (calls v0-startup which loads config)
- `v0 fix` / `v0 chore` (load config)
- `v0 build` / `v0 plan` (load config)
- `v0 init` (calls v0_init_config which sets up V0_STATE_DIR)

### Phase 3: Add cleanup on --drop-workspace

**File:** `bin/v0-shutdown` (~line 462, in the --drop-workspace block)

After removing workspace and worktrees, also remove `.v0.root`:

```bash
  # Handle --drop-workspace: remove workspace, worktrees, and project registration
  if [[ -n "${DROP_WORKSPACE}" || -n "${DROP_EVERYTHING}" ]]; then
    # ... existing workspace removal code ...

    # Remove project registration (unregister from v0 watch --all)
    local root_file="${V0_STATE_DIR}/.v0.root"
    if [[ -f "${root_file}" ]]; then
      if [[ -n "${DRY_RUN}" ]]; then
        echo "Would remove project registration: ${root_file}"
      else
        rm -f "${root_file}"
        echo "Removed project registration"
      fi
    fi
  fi
```

### Phase 4: Add --all flag to v0 watch

**File:** `bin/v0-watch`

Add argument parsing for `--all` (~line 39):

```bash
WATCH_ALL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      WATCH_ALL=1
      shift
      ;;
    # ... existing cases ...
  esac
done
```

Add the main watch-all loop before the regular watch loop (~line 125):

```bash
# System-wide watch mode
if [[ -n "${WATCH_ALL}" ]]; then
  V0_STATE_BASE="${XDG_STATE_HOME:-${HOME}/.local/state}/v0"

  # Discover running projects
  discover_running_projects() {
    local projects=()
    for root_file in "${V0_STATE_BASE}"/*/.v0.root; do
      [[ ! -f "${root_file}" ]] && continue
      local project_dir
      project_dir=$(dirname "${root_file}")
      local project
      project=$(basename "${project_dir}")
      [[ "${project}" = "standalone" ]] && continue

      local v0_root
      v0_root=$(cat "${root_file}")
      [[ ! -d "${v0_root}" ]] && continue

      # Check for active tmux sessions (v0-${project}-*)
      if tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -q "^v0-${project}-"; then
        echo "${project}:${v0_root}"
        continue
      fi

      # Check for daemon PID files (mergeq, fix, chore)
      local build_dir="${v0_root}/.v0/build"
      for daemon_dir in mergeq fix chore; do
        local pid_file="${build_dir}/${daemon_dir}/.daemon.pid"
        if [[ -f "${pid_file}" ]]; then
          local pid
          pid=$(cat "${pid_file}")
          if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            echo "${project}:${v0_root}"
            break
          fi
        fi
      done
    done
  }

  # Show header with timestamp
  show_all_header() {
    local now version width
    now=$(date '+%Y-%m-%d %H:%M:%S')
    version=$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null || echo "unknown")
    width=${COLUMNS:-80}
    echo -e "v0 ${C_DIM}${C_LAVENDER}${version}${C_RESET} | ${C_BOLD}System Watch${C_RESET} | ${C_CYAN}${now}${C_RESET} | ${C_DIM}Ctrl+C to exit${C_RESET}"
    local bar=""
    for ((i=0; i<width; i++)); do bar+="═"; done
    printf '%s\n' "${bar}"
  }

  trap 'echo; exit 0' INT TERM

  iteration=0
  while true; do
    [[ -t 1 ]] && clear
    show_all_header

    # Get running projects
    local projects
    projects=$(discover_running_projects)

    if [[ -z "${projects}" ]]; then
      echo ""
      echo -e "${C_DIM}No running v0 projects found${C_RESET}"
      echo ""
      echo "Projects are registered when you run v0 commands (start, build, etc.)"
      echo "Start a project with: v0 start"
    else
      while IFS=':' read -r project v0_root; do
        [[ -z "${project}" ]] && continue
        echo ""
        echo -e "${C_BOLD}▶ ${project}${C_RESET} ${C_DIM}(${v0_root})${C_RESET}"
        echo ""
        # Run v0 status from the project directory
        (cd "${v0_root}" && "${SCRIPT_DIR}/v0-status" --no-hints --max-ops 5 2>/dev/null) | sed 's/^/  /' || true
      done <<< "${projects}"
    fi

    # Check iteration limit (for testing)
    ((iteration++)) || true
    if [[ -n "${MAX_ITERATIONS}" && "${iteration}" -ge "${MAX_ITERATIONS}" ]]; then
      break
    fi

    sleep "${REFRESH_INTERVAL}"
  done

  exit 0
fi
```

Update usage text (~line 17):

```bash
usage() {
  v0_help <<'EOF'
Usage: v0 watch [OPTIONS] [OPERATION]

Continuously watch v0 status output.

Arguments:
  OPERATION             Watch a specific operation by name

Options:
  --all                 Watch all running v0 projects on the system
  -n, --interval SECS   Refresh interval in seconds (default: 5)
  -o, --operation NAME  Watch a specific operation by name
  --fix                 Watch fix worker status only
  --chore               Watch chore worker status only
  --merge               Watch merge queue status only
  --max-iterations N    Exit after N iterations (for testing)
  -h, --help            Show this help message

Press Ctrl+C to exit.
EOF
}
```

### Phase 5: Allow watch --all without project context

**File:** `bin/v0`

The `watch` command currently requires a project. We need to allow `v0 watch --all` to run from anywhere.

**Option 1:** Add special handling for `watch --all` in the dispatch (~line 207):

```bash
  # Project-required commands (with exceptions)
  watch)
    # Allow --all without project context
    if [[ "$1" == "--all" ]]; then
      exec "${V0_DIR}/bin/v0-watch" "$@"
    fi
    # Otherwise require project
    if ! v0_find_project_root >/dev/null 2>&1; then
        v0_check_standalone_mode "${CMD}"
    fi
    exec "${V0_DIR}/bin/v0-watch" "$@"
    ;;
```

**Update standalone mode help message** (~line 54):

```bash
    echo "Available without a project:" >&2
    echo "  v0 chore      - Work on standalone chores" >&2
    echo "  v0 watch --all - Watch all running projects" >&2
    echo "  v0 help       - Show help" >&2
```

### Phase 6: Update README user guide

**File:** `README.md` (~line 140, in "Other Commands" section)

Update the `v0 watch` line to mention `--all`:

```markdown
### Other Commands

```bash
v0 talk          # Interactive Haiku for quick questions
v0 status        # Show all operations
v0 watch         # Continuously refresh status
v0 watch --all   # Watch all running projects (works from anywhere)
v0 attach fix    # Attach to a worker (fix, chore, mergeq or <feature>)
v0 coffee        # Keep computer awake
v0 prune         # Clean up completed state
v0 stop          # Stop all workers and daemons
```
```

### Phase 7: Update architecture documentation

**File:** `docs/arch/commands/v0-watch.md`

Replace the entire file with:

```markdown
# v0-watch

**Purpose:** Continuously watch operation status.

## Workflow

1. Clear screen
2. Show header with timestamp
3. Run `v0-status`
4. Sleep and repeat

## Usage

```bash
v0 watch                # Default (5 second refresh)
v0 watch -n 10          # 10 second refresh
v0 watch auth           # Watch specific operation
v0 watch --fix          # Watch fix worker only
v0 watch --all          # Watch all running projects on system
```

## System-wide Watch (--all)

The `--all` flag monitors all running v0 projects on the system:

```bash
v0 watch --all          # Watch all projects
v0 watch --all -n 10    # 10 second refresh
```

Projects are automatically registered when any v0 command runs (`v0 start`, `v0 build`, etc.). Registration is stored in `~/.local/state/v0/${PROJECT}/.v0.root`.

A project is considered "running" if it has:
- Active tmux sessions matching `v0-${PROJECT}-*`
- Running daemon processes (mergeq, fix, chore workers)

Press Ctrl+C to exit.
```

**File:** `docs/arch/SYSTEM.md` (add to Key Files table ~line 64)

```markdown
| `.v0.root` | Project root path (for `v0 watch --all`) |
```

## Key Implementation Details

### Project Discovery

The `--all` mode discovers projects by:
1. Scanning `~/.local/state/v0/*/` for `.v0.root` files
2. Reading the project root path from each file
3. Checking if the project has active tmux sessions or daemon PIDs
4. Only showing projects that are actually running

### Standalone Mode

`v0 watch --all` works from anywhere - no project context required. This is achieved by:
1. Special-casing `watch --all` in `bin/v0` to bypass project requirement
2. The `--all` mode in `v0-watch` sources only the minimal common functions (colors, etc.)
3. Project discovery uses the global state directory, not `V0_ROOT`

### Registration Timing

Projects are registered:
- On first `v0_load_config()` call (any command that uses config)
- This includes: `v0 start`, `v0 fix`, `v0 chore`, `v0 build`, `v0 plan`, `v0 status`, etc.
- `v0 init` also triggers registration via `v0_init_config()`

### Cleanup Timing

Project registration (`.v0.root`) is removed on:
- `v0 stop --drop-workspace` - explicitly removes `.v0.root`
- `v0 stop --drop-everything` - removes entire `${V0_STATE_DIR}` including `.v0.root`

The distinction is intentional:
- `--drop-workspace` unregisters the project from system watch but preserves other state
- `--drop-everything` removes all state (`.v0.root` is deleted along with the directory)

### Display Format

The `--all` view shows:
```
v0 (1.2.3) | System Watch | 2026-01-26 12:34:56 | Ctrl+C to exit
════════════════════════════════════════════════════════════════

▶ project1 (/path/to/project1)

  [condensed v0 status output...]

▶ project2 (/path/to/project2)

  [condensed v0 status output...]
```

## Verification Plan

1. **Registration test:**
   ```bash
   # In a v0 project
   v0 status
   cat ~/.local/state/v0/${PROJECT}/.v0.root  # Should show project path
   ```

2. **Watch all test:**
   ```bash
   # Start workers in one project
   cd /path/to/project1
   v0 start

   # In another terminal
   v0 watch --all  # Should show project1
   ```

3. **Standalone mode test:**
   ```bash
   cd /tmp  # Not a v0 project
   v0 watch --all --max-iterations 1  # Should work, not error
   ```

4. **Cleanup test:**
   ```bash
   v0 stop --drop-workspace
   cat ~/.local/state/v0/${PROJECT}/.v0.root  # Should not exist
   ```

5. **Help text test:**
   ```bash
   cd /tmp
   v0 status  # Should show "v0 watch --all" in available commands
   ```

6. **Lint and tests:**
   ```bash
   make check
   ```

## Test Cases

Add tests to `tests/v0-watch.bats`:

```bash
@test "v0 watch --all shows help with --help" {
  run v0 watch --help
  assert_success
  assert_output --partial "--all"
  assert_output --partial "Watch all running"
}

@test "v0_register_project creates .v0.root" {
  cd "${TEST_PROJECT}"
  v0 status  # Triggers registration

  local root_file="${V0_STATE_DIR}/.v0.root"
  assert [ -f "${root_file}" ]
  assert_equal "$(cat "${root_file}")" "${TEST_PROJECT}"
}

@test "v0 stop --drop-workspace removes .v0.root" {
  cd "${TEST_PROJECT}"
  v0 status  # Register
  v0 stop --drop-workspace

  local root_file="${V0_STATE_DIR}/.v0.root"
  assert [ ! -f "${root_file}" ]
}

@test "v0 watch --all works outside project directory" {
  cd /tmp  # Not a v0 project
  run v0 watch --all --max-iterations 1
  assert_success
  # Should show "No running v0 projects" or project list, not "Not in a v0 project"
  refute_output --partial "Not in a v0 project"
}
```
