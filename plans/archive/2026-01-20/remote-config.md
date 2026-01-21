# Remote Configuration Plan

## Overview

Add support for a configurable `V0_GIT_REMOTE` setting that allows users to specify which git remote to use for push/fetch operations. All automation, scripts, templates, and prompts will respect this configuration instead of hardcoding "origin".

## Project Structure

Key files to modify:

```
lib/v0-common.sh           # [DONE] V0_GIT_REMOTE default and export already added
lib/worker-common.sh       # Update git fetch to use V0_GIT_REMOTE
bin/v0-mergeq              # Update all git remote operations
bin/v0-merge               # Update git push operations
bin/v0-fix                 # Update git push/fetch operations
bin/v0-chore               # Update git push/fetch operations
lib/templates/claude.feature.m4  # Template git push with remote
lib/prompts/uncommitted.md       # Template git push with remote
lib/hooks/stop-feature.sh        # Template error message git push
tests/unit/v0-remote-config.bats # New test file for V0_GIT_REMOTE
tests/unit/v0-common.bats        # Add V0_GIT_REMOTE configuration tests
```

## Dependencies

- No external dependencies required
- Relies on existing `.v0.rc` configuration mechanism

## Implementation Phases

### Phase 1: Configuration Support ✓ COMPLETE

`V0_GIT_REMOTE` is already added to `lib/v0-common.sh`:
- Line 130: `V0_GIT_REMOTE="origin"` default in `v0_load_config()`
- Line 164: `export V0_GIT_REMOTE`
- Line 277: Commented example in `v0_init_config()` template

---

### Phase 2: Update Shell Scripts

**Goal**: Replace all hardcoded "origin" references with `${V0_GIT_REMOTE}`.

#### lib/v0-common.sh (line 706)
```bash
# Before:
git fetch origin "${branch}" --quiet 2>/dev/null || true

# After:
git fetch "${V0_GIT_REMOTE}" "${branch}" --quiet 2>/dev/null || true
```

#### lib/worker-common.sh

Search for any `git fetch origin` or `git push origin` patterns and replace with `${V0_GIT_REMOTE:-origin}` (using fallback since worker-common.sh may be sourced before config is loaded).

#### bin/v0-mergeq

| Line | Operation | Update |
|------|-----------|--------|
| 412 | `git ls-remote --heads origin` | `git ls-remote --heads "${V0_GIT_REMOTE}"` |
| 422 | `git ls-remote --heads origin` | `git ls-remote --heads "${V0_GIT_REMOTE}"` |
| 622 | `git pull --ff-only origin` | `git pull --ff-only "${V0_GIT_REMOTE}"` |
| 635 | `git fetch origin "${branch}"` | `git fetch "${V0_GIT_REMOTE}" "${branch}"` |
| 658 | `git push origin "${V0_MAIN_BRANCH}"` | `git push "${V0_GIT_REMOTE}" "${V0_MAIN_BRANCH}"` |
| 671 | `git push origin --delete` | `git push "${V0_GIT_REMOTE}" --delete` |
| 711 | `git fetch origin "${branch}"` | `git fetch "${V0_GIT_REMOTE}" "${branch}"` |
| 734 | `git push origin HEAD:` | `git push "${V0_GIT_REMOTE}" HEAD:` |
| 737 | `git push origin --delete` | `git push "${V0_GIT_REMOTE}" --delete` |
| 786-789 | Help text examples | Update to show `${V0_GIT_REMOTE}` usage |

#### bin/v0-merge

| Line | Operation | Update |
|------|-----------|--------|
| 586 | `git push origin --delete "${BRANCH}"` | `git push "${V0_GIT_REMOTE}" --delete "${BRANCH}"` |
| 626 | `git push origin --delete "${BRANCH}"` | `git push "${V0_GIT_REMOTE}" --delete "${BRANCH}"` |

#### bin/v0-fix

| Line | Operation | Update |
|------|-----------|--------|
| 202 | `git push -u origin` | `git push -u "${V0_GIT_REMOTE}"` |
| 234 | `git fetch origin main` | `git fetch "${V0_GIT_REMOTE}" main` |
| 279 | `git push -u origin` | `git push -u "${V0_GIT_REMOTE}"` |
| 307 | `git fetch origin main` | `git fetch "${V0_GIT_REMOTE}" main` |

