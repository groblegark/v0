#!/usr/bin/env bats
# Tests for V0_GIT_REMOTE configuration

load '../helpers/test_helper'

# ============================================================================
# V0_GIT_REMOTE Configuration Tests
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

@test "V0_GIT_REMOTE custom value is exported for subprocesses" {
    cat > "${TEST_TEMP_DIR}/project/.v0.rc" <<'EOF'
PROJECT="testproj"
ISSUE_PREFIX="tp"
V0_GIT_REMOTE="upstream"
EOF
    cd "${TEST_TEMP_DIR}/project" || return 1
    source_lib "v0-common.sh"
    v0_load_config

    # Check that custom value is exported
    run bash -c 'echo $V0_GIT_REMOTE'
    assert_success
    assert_output "upstream"
}

@test "v0_init_config includes V0_GIT_REMOTE in template" {
    cd "${TEST_TEMP_DIR}/project" || return 1
    rm -f .v0.rc  # Remove any existing config

    # Mock wk init to avoid wk dependency
    setup_mock_binaries wk

    source_lib "v0-common.sh"
    v0_init_config

    # Check that the generated .v0.rc contains V0_GIT_REMOTE option
    assert_file_exists "${TEST_TEMP_DIR}/project/.v0.rc"
    run grep "V0_GIT_REMOTE" "${TEST_TEMP_DIR}/project/.v0.rc"
    assert_success
    assert_output --partial 'V0_GIT_REMOTE="origin"'
}

# ============================================================================
# Template Tests
# ============================================================================

@test "claude.feature.m4 uses V0_GIT_REMOTE in git push commands" {
    local template_file="${PROJECT_ROOT}/lib/templates/claude.feature.m4"

    # Check that template references V0_GIT_REMOTE
    run grep "V0_GIT_REMOTE" "${template_file}"
    assert_success
}

@test "uncommitted.md uses V0_GIT_REMOTE placeholder" {
    local prompt_file="${PROJECT_ROOT}/lib/prompts/uncommitted.md"

    # Check that prompt has the placeholder
    run grep "__V0_GIT_REMOTE__" "${prompt_file}"
    assert_success
}
