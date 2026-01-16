# Debug Reference

Quick-reference guides for diagnosing and recovering from workflow failures.

## Quick Links

| Workflow | State File | tmux Session |
|----------|------------|--------------|
| [Feature](feature.md) | `BUILD_DIR/operations/{name}/state.json` | `{project}-feature-{name}` |
| [Fix](fix.md) | `BUILD_DIR/fix/{id}/state.json` | `{project}-worker-fix` |
| [Chore](chore.md) | `BUILD_DIR/chore/{id}/state.json` | `{project}-worker-chore` |
| [Merge Queue](merge-queue.md) | `BUILD_DIR/mergeq/queue.json` | — |
| [Hooks](hooks.md) | — | — |
| [Recovery](recovery.md) | — | — |

## Common Issues

**Lost work?** → [recovery.md](recovery.md#finding-lost-work)

**Branch stuck unmerged?** → [recovery.md](recovery.md#branch-lost---never-merged)

**Agent exited but work incomplete?** → [hooks.md](hooks.md#1-hook-silently-approves-exit-critical)

**Nothing processing?** → Check daemon status:
```bash
pgrep -f "v0-mergeq --watch"   # merge queue daemon
tmux ls | grep worker           # fix/chore workers
```

**Operation stuck?** → Check state:
```bash
cat BUILD_DIR/operations/{name}/state.json | jq .phase
v0 mergeq --list
```

## Lock Files

| Lock | Location | Stuck? |
|------|----------|--------|
| Merge | `BUILD_DIR/.merge.lock` | `rm BUILD_DIR/.merge.lock` |
| Queue | `BUILD_DIR/mergeq/.queue.lock` | `rm BUILD_DIR/mergeq/.queue.lock` |

## Source References

- `bin/v0-feature` — Feature workflow orchestration
- `bin/v0-fix` — Fix workflow and polling daemon
- `bin/v0-chore` — Chore workflow
- `bin/v0-mergeq` — Merge queue daemon
- `lib/worker-common.sh` — Shared polling loop logic
- `lib/hooks/stop-*.sh` — Completion validation hooks
