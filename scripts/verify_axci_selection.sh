#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AXCI_ROOT_DEFAULT="$(cd "$REPO_ROOT/.." && pwd)/axci"

AXCI_ROOT="$AXCI_ROOT_DEFAULT"
BASE_REF="HEAD"
KEEP_WORKTREE=false

show_help() {
  cat <<'EOF'
Verify axci auto-target selection with two scenarios.

Usage:
  scripts/verify_axci_selection.sh [options]

Options:
  --axci-root PATH   Path to axci repository (default: ../axci)
  --base-ref REF     Base ref used by axci tests.sh (default: HEAD)
  --keep-worktree    Keep temporary worktree for debugging
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --axci-root)
      AXCI_ROOT="$2"
      shift 2
      ;;
    --base-ref)
      BASE_REF="$2"
      shift 2
      ;;
    --keep-worktree)
      KEEP_WORKTREE=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      show_help
      exit 1
      ;;
  esac
done

AXCI_TESTS_SH="$AXCI_ROOT/tests.sh"
if [[ ! -f "$AXCI_TESTS_SH" ]]; then
  echo "[ERROR] axci tests.sh not found: $AXCI_TESTS_SH" >&2
  exit 1
fi

if [[ ! -d "$REPO_ROOT/.git" ]]; then
  echo "[ERROR] $REPO_ROOT is not a git repository" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
WORKTREE_DIR="$TMP_DIR/starry-process-wt"
DOC_OUTPUT="$TMP_DIR/doc_case.log"
CODE_OUTPUT="$TMP_DIR/code_case.log"

cleanup() {
  if [[ -d "$WORKTREE_DIR" ]] && [[ "$KEEP_WORKTREE" != true ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_WORKTREE" != true ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

echo "[INFO] Create temporary worktree..."
git -C "$REPO_ROOT" worktree add --detach "$WORKTREE_DIR" HEAD >/dev/null

run_axci_dryrun() {
  local output_file="$1"
  (
    cd "$WORKTREE_DIR"
    bash "$AXCI_TESTS_SH" \
      -c "$WORKTREE_DIR" \
      --auto-target \
      --base-ref "$BASE_REF" \
      --dry-run -v
  ) >"$output_file" 2>&1
}

contains_text() {
  local needle="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "$needle" "$file"
  else
    grep -q "$needle" "$file"
  fi
}

echo "[INFO] Case 1/2: doc-only change (expect skip_all)"
printf '\naxci-doc-verify-%s\n' "$(date +%s)" >> "$WORKTREE_DIR/README.md"
run_axci_dryrun "$DOC_OUTPUT"
if contains_text "跳过所有测试" "$DOC_OUTPUT"; then
  echo "[PASS] doc-only change -> skip_all"
else
  echo "[FAIL] doc-only change was not skipped" >&2
  echo "---- output ----" >&2
  sed -n '1,160p' "$DOC_OUTPUT" >&2
  exit 1
fi

git -C "$WORKTREE_DIR" reset --hard HEAD >/dev/null
git -C "$WORKTREE_DIR" clean -fd >/dev/null

echo "[INFO] Case 2/2: source code change (expect non-skip)"
printf '\n// axci-code-verify-%s\n' "$(date +%s)" >> "$WORKTREE_DIR/src/lib.rs"
run_axci_dryrun "$CODE_OUTPUT"
if contains_text "跳过所有测试" "$CODE_OUTPUT"; then
  echo "[FAIL] code change unexpectedly skipped" >&2
  echo "---- output ----" >&2
  sed -n '1,220p' "$CODE_OUTPUT" >&2
  exit 1
fi
if contains_text "自动目标选择" "$CODE_OUTPUT"; then
  echo "[PASS] code change -> targets selected"
else
  echo "[FAIL] no auto-target selection output for code change" >&2
  echo "---- output ----" >&2
  sed -n '1,220p' "$CODE_OUTPUT" >&2
  exit 1
fi

echo
echo "[OK] axci selection verification passed."
echo "[INFO] doc log:  $DOC_OUTPUT"
echo "[INFO] code log: $CODE_OUTPUT"
if [[ "$KEEP_WORKTREE" == true ]]; then
  echo "[INFO] kept temp worktree: $WORKTREE_DIR"
fi
