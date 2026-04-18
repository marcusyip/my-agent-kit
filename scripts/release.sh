#!/usr/bin/env bash
# Bump tdd-contract-review plugin version across every file that tracks it.
#
# Usage: scripts/release.sh <version>
# Example: scripts/release.sh 0.35.0
#
# Updates:
#   - tdd-contract-review/.claude-plugin/plugin.json           (.version)
#   - .claude-plugin/marketplace.json                          (plugin entry .version)
#   - tdd-contract-review/skills/tdd-contract-review/SKILL.md  (frontmatter version:)
#
# Requires CHANGELOG.md to already have a matching `## [<version>]` section at
# the top — the script validates, it does not write one for you.
#
# Does not commit, tag, or push. Run git diff after to review.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi

VERSION="$1"
PLUGIN="tdd-contract-review"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PLUGIN_JSON="$PLUGIN/.claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
SKILL_MD="$PLUGIN/skills/$PLUGIN/SKILL.md"
CHANGELOG="CHANGELOG.md"

for f in "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$SKILL_MD" "$CHANGELOG"; do
  [[ -f "$f" ]] || { echo "error: $f not found" >&2; exit 1; }
done

command -v jq >/dev/null || { echo "error: jq is required (brew install jq)" >&2; exit 1; }

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "error: '$VERSION' is not a semver (expected X.Y.Z[-pre])" >&2
  exit 1
fi

TOP_CHANGELOG_VERSION=$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+' "$CHANGELOG" \
  | sed -E 's/^## \[([^]]+)\].*/\1/')
if [[ "$TOP_CHANGELOG_VERSION" != "$VERSION" ]]; then
  echo "error: top of CHANGELOG.md is [$TOP_CHANGELOG_VERSION], expected [$VERSION]" >&2
  echo "       add '## [$VERSION] - $(date +%Y-%m-%d)' with release notes before bumping" >&2
  exit 1
fi

CURRENT_PLUGIN=$(jq -r .version "$PLUGIN_JSON")
CURRENT_MARKETPLACE=$(jq -r --arg n "$PLUGIN" '.plugins[] | select(.name == $n) | .version' "$MARKETPLACE_JSON")
CURRENT_SKILL=$(awk '/^---$/{c++; next} c==1 && /^version: /{print $2; exit}' "$SKILL_MD")

echo "current:"
printf '  %-55s %s\n' "$PLUGIN_JSON"      "$CURRENT_PLUGIN"
printf '  %-55s %s\n' "$MARKETPLACE_JSON" "$CURRENT_MARKETPLACE"
printf '  %-55s %s\n' "$SKILL_MD"         "$CURRENT_SKILL"
echo "target: $VERSION"
echo

tmp=$(mktemp)
jq --arg v "$VERSION" '.version = $v' "$PLUGIN_JSON" > "$tmp" && mv "$tmp" "$PLUGIN_JSON"

tmp=$(mktemp)
jq --arg n "$PLUGIN" --arg v "$VERSION" \
  '(.plugins[] | select(.name == $n) | .version) = $v' \
  "$MARKETPLACE_JSON" > "$tmp" && mv "$tmp" "$MARKETPLACE_JSON"

# Rewrite only the `version:` line inside the YAML frontmatter (between the first two `---`).
tmp=$(mktemp)
awk -v v="$VERSION" '
  /^---$/ { c++; print; next }
  c == 1 && !done && /^version: / { print "version: " v; done = 1; next }
  { print }
' "$SKILL_MD" > "$tmp" && mv "$tmp" "$SKILL_MD"

echo "bumped $PLUGIN → $VERSION in:"
echo "  $PLUGIN_JSON"
echo "  $MARKETPLACE_JSON"
echo "  $SKILL_MD"
echo
echo "next steps:"
echo "  git diff -- $PLUGIN_JSON $MARKETPLACE_JSON $SKILL_MD $CHANGELOG"
echo "  git commit -am 'chore: release $PLUGIN v$VERSION'"
