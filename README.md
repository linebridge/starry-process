# starry-process

Process management for Starry OS.

Heavily inspired by [Asterinas](https://github.com/asterinas/asterinas).

## Verify axci auto-target integration

Run a local dry-run verification with doc-only and code-change scenarios:

```bash
scripts/verify_axci_selection.sh --axci-root /home/fei/os-internship/axci
```

This script creates a temporary git worktree and checks:

- doc-only change should skip tests
- source code change should select test targets

> CI validation note: this line is added to verify doc-only auto-skip behavior.