#### bin/v0-chore

| Line | Operation | Update |
|------|-----------|--------|
| 198 | `git fetch origin main` | `git fetch "${V0_GIT_REMOTE}" main` |
| 243 | `git push -u origin` | `git push -u "${V0_GIT_REMOTE}"` |
| 271 | `git fetch origin main` | `git fetch "${V0_GIT_REMOTE}" main` |

**Verification**: Run `make lint` and `make test`.

---

### Phase 3: Update Templates and Prompts

**Goal**: Template git push/fetch commands to use the configured remote.

#### lib/templates/claude.feature.m4

Pass `V0_GIT_REMOTE` as an m4 define and use it in the template:

```m4
# Lines 56, 69 change from:
git push

# To:
git push V0_GIT_REMOTE
```

The template generators (bin/v0-feature, bin/v0-feature-worker) must pass the define:
```bash
M4_ARGS="-DV0_GIT_REMOTE=${V0_GIT_REMOTE} ..."
m4 ${M4_ARGS} template.m4
```

#### lib/prompts/uncommitted.md (line 39)

Change from:
```markdown
git push
```

To:
```markdown
git push __V0_GIT_REMOTE__
```

Scripts using this prompt must substitute the placeholder:
```bash
sed "s/__V0_GIT_REMOTE__/${V0_GIT_REMOTE}/g"
```

#### lib/hooks/stop-feature.sh (line 64)

The error message contains hardcoded `git push`:
```bash
# Before:
echo "{\"decision\": \"block\", \"reason\": \"... && git push\"}"

# After:
echo "{\"decision\": \"block\", \"reason\": \"... && git push ${V0_GIT_REMOTE}\"}"
```

**Verification**: Manual test by examining generated CLAUDE.md files and hook output.

---

### Phase 4: Update Template Generators

**Goal**: Ensure scripts that generate prompts/templates substitute the remote variable.

**Files to update**:

1. **bin/v0-feature** - Find m4 invocation and add `-DV0_GIT_REMOTE="${V0_GIT_REMOTE}"`
2. **bin/v0-feature-worker** - Same as above
3. **Scripts using uncommitted.md** - Add sed substitution for `__V0_GIT_REMOTE__`

Search for usages:
```bash
grep -rn "uncommitted.md" bin/ lib/
grep -rn "claude.feature.m4" bin/ lib/
```

**Verification**: Run worker commands and verify generated CLAUDE.md contains correct remote.

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

# ============================================================================
# Script usage tests
# ============================================================================

@test "v0-mergeq uses V0_GIT_REMOTE for git operations" {
    # Verify mergeq script contains ${V0_GIT_REMOTE} not hardcoded origin
    run grep -c 'git.*"\${V0_GIT_REMOTE}"' "${V0_DIR}/bin/v0-mergeq"
    assert_success
    # Should have multiple occurrences
    [ "${output}" -ge 5 ]
}

@test "v0-fix uses V0_GIT_REMOTE for git operations" {
    run grep -c 'V0_GIT_REMOTE' "${V0_DIR}/bin/v0-fix"
    assert_success
    [ "${output}" -ge 2 ]
}

@test "v0-chore uses V0_GIT_REMOTE for git operations" {
    run grep -c 'V0_GIT_REMOTE' "${V0_DIR}/bin/v0-chore"
    assert_success
    [ "${output}" -ge 2 ]
}

# ============================================================================
# Template tests
# ============================================================================

@test "claude.feature.m4 uses V0_GIT_REMOTE placeholder" {
    run grep -c 'V0_GIT_REMOTE' "${V0_DIR}/lib/templates/claude.feature.m4"
    assert_success
    [ "${output}" -ge 2 ]
}

@test "uncommitted.md uses V0_GIT_REMOTE placeholder" {
    run grep -c '__V0_GIT_REMOTE__\|V0_GIT_REMOTE' "${V0_DIR}/lib/prompts/uncommitted.md"
    assert_success
}

