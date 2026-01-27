#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# workspace/plan-commit.sh - Commit plans to V0_DEVELOP_BRANCH via workspace
#
# Depends on: create.sh, validate.sh
# IMPURE: Uses git, file system operations

# Expected environment variables:
# V0_WORKSPACE_DIR - Path to workspace directory
# V0_DEVELOP_BRANCH - Main development branch name
# V0_GIT_REMOTE - Git remote name
# V0_PLANS_DIR - Plans directory name (e.g., "plans")

# ws_commit_plan_to_develop <name> <source_file>
# Commit a plan file to V0_DEVELOP_BRANCH via the workspace
# Uses retry-on-push-failure for concurrent safety
# Returns: 0 on success, 1 on failure
ws_commit_plan_to_develop() {
  local name="$1"
  local source_file="$2"

  if [[ -z "${name}" ]] || [[ -z "${source_file}" ]]; then
    echo "Error: ws_commit_plan_to_develop requires <name> <source_file>" >&2
    return 1
  fi

  if [[ ! -f "${source_file}" ]]; then
    echo "Error: Source file does not exist: ${source_file}" >&2
    return 1
  fi

  # Ensure workspace exists and is synced
  if ! ws_ensure_workspace; then
    echo "Error: Failed to ensure workspace" >&2
    return 1
  fi

  if ! ws_sync_to_develop; then
    echo "Error: Failed to sync workspace to ${V0_DEVELOP_BRANCH}" >&2
    return 1
  fi

  # Create plans directory in workspace if needed
  local plans_dir="${V0_WORKSPACE_DIR}/${V0_PLANS_DIR:-plans}"
  mkdir -p "${plans_dir}"

  # Copy plan to workspace
  local dest_file="${plans_dir}/${name}.md"
  if ! /bin/cp "${source_file}" "${dest_file}"; then
    echo "Error: Failed to copy plan to workspace" >&2
    return 1
  fi

  # Check if plan already committed with same content
  if git -C "${V0_WORKSPACE_DIR}" diff --quiet -- "${V0_PLANS_DIR:-plans}/${name}.md" 2>/dev/null && \
     git -C "${V0_WORKSPACE_DIR}" ls-files --error-unmatch "${V0_PLANS_DIR:-plans}/${name}.md" &>/dev/null; then
    # Plan exists and unchanged
    return 0
  fi

  # Stage and commit the plan
  if ! git -C "${V0_WORKSPACE_DIR}" add "${V0_PLANS_DIR:-plans}/${name}.md"; then
    echo "Error: Failed to stage plan" >&2
    return 1
  fi

  # Check if there's anything to commit
  if git -C "${V0_WORKSPACE_DIR}" diff --cached --quiet 2>/dev/null; then
    # Nothing to commit (file unchanged)
    return 0
  fi

  if ! git -C "${V0_WORKSPACE_DIR}" commit -m "Add plan: ${name}" -m "Auto-committed by v0 build"; then
    echo "Error: Failed to commit plan" >&2
    return 1
  fi

  # Push with retry for concurrent safety
  # If push fails (another worker pushed), pull --rebase and retry
  if ! git -C "${V0_WORKSPACE_DIR}" push "${V0_GIT_REMOTE}" "${V0_DEVELOP_BRANCH}" 2>/dev/null; then
    if git -C "${V0_WORKSPACE_DIR}" pull --rebase "${V0_GIT_REMOTE}" "${V0_DEVELOP_BRANCH}" && \
       git -C "${V0_WORKSPACE_DIR}" push "${V0_GIT_REMOTE}" "${V0_DEVELOP_BRANCH}"; then
      return 0
    else
      echo "Error: Failed to push plan after retry" >&2
      return 1
    fi
  fi

  return 0
}

# ws_get_plan_from_develop <name> <dest_file>
# Retrieve a plan file from V0_DEVELOP_BRANCH via the workspace
# Returns: 0 on success, 1 if plan not found
ws_get_plan_from_develop() {
  local name="$1"
  local dest_file="$2"

  if [[ -z "${name}" ]] || [[ -z "${dest_file}" ]]; then
    echo "Error: ws_get_plan_from_develop requires <name> <dest_file>" >&2
    return 1
  fi

  # Ensure workspace exists and is synced
  if ! ws_ensure_workspace; then
    echo "Error: Failed to ensure workspace" >&2
    return 1
  fi

  if ! ws_sync_to_develop; then
    echo "Error: Failed to sync workspace to ${V0_DEVELOP_BRANCH}" >&2
    return 1
  fi

  # Check if plan exists in workspace
  local source_file="${V0_WORKSPACE_DIR}/${V0_PLANS_DIR:-plans}/${name}.md"
  if [[ ! -f "${source_file}" ]]; then
    return 1
  fi

  # Copy plan to destination
  local dest_dir
  dest_dir=$(dirname "${dest_file}")
  mkdir -p "${dest_dir}"

  if ! /bin/cp "${source_file}" "${dest_file}"; then
    echo "Error: Failed to copy plan from workspace" >&2
    return 1
  fi

  return 0
}
