# Plan: detect-branch

Enhance `v0 init` to accept `--develop <branch>` and `--remote <name>` arguments, with smart branch detection when no branch is specified.

## Overview

Currently `v0 init [path]` only accepts a directory path. This plan adds:
- `--develop <branch>` flag to specify the target branch for merges
- `--remote <name>` flag to specify the git remote
- Auto-detection of 'develop' branch when no `--develop` is specified
- Fallback to 'main' if 'develop' doesn't exist
- Updated help text and README.md documentation

## Project Structure

Key files to modify:
```
bin/v0                      # Add argument parsing for --develop and --remote
lib/v0-common.sh            # Update v0_init_config() to accept branch/remote params
.v0.rc                      # Verify defaults are commented correctly (already done)
README.md                   # Add documentation for new flags and examples
tests/unit/v0-common.bats   # Add tests for new init flags and branch detection
```

## Dependencies

No new external dependencies. Uses existing git commands:
- `git branch --list <name>` - Check if a branch exists locally
- `git ls-remote --heads <remote> <branch>` - Check if branch exists on remote

## Implementation Phases

### Phase 1: Argument Parsing in `bin/v0`

Add argument parsing for the init subcommand to handle `--develop` and `--remote` flags.

**File:** `bin/v0` (around line 143)

**Current:**
```bash
  init)
    source "${V0_DIR}/lib/v0-common.sh"
    if ! v0_precheck; then
      echo "" >&2
      echo "Please install missing dependencies and try again." >&2
      exit 1
    fi
    shift
    v0_init_config "${1:-.}"
    exit 0
    ;;
```

**New:**
```bash
  init)
    source "${V0_DIR}/lib/v0-common.sh"
    if ! v0_precheck; then
      echo "" >&2
      echo "Please install missing dependencies and try again." >&2
      exit 1
    fi
    shift

    local init_path="."
    local init_develop=""
    local init_remote=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --develop|--branch)
          init_develop="$2"
          shift 2
          ;;
        --remote)
          init_remote="$2"
          shift 2
          ;;
        -*)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
        *)
          init_path="$1"
          shift
          ;;
      esac
    done

    v0_init_config "${init_path}" "${init_develop}" "${init_remote}"
    exit 0
    ;;
```

**Verification:** Run `v0 init --develop feature --remote upstream` and check .v0.rc is created with those values uncommented.

---

### Phase 2: Branch Detection in `v0_init_config()`

Update `v0_init_config()` to accept optional branch and remote parameters, with auto-detection when not specified.

**File:** `lib/v0-common.sh` (function `v0_init_config`, around line 205)

**Add branch detection helper function:**
```bash
# Detect the best default branch for development
# Returns: branch name (develop if exists, otherwise main)
v0_detect_develop_branch() {
  local remote="${1:-origin}"

  # Check if 'develop' exists locally
  if git branch --list develop 2>/dev/null | grep -q develop; then
    echo "develop"
    return 0
  fi

  # Check if 'develop' exists on remote
  if git ls-remote --heads "${remote}" develop 2>/dev/null | grep -q develop; then
    echo "develop"
    return 0
  fi

  # Fallback to main
  echo "main"
}
```

**Update `v0_init_config()` signature:**
```bash
# Initialize v0 configuration
# Args: target_dir [develop_branch] [git_remote]
v0_init_config() {
  local target_dir="${1:-.}"
  local develop_branch="${2:-}"
  local git_remote="${3:-origin}"

  # ... existing directory handling ...

  # Auto-detect branch if not specified
  if [[ -z "${develop_branch}" ]]; then
    develop_branch="$(v0_detect_develop_branch "${git_remote}")"
  fi

  # ... rest of function, update template generation ...
}
```

**Update .v0.rc template generation** to write the detected/specified values:
- If branch is "main" and remote is "origin", keep them commented (defaults)
- If different, write them uncommented

**Verification:**
- `v0 init` in a repo with 'develop' branch → detects and uses 'develop'
- `v0 init` in a repo without 'develop' → falls back to 'main'
- `v0 init --develop staging` → uses 'staging' regardless of detection

---

### Phase 3: Update Help Text

Add init-specific help and update main v0 help.

**File:** `bin/v0` - Add to help text (around line 65):

```
Commands:
  init [path]   Initialize .v0.rc in current directory (or path)
                Options:
                  --develop <branch>  Target branch for merges (auto-detects 'develop', fallback 'main')
                  --remote <name>     Git remote name (default: origin)
```

**Update Examples section:**
```
Examples:
  v0 init                     # Initialize with auto-detected branch
  v0 init --develop agent     # Use 'agent' as the development branch
  v0 init ./myproject --remote upstream  # Init in myproject, use 'upstream' remote
```

**Verification:** Run `v0 --help` and verify the new init options are documented.

---

### Phase 4: Update README.md

Document the new init flags and provide examples.

**File:** `README.md`

**Update Installation section:**
```markdown
Then initialize a project:
```bash
cd /path/to/your/project
v0 init
```

The init command auto-detects your development branch:
- Uses `develop` if it exists (locally or on remote)
- Falls back to `main` otherwise

To specify a different branch or remote:
```bash
v0 init --develop agent              # Use 'agent' branch
v0 init --develop staging --remote upstream
```
```

