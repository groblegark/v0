#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# operations/schema.sh - Schema versioning and migration
#
# This module provides:
# - Schema migration
# - Auto-migration on access
# - Phase access with schema check
#
# External commands: date (via sm_bulk_update_state, sm_emit_event)

# Requires: SM_STATE_VERSION from rules.sh
# Requires: sm_get_state_file from rules.sh
# Requires: sm_bulk_update_state, sm_get_state_version, sm_read_state from io.sh
# Requires: sm_emit_event from logging.sh

# ============================================================================
# Schema Versioning Functions
# ============================================================================

# sm_migrate_state <op>
# Migrate state file to current schema version
sm_migrate_state() {
  local op="$1"
  local version
  version=$(sm_get_state_version "${op}")

  # Already current
  [[ "${version}" -ge "${SM_STATE_VERSION}" ]] && return 0

  # Migration from v0 (legacy) to v1
  if [[ "${version}" -eq 0 ]]; then
    sm_bulk_update_state "${op}" \
      "_schema_version" "1" \
      "_migrated_at" "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    sm_emit_event "${op}" "schema:migrated" "v0 -> v1"
    version=1
  fi

  # Migration from v1 to v2: Remove after field, migrate to wok
  if [[ "${version}" -eq 1 ]]; then
    local state_file
    state_file=$(sm_get_state_file "${op}")

    # Read current after value before removing
    local after_op epic_id phase
    after_op=$(jq -r '.after // empty' "${state_file}")
    epic_id=$(jq -r '.epic_id // empty' "${state_file}")
    phase=$(jq -r '.phase // empty' "${state_file}")

    # If we have an after dependency and an epic_id, migrate to wok
    if [[ -n "${after_op}" ]] && [[ "${after_op}" != "null" ]] && \
       [[ -n "${epic_id}" ]] && [[ "${epic_id}" != "null" ]]; then
      # Resolve after_op to wok ID
      local blocker_id
      blocker_id=$(v0_resolve_to_wok_id "${after_op}" 2>/dev/null || true)

      if [[ -n "${blocker_id}" ]]; then
        # Add wok dependency (graceful failure)
        if wk dep "${epic_id}" blocked-by "${blocker_id}" 2>/dev/null; then
          sm_emit_event "${op}" "migration:dep_added" "Added wok dep: ${blocker_id}"
        else
          sm_emit_event "${op}" "migration:dep_failed" "Failed to add wok dep: ${blocker_id}"
        fi
      fi
    fi

    # If phase was blocked, change to init (wok will track blocking)
    local new_phase="${phase}"
    if [[ "${phase}" == "blocked" ]]; then
      local blocked_phase
      blocked_phase=$(jq -r '.blocked_phase // "init"' "${state_file}")
      new_phase="${blocked_phase}"
      [[ "${new_phase}" == "null" ]] && new_phase="init"
    fi

    # Remove after, blocked_phase, eager fields from state
    local tmp
    tmp=$(mktemp)
    if jq --arg phase "${new_phase}" \
       'del(.after, .blocked_phase, .eager) | .phase = $phase | ._schema_version = 2 | ._migrated_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
       "${state_file}" > "${tmp}"; then
      mv "${tmp}" "${state_file}"
    else
      rm -f "${tmp}"
    fi

    sm_emit_event "${op}" "schema:migrated" "v1 -> v2 (after field removed)"
  fi
}

# sm_ensure_current_schema <op>
# Called by transition functions to auto-migrate on first access
sm_ensure_current_schema() {
  local op="$1"
  local state_file
  state_file=$(sm_get_state_file "${op}")

  # Skip if no state file
  [[ ! -f "${state_file}" ]] && return 0

  local version
  version=$(jq -r '._schema_version // 0' "${state_file}")
  if [[ "${version}" -lt "${SM_STATE_VERSION}" ]]; then
    sm_migrate_state "${op}"
  fi
}

# sm_get_phase <op>
# Get current phase of an operation
sm_get_phase() {
  local op="$1"
  sm_ensure_current_schema "${op}"
  sm_read_state "${op}" "phase"
}
