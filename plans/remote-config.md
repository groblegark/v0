# Remote Configuration Plan

## Overview

Add support for a configurable `V0_GIT_REMOTE` setting that allows users to specify which git remote to use for push/fetch operations. All automation, scripts, templates, and prompts will respect this configuration instead of hardcoding "origin".

## Project Structure

Key files to modify:

```
lib/v0-common.sh           # Add V0_GIT_REMOTE default and export
lib/worker-common.sh       # Update git fetch to use V0_GIT_REMOTE
bin/v0-mergeq              # Update all git remote operations
lib/templates/claude.feature.m4  # Template git push with remote
lib/templates/claude.fix.md      # Update push documentation
lib/templates/claude.chore.md    # Update push documentation
lib/prompts/uncommitted.md       # Template git push with remote
.v0.rc                     # Document V0_GIT_REMOTE option
tests/unit/v0-common.bats  # Test V0_GIT_REMOTE configuration
tests/unit/v0-mergeq.bats  # Test remote usage in mergeq
tests/fixtures/configs/    # Add test config with custom remote
```

## Dependencies

- No external dependencies required
- Relies on existing `.v0.rc` configuration mechanism

## Implementation Phases

### Phase 1: Add Configuration Support

**Goal**: Add `V0_GIT_REMOTE` to configuration loading with "origin" as default.

**Files to modify**:
- `lib/v0-common.sh`

**Changes**:
1. Add `V0_GIT_REMOTE="origin"` to defaults in `v0_load_config()` (after line 128)
2. Export `V0_GIT_REMOTE` alongside other variables (line 160)

```bash
# In v0_load_config(), add to defaults section:
V0_GIT_REMOTE="origin"

# In export section:
export V0_GIT_REMOTE
```

3. Update `v0_init_config()` template to include commented `V0_GIT_REMOTE` option

**Verification**: Run `make lint` and existing tests pass.

---

### Phase 2: Update Shell Scripts

**Goal**: Replace all hardcoded "origin" references with `${V0_GIT_REMOTE}`.

**Files to modify**:

#### lib/v0-common.sh (line 703)
```bash
# Before:
git fetch origin "${branch}" --quiet 2>/dev/null || true

# After:
git fetch "${V0_GIT_REMOTE}" "${branch}" --quiet 2>/dev/null || true
```

#### lib/worker-common.sh (line 342)
```bash
# Before:
git -C "${git_dir}" fetch origin main >> "${polling_log}" 2>&1 || true

# After:
git -C "${git_dir}" fetch "${V0_GIT_REMOTE:-origin}" main >> "${polling_log}" 2>&1 || true
```

Note: Use `${V0_GIT_REMOTE:-origin}` as fallback since worker-common.sh may be sourced before config is loaded.

#### bin/v0-mergeq (multiple locations)

| Line | Operation | Update |
|------|-----------|--------|
| 412 | `git ls-remote --heads origin` | `git ls-remote --heads "${V0_GIT_REMOTE}"` |
| 422 | `git ls-remote --heads origin` | `git ls-remote --heads "${V0_GIT_REMOTE}"` |
| 475 | `git ls-remote --heads origin` | `git ls-remote --heads "${V0_GIT_REMOTE}"` |
| 622 | `git pull --ff-only origin` | `git pull --ff-only "${V0_GIT_REMOTE}"` |
| 635 | `git fetch origin "${branch}"` | `git fetch "${V0_GIT_REMOTE}" "${branch}"` |
| 658 | `git push origin "${V0_MAIN_BRANCH}"` | `git push "${V0_GIT_REMOTE}" "${V0_MAIN_BRANCH}"` |
| 671 | `git push origin --delete` | `git push "${V0_GIT_REMOTE}" --delete` |
| 711 | `git fetch origin "${branch}"` | `git fetch "${V0_GIT_REMOTE}" "${branch}"` |
| 734 | `git push origin HEAD:` | `git push "${V0_GIT_REMOTE}" HEAD:` |
| 737 | `git push origin --delete` | `git push "${V0_GIT_REMOTE}" --delete` |
| 786-789 | Help text with "origin" | Update to use configured remote |

**Verification**: Run `make lint` and `make test`.

---

### Phase 3: Update Templates and Prompts

**Goal**: Template git push/fetch commands to use the configured remote.

**Files to modify**:

#### lib/templates/claude.feature.m4

The m4 template already uses `changequote` for templating. Add a new define:

```m4
# At top of file, add:
define([[V0_REMOTE]], [[V0_GIT_REMOTE]])dnl

# Line 56, change:
git push

# To:
git push V0_REMOTE

# Line 69, change:
git push

# To:
git push V0_REMOTE
```

Alternatively, since m4 is complex, we could use a simpler approach by having the template generator substitute `__V0_GIT_REMOTE__` placeholders.

#### lib/templates/claude.fix.md (line 14)
```markdown
# Before:
`./fixed <id>` - pushes, queues merge, closes bug, **exits session**

# After (if we want to be explicit):
`./fixed <id>` - pushes to remote, queues merge, closes bug, **exits session**
```

This file documents the `./fixed` script behavior, so it may not need the remote name explicitly - the script itself will use the configured remote.

#### lib/templates/claude.chore.md (line 14)
Same as claude.fix.md - documents `./fixed` behavior.