**Update Configuration section** to clarify the relationship between init flags and .v0.rc:
```markdown
### Configuration via .v0.rc

The `v0 init` command creates `.v0.rc` with sensible defaults. You can override
these by editing the file or by passing flags to `v0 init`:

| Setting | Init Flag | Default |
|---------|-----------|---------|
| V0_DEVELOP_BRANCH | `--develop <branch>` | auto-detect (develop → main) |
| V0_GIT_REMOTE | `--remote <name>` | origin |
```

**Verification:** Review README.md for clarity and completeness.

---

### Phase 5: Add Tests

Add tests for the new functionality.

**File:** `tests/unit/v0-common.bats`

**Tests to add:**

```bash
@test "v0_detect_develop_branch returns develop when it exists locally" {
  cd "$TEST_REPO"
  git branch develop
  run v0_detect_develop_branch
  [ "$status" -eq 0 ]
  [ "$output" = "develop" ]
}

@test "v0_detect_develop_branch returns main when develop does not exist" {
  cd "$TEST_REPO"
  run v0_detect_develop_branch
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "v0_init_config accepts develop branch parameter" {
  cd "$TEST_REPO"
  v0_init_config "." "staging"
  grep -q 'V0_DEVELOP_BRANCH="staging"' .v0.rc
}

@test "v0_init_config accepts remote parameter" {
  cd "$TEST_REPO"
  v0_init_config "." "" "upstream"
  grep -q 'V0_GIT_REMOTE="upstream"' .v0.rc
}

@test "v0_init_config auto-detects develop branch" {
  cd "$TEST_REPO"
  git branch develop
  v0_init_config "."
  grep -q 'V0_DEVELOP_BRANCH="develop"' .v0.rc
}
```

**Verification:** Run `make test` - all tests pass.

---

### Phase 6: Verify .v0.rc Template

Ensure the .v0.rc template shows correct defaults.

**File:** `lib/v0-common.sh` (template in `v0_init_config`)

**Expected template output when using defaults (main/origin):**
```bash
# Optional: Override defaults
# V0_BUILD_DIR=".v0/build"
# V0_PLANS_DIR="plans"
# V0_DEVELOP_BRANCH="main"      # Target branch for merges (default: main)
# ...
# V0_GIT_REMOTE="origin"        # Git remote for push/fetch
```

**Expected template output when using non-defaults:**
```bash
# Optional: Override defaults
# V0_BUILD_DIR=".v0/build"
# V0_PLANS_DIR="plans"
V0_DEVELOP_BRANCH="staging"     # Target branch for merges
# ...
V0_GIT_REMOTE="upstream"        # Git remote for push/fetch
```

**Verification:** Run `v0 init --develop staging --remote upstream` and verify .v0.rc has the values uncommented.

## Key Implementation Details

### Branch Detection Priority

1. Explicit `--develop <branch>` flag → use that branch
2. No flag specified:
   a. Check if 'develop' branch exists locally (`git branch --list develop`)
   b. Check if 'develop' branch exists on remote (`git ls-remote --heads`)
   c. Fall back to 'main'

### Backward Compatibility

- `v0 init` without arguments continues to work
- Existing .v0.rc files are unaffected
- Detection only happens at init time, not on every v0 command

### Template Conditional Logic

```bash
# In v0_init_config(), when generating .v0.rc:
if [[ "${develop_branch}" != "main" ]]; then
  echo "V0_DEVELOP_BRANCH=\"${develop_branch}\""
else
  echo "# V0_DEVELOP_BRANCH=\"main\"      # Target branch for merges (default: main)"
fi

if [[ "${git_remote}" != "origin" ]]; then
  echo "V0_GIT_REMOTE=\"${git_remote}\""
else
  echo "# V0_GIT_REMOTE=\"origin\"        # Git remote for push/fetch"
fi
```

## Verification Plan

### Unit Tests
- [ ] `v0_detect_develop_branch` returns 'develop' when it exists
- [ ] `v0_detect_develop_branch` returns 'main' when 'develop' doesn't exist
- [ ] `v0_init_config` accepts and uses --develop parameter
- [ ] `v0_init_config` accepts and uses --remote parameter
- [ ] `v0_init_config` auto-detects 'develop' branch when available
- [ ] .v0.rc template has correct commented/uncommented values

### Manual Testing
1. Create a new repo without 'develop' branch:
   ```bash
   mkdir /tmp/test-no-develop && cd /tmp/test-no-develop
   git init
   v0 init
   grep V0_DEVELOP_BRANCH .v0.rc  # Should show commented "main"
   ```

2. Create a repo with 'develop' branch:
   ```bash
   mkdir /tmp/test-with-develop && cd /tmp/test-with-develop
   git init && git commit --allow-empty -m "init"
   git branch develop
   v0 init
   grep V0_DEVELOP_BRANCH .v0.rc  # Should show uncommented "develop"
   ```

3. Test explicit flag:
   ```bash
   v0 init --develop agent --remote upstream
   grep V0_DEVELOP_BRANCH .v0.rc  # Should show "agent"
   grep V0_GIT_REMOTE .v0.rc      # Should show "upstream"
   ```

### Linting
```bash
make lint  # All scripts pass ShellCheck
```

### Full Test Suite
```bash
make test  # All tests pass
```