# ============================================================================
# No hardcoded origin tests
# ============================================================================

@test "no hardcoded origin in git push/fetch operations in bin scripts" {
    # Check that bin scripts don't have hardcoded 'origin' in git commands
    # Exclude test fixtures and documentation
    run bash -c "grep -l 'git.*origin' ${V0_DIR}/bin/v0-mergeq ${V0_DIR}/bin/v0-merge ${V0_DIR}/bin/v0-fix ${V0_DIR}/bin/v0-chore 2>/dev/null || true"
    assert_output ""
}
```

**Test fixture**: `tests/fixtures/configs/with-custom-remote.v0.rc`
```bash
PROJECT="remoteproj"
ISSUE_PREFIX="rp"
V0_GIT_REMOTE="upstream"
```

**Verification**: `make test` passes with new tests.

---

### Phase 6: Verification and Cleanup

**Goal**: Verify all occurrences are updated and run final tests.

**Verification commands**:
```bash
# Check no hardcoded origin remains in git operations
grep -rn "git.*origin" lib/ bin/ --include="*.sh" --include="*.m4" | \
  grep -v "V0_GIT_REMOTE" | \
  grep -v "\.bats:" | \
  grep -v "plans/"

# Should return empty or only acceptable matches (docs, comments)
```

**Final checks**:
1. `make lint` passes
2. `make test` passes
3. Manual test with `V0_GIT_REMOTE="upstream"` in `.v0.rc`:
   - Run `v0 status` - no errors
   - Examine generated CLAUDE.md files for correct remote
   - Trigger a hook and verify error messages use correct remote

## Key Implementation Details

### Variable Fallback Pattern

In scripts that may run before config is loaded, use fallback:
```bash
git fetch "${V0_GIT_REMOTE:-origin}" ...
```

### Template Substitution

For markdown templates, use `sed` substitution pattern:
```bash
sed "s/__V0_GIT_REMOTE__/${V0_GIT_REMOTE}/g"
```

### M4 Template Handling

For `.m4` files, pass the define on the command line:
```bash
m4 -DV0_GIT_REMOTE="${V0_GIT_REMOTE}" template.m4
```

In the template, reference directly:
```m4
git push V0_GIT_REMOTE
```

### User Feedback in Error Messages

When git operations fail, include the remote name in error messages:
```bash
echo "Failed to push to ${V0_GIT_REMOTE}" >&2
```

## Verification Plan

1. **Unit tests**: New `v0-remote-config.bats` with config and script tests
2. **Static analysis**: grep-based tests to verify no hardcoded origin remains
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
| v0-mergeq | Static | Contains ${V0_GIT_REMOTE} references |
| v0-merge | Static | Contains ${V0_GIT_REMOTE} references |
| v0-fix | Static | Contains ${V0_GIT_REMOTE} references |
| v0-chore | Static | Contains ${V0_GIT_REMOTE} references |
| Templates | Static | Contains V0_GIT_REMOTE placeholders |
| Prompts | Static | Contains __V0_GIT_REMOTE__ placeholders |
| End-to-end | Manual | Full workflow with custom remote |

### Files Summary

**Shell scripts requiring updates** (replace hardcoded `origin`):
- `lib/v0-common.sh` - 1 location (line 706)
- `bin/v0-mergeq` - 10 locations
- `bin/v0-merge` - 2 locations
- `bin/v0-fix` - 4 locations
- `bin/v0-chore` - 3 locations

**Templates requiring updates** (add V0_GIT_REMOTE):
- `lib/templates/claude.feature.m4` - 2 locations (lines 56, 69)
- `lib/prompts/uncommitted.md` - 1 location (line 39)
- `lib/hooks/stop-feature.sh` - 1 location (line 64)

**Template generators requiring updates** (pass V0_GIT_REMOTE):
- `bin/v0-feature` - m4 invocation
- `bin/v0-feature-worker` - m4 invocation
- Any script reading `uncommitted.md`

**New test files**:
- `tests/unit/v0-remote-config.bats`
- `tests/fixtures/configs/with-custom-remote.v0.rc`
