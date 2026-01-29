#!/usr/bin/env bats
# Tests for v0-common.sh - Utility functions

load '../../test-support/helpers/test_helper'
load 'helpers'

# ============================================================================
# v0_issue_pattern() tests
# ============================================================================

@test "v0_issue_pattern generates correct regex" {
    source_lib "v0-common.sh"
    export ISSUE_PREFIX="myp"

    run v0_issue_pattern
    assert_success
    assert_output "myp-[a-z0-9]+"
}

@test "v0_issue_pattern uses configured ISSUE_PREFIX" {
    source_lib "v0-common.sh"
    export ISSUE_PREFIX="testprefix"

    run v0_issue_pattern
    assert_success
    assert_output "testprefix-[a-z0-9]+"
}

@test "v0_issue_pattern matches expected patterns" {
    source_lib "v0-common.sh"
    export ISSUE_PREFIX="proj"

    local pattern
    pattern=$(v0_issue_pattern)

    # Test that pattern matches valid issue IDs
    echo "proj-abc123" | grep -qE "${pattern}"
    echo "proj-a1b2c3" | grep -qE "${pattern}"
}

# ============================================================================
# v0_expand_branch() tests
# ============================================================================

@test "v0_expand_branch expands {name} and {id} placeholders" {
    source_lib "v0-common.sh"

    run v0_expand_branch "feature/{name}" "auth"
    assert_success
    assert_output "feature/auth"

    run v0_expand_branch "fix/{id}" "abc123"
    assert_success
    assert_output "fix/abc123"
}

@test "v0_expand_branch works with custom prefixes" {
    source_lib "v0-common.sh"

    run v0_expand_branch "feat/{name}" "login"
    assert_success
    assert_output "feat/login"
}

@test "v0_expand_branch handles both placeholders" {
    source_lib "v0-common.sh"

    # Test that {name} works when using it
    run v0_expand_branch "work/{name}" "task"
    assert_success
    assert_output "work/task"

    # And {id} also expands to same value
    run v0_expand_branch "work/{id}" "task"
    assert_success
    assert_output "work/task"
}

@test "v0_expand_branch preserves templates without placeholders" {
    source_lib "v0-common.sh"

    run v0_expand_branch "static-branch" "ignored"
    assert_success
    assert_output "static-branch"
}

# ============================================================================
# v0_log() tests
# ============================================================================

@test "v0_log creates log directory if needed" {
    setup_v0_project
    v0_log "test_event" "test message"
    assert_dir_exists "${BUILD_DIR}/logs"
}

@test "v0_log writes to log file" {
    setup_v0_project
    v0_log "test_event" "test message"
    assert_file_exists "${BUILD_DIR}/logs/v0.log"
    run cat "${BUILD_DIR}/logs/v0.log"
    assert_output --partial "test_event"
    assert_output --partial "test message"
}

@test "v0_log includes timestamp" {
    setup_v0_project
    v0_log "event" "msg"
    run cat "${BUILD_DIR}/logs/v0.log"
    # Timestamp format: [YYYY-MM-DDTHH:MM:SSZ]
    assert_output --regexp '\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]'
}

@test "v0_log appends to existing log" {
    setup_v0_project
    v0_log "event1" "message1"
    v0_log "event2" "message2"
    run cat "${BUILD_DIR}/logs/v0.log"
    assert_output --partial "event1"
    assert_output --partial "event2"
}

# ============================================================================
# v0_check_deps() tests
# ============================================================================

@test "v0_check_deps succeeds when dependencies present" {
    source_lib "v0-common.sh"

    # Single dependency
    run v0_check_deps "echo"
    assert_success

    # Multiple dependencies
    run v0_check_deps "echo" "cat" "ls"
    assert_success
}

@test "v0_check_deps fails with missing dependency" {
    source_lib "v0-common.sh"

    run v0_check_deps "nonexistent_command_xyz123"
    assert_failure
    assert_output --partial "Missing required commands"
    assert_output --partial "nonexistent_command_xyz123"
}

@test "v0_check_deps reports all missing dependencies" {
    source_lib "v0-common.sh"

    run v0_check_deps "echo" "missing_cmd1" "cat" "missing_cmd2"
    assert_failure
    assert_output --partial "missing_cmd1"
    assert_output --partial "missing_cmd2"
}

# ============================================================================
# v0_ensure_state_dir() tests
# ============================================================================

@test "v0_ensure_state_dir creates state directory" {
    setup_v0_project "testproj" "tp"
    v0_ensure_state_dir
    assert_dir_exists "${V0_STATE_DIR}"
}

# ============================================================================
# v0_ensure_build_dir() tests
# ============================================================================

@test "v0_ensure_build_dir creates build directory" {
    setup_v0_project
    v0_ensure_build_dir
    assert_dir_exists "${BUILD_DIR}"
}