#### lib/prompts/uncommitted.md (line 39)
```markdown
# Before:
git push

# After:
git push __V0_GIT_REMOTE__
```

The prompt generator will need to substitute `__V0_GIT_REMOTE__` with the actual value.

**Implementation approach for templates**:
Since templates are read and used by various scripts, the cleanest approach is to:
1. Have templates use a placeholder like `__V0_GIT_REMOTE__`
2. Update the script that uses the template to substitute the placeholder with the actual `V0_GIT_REMOTE` value using `sed`

**Verification**: Manual test by examining generated CLAUDE.md files.

---

### Phase 4: Update Template Generators

**Goal**: Ensure scripts that generate prompts/templates substitute the remote variable.

**Files to identify and update**:
Scripts that use templates from `lib/templates/` or `lib/prompts/`:
- Scripts using `claude.feature.m4` (search for m4 invocation)
- Scripts using prompts (search for `lib/prompts/`)

For each script that reads a template containing `__V0_GIT_REMOTE__`, add substitution:
```bash
# Example:
template_content=$(cat "${V0_DIR}/lib/prompts/uncommitted.md" | sed "s/__V0_GIT_REMOTE__/${V0_GIT_REMOTE}/g")
```

For m4 templates, pass the variable as a define:
```bash
m4 -DV0_GIT_REMOTE="${V0_GIT_REMOTE}" template.m4
```

**Verification**: Run worker commands and verify CLAUDE.md contains correct remote.

---

### Phase 5: Add Tests

**Goal**: Comprehensive test coverage for remote configuration.

**New test file**: `tests/unit/v0-remote-config.bats`

```bash
#!/usr/bin/env bats
# Tests for V0_GIT_REMOTE configuration

load '../helpers/test_helper'

# ============================================================================
# Configuration tests
# ============================================================================

@test "V0_GIT_REMOTE defaults to origin" {
    create_v0rc
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"
    v0_load_config

    assert_equal "${V0_GIT_REMOTE}" "origin"
}

@test "V0_GIT_REMOTE can be customized in .v0.rc" {
    cat > "${TEST_TEMP_DIR}/project/.v0.rc" <<'EOF'
PROJECT="testproj"
ISSUE_PREFIX="tp"
V0_GIT_REMOTE="upstream"
EOF
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"
    v0_load_config

    assert_equal "${V0_GIT_REMOTE}" "upstream"
}

@test "V0_GIT_REMOTE is exported for subprocesses" {
    create_v0rc
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"
    v0_load_config

    # Check that it's in the exported environment
    run bash -c 'echo $V0_GIT_REMOTE'
    assert_success
    assert_output "origin"
}
```

**Additional tests**:

1. **Shell script tests**: Verify `v0-mergeq` uses configured remote
2. **Template tests**: Verify templates contain remote placeholder or correct value
3. **Integration tests**: End-to-end test with custom remote

**Test fixture**: `tests/fixtures/configs/with-custom-remote.v0.rc`
```bash
PROJECT="remoteproj"
ISSUE_PREFIX="rp"
V0_GIT_REMOTE="upstream"
```

**Verification**: `make test` passes with new tests.

---

### Phase 6: Documentation and Cleanup

**Goal**: Document the new configuration option and verify everything works.

**Files to update**:

1. **`.v0.rc` in project root** - Add commented example:
```bash
# V0_GIT_REMOTE="origin"        # Git remote for push/fetch (default: origin)
```

2. **Verify all occurrences** - Run grep to ensure no remaining hardcoded "origin" in push/fetch context:
```bash
grep -rn "git.*origin" lib/ bin/ --include="*.sh" --include="*.m4" --include="*.md"
```

3. **Final verification**:
   - `make lint` passes
   - `make test` passes
   - Manual test with custom remote configured

## Key Implementation Details

### Variable Fallback Pattern

In scripts that may run before config is loaded, use fallback:
```bash
git fetch "${V0_GIT_REMOTE:-origin}" ...
```

### Template Substitution

For templates, use `sed` substitution pattern:
```bash
sed "s/__V0_GIT_REMOTE__/${V0_GIT_REMOTE}/g"
```

### M4 Template Handling

For `.m4` files, pass the define on the command line:
```bash
m4 -DV0_GIT_REMOTE="${V0_GIT_REMOTE}" template.m4
```

Or use the existing changequote mechanism with a new define.

### User Feedback in Error Messages

When git operations fail, include the remote name in error messages:
```bash
echo "Failed to push to ${V0_GIT_REMOTE}" >&2
```

## Verification Plan

1. **Unit tests**: New `v0-remote-config.bats` with config tests
2. **Integration tests**: Update existing v0-mergeq tests to verify remote usage
3. **Linting**: `make lint` must pass
4. **Manual verification**:
   - Create `.v0.rc` with `V0_GIT_REMOTE="upstream"`
   - Run `v0 status` and verify no errors
   - Examine generated CLAUDE.md files for correct remote
5. **Regression testing**: All existing tests must pass

### Test Matrix

| Component | Test Type | Verification |
|-----------|-----------|--------------|
| v0_load_config | Unit | Default and custom remote values |
| v0-mergeq | Unit | Remote variable used in git commands |
| Templates | Integration | Placeholders substituted correctly |
| Prompts | Integration | Generated prompts use correct remote |
| End-to-end | Manual | Full workflow with custom remote |
