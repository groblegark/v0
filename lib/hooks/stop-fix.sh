#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# Stop hook for fix worker - verifies no bugs remain
set -e

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
STOP_REASON=$(echo "$INPUT" | jq -r '.reason // ""')

# Approve immediately if stop is due to system reasons (auth, credits, etc.)
case "$STOP_REASON" in
  *auth*|*login*|*credential*|*credit*|*subscription*|*billing*|*payment*)
    echo '{"decision": "approve"}'
    exit 0
    ;;
esac

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Check for abandoned work (in_progress bugs indicate work started but not finished)
# Note: Ready bugs are expected - the workflow is one bug per session
IN_PROGRESS=$(wk list --type bug --status in_progress 2>/dev/null | wc -l | tr -d ' ')

if [ "$IN_PROGRESS" -gt 0 ]; then
  echo "{\"decision\": \"block\", \"reason\": \"$IN_PROGRESS bug(s) still in progress. Complete with './fixed <id>' or abandon with 'wk stop <id>'.\"}"
  exit 0
fi

echo '{"decision": "approve"}'