# ============================================================================
# V0_INSTALL_DIR tests
# ============================================================================

@test "V0_INSTALL_DIR is set correctly" {
    source_lib "v0-common.sh"

    assert [ -n "${V0_INSTALL_DIR}" ]
    assert [ -d "${V0_INSTALL_DIR}" ]
    assert [ -d "${V0_INSTALL_DIR}/packages" ]
}

# ============================================================================
# v0_session_name() tests
# ============================================================================

@test "v0_session_name generates namespaced names" {
    setup_v0_project "myapp" "ma"
    local result
    result=$(v0_session_name "worker" "fix")
    assert_equal "${result}" "v0-myapp-worker-fix"
}

@test "v0_session_name fails without PROJECT" {
    source_lib "v0-common.sh"
    unset PROJECT

    run v0_session_name "worker" "fix"
    assert_failure
    assert_output --partial "PROJECT not set"
}

@test "v0_session_name with different suffixes and types" {
    setup_v0_project "testproj" "tp"
    run v0_session_name "worker" "chore"
    assert_success
    assert_output "v0-testproj-worker-chore"
    run v0_session_name "polling" "fix"
    assert_success
    assert_output "v0-testproj-polling-fix"
    run v0_session_name "auth" "plan"
    assert_success
    assert_output "v0-testproj-auth-plan"
    run v0_session_name "api" "feature"
    assert_success
    assert_output "v0-testproj-api-feature"
}

@test "v0_session_name handles hyphenated suffixes" {
    setup_v0_project "proj" "p"
    run v0_session_name "feature-auth" "merge-resolve"
    assert_success
    assert_output "v0-proj-feature-auth-merge-resolve"
}

# ============================================================================
# v0_clean_log_file() tests
# ============================================================================

@test "v0_clean_log_file removes ANSI escape sequences" {
    source_lib "v0-common.sh"

    local log_file="${TEST_TEMP_DIR}/test.log"
    # Create log with ANSI escape codes
    printf 'Normal line\n\x1b[38;2;255;107;128mcolored text\x1b[39m\nAnother line\n' > "${log_file}"

    v0_clean_log_file "${log_file}"

    # Should contain text without escape codes
    assert [ -f "${log_file}" ]
    run cat "${log_file}"
    assert_output "Normal line
colored text
Another line"
}

@test "v0_clean_log_file handles missing file gracefully" {
    source_lib "v0-common.sh"

    # Should not fail for non-existent file
    run v0_clean_log_file "/nonexistent/file.log"
    assert_success
}

@test "v0_clean_log_file handles empty file" {
    source_lib "v0-common.sh"

    local log_file="${TEST_TEMP_DIR}/empty.log"
    touch "${log_file}"

    run v0_clean_log_file "${log_file}"
    assert_success
    assert [ -f "${log_file}" ]
}

# ============================================================================
# v0_resolve_to_wok_id() tests
# ============================================================================

@test "v0_resolve_to_wok_id returns wok ticket ID as-is" {
    setup_v0_project "testproj" "v0"
    run v0_resolve_to_wok_id "v0-abc123"
    assert_success
    assert_output "v0-abc123"
}

@test "v0_resolve_to_wok_id resolves operation name to epic_id" {
    setup_v0_project "testproj" "v0"
    mkdir -p "${BUILD_DIR}/operations/test-op"
    echo '{"epic_id": "v0-xyz789"}' > "${BUILD_DIR}/operations/test-op/state.json"
    run v0_resolve_to_wok_id "test-op"
    assert_success
    assert_output "v0-xyz789"
}

@test "v0_resolve_to_wok_id fails for unknown operation" {
    setup_v0_project "testproj" "v0"
    run v0_resolve_to_wok_id "nonexistent-op"
    assert_failure
}

@test "v0_resolve_to_wok_id fails for operation without epic_id" {
    setup_v0_project "testproj" "v0"
    mkdir -p "${BUILD_DIR}/operations/early-op"
    echo '{"phase": "init"}' > "${BUILD_DIR}/operations/early-op/state.json"
    run v0_resolve_to_wok_id "early-op"
    assert_failure
}

@test "v0_resolve_to_wok_id handles different issue prefixes" {
    setup_v0_project "testproj" "proj"
    run v0_resolve_to_wok_id "proj-abc123"
    assert_success
    assert_output "proj-abc123"
}

@test "v0_resolve_to_wok_id distinguishes between ID patterns and operation names" {
    setup_v0_project "testproj" "v0"
    mkdir -p "${BUILD_DIR}/operations/auth"
    echo '{"epic_id": "v0-authepic"}' > "${BUILD_DIR}/operations/auth/state.json"
    run v0_resolve_to_wok_id "auth"
    assert_success
    assert_output "v0-authepic"
}
