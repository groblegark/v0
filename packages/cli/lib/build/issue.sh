#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# Issue filing utilities for v0-build
# Source this file to get issue filing functions

# file_plan_issue <name> <plan_file>
# Creates a single feature issue for the plan
# Returns: issue ID on stdout, or empty string on failure
file_plan_issue() {
  local name="$1"
  local plan_file="$2"
  local title="Plan: ${name}"
  local description

  # Read plan file contents as description
  if [[ ! -f "${plan_file}" ]]; then
    return 1
  fi
  description=$(cat "${plan_file}")

  # Create feature issue with plan content as description
  local issue_id
  issue_id=$(wk new feature "${title}" --description "${description}" --output id 2>/dev/null) || return 1

  # Add label
  wk label "${issue_id}" "plan:${name}" 2>/dev/null || true

  echo "${issue_id}"
}
