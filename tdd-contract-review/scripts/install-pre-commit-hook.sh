#!/usr/bin/env bash
# Install a git pre-commit hook that runs check_rendered_md.py --staged.
# Idempotent: re-running overwrites an older hook only if it was installed
# by this script (detected by a marker line at the top).
#
# Usage: tdd-contract-review/scripts/install-pre-commit-hook.sh
#
# The hook catches drift when someone hand-edits a rendered `.md` file:
# re-render from the `.json` source and any diff fails the commit.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
HOOK_DIR="$REPO_ROOT/.git/hooks"
HOOK_FILE="$HOOK_DIR/pre-commit"
MARKER='# tdd-contract-review:check_rendered_md'

if [[ ! -d "$HOOK_DIR" ]]; then
  echo "error: $HOOK_DIR not found — is this a git worktree?" >&2
  exit 1
fi

if [[ -f "$HOOK_FILE" ]] && ! grep -qF "$MARKER" "$HOOK_FILE"; then
  cat >&2 <<EOF
error: a non-tdd-contract-review pre-commit hook already exists at:
  $HOOK_FILE

Inspect it before overwriting. If you want to replace it, move it aside
or delete it, then re-run this installer.
EOF
  exit 1
fi

cat > "$HOOK_FILE" <<EOF
#!/usr/bin/env bash
$MARKER
# Installed by tdd-contract-review/scripts/install-pre-commit-hook.sh.
# Fails the commit if any staged \`.json\` artifact under tdd-contract-review/
# no longer matches its rendered \`.md\` sibling. Edit JSON, re-render, commit
# both — never hand-edit the \`.md\`.
set -e
exec python3 "$HERE/check_rendered_md.py" --staged
EOF
chmod +x "$HOOK_FILE"

echo "installed: $HOOK_FILE"
echo "runs: $HERE/check_rendered_md.py --staged"
