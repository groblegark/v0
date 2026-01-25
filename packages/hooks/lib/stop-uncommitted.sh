#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# Stop hook for uncommitted changes resolution
# Verifies worktree has no uncommitted changes before allowing exit
set -e

# Source grep wrapper for fast pattern matching
_HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/core/lib/grep.sh
source "${_HOOKS_DIR}/../../core/lib/grep.sh"

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

WORKTREE="${UNCOMMITTED_WORKTREE:-}"
if [ -z "$WORKTREE" ] || [ ! -d "$WORKTREE" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Check for uncommitted changes (ignore untracked files)
if git -C "$WORKTREE" status --porcelain 2>/dev/null | v0_grep_invert '^??' | v0_grep_quiet .; then
  REPO_NAME=$(basename "$WORKTREE")
  echo "{\"decision\": \"block\", \"reason\": \"Uncommitted changes remain. Run: cd $REPO_NAME && git status\"}"
  exit 0
fi

echo '{"decision": "approve"}'
