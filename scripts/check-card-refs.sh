#!/usr/bin/env bash
# Fails when a tracked file names a task card (docs/tasks/<type>-<slug>.md)
# that does not exist. Cards are the place a comment's "why" lives; a path
# to a card that is gone sends the reader nowhere.
#   scripts/check-card-refs.sh
# docs/KEEL.md, docs/examples and the card templates use made-up names.
# docs/archive holds cards written before the repository was published; the
# paths inside them are as they were then and are not checked.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"
status=0
while IFS=: read -r file path; do
  if [ ! -f "$path" ]; then
    echo "FAIL $file names $path, which does not exist" >&2
    status=1
  fi
done < <(git grep -I -o -E 'docs/tasks/(feat|fix|perf|refactor|debt|docs|chore|research|review|release)-[a-z0-9][a-z0-9.-]*\.md' \
  -- . ':!docs/archive' ':!docs/KEEL.md' ':!docs/examples' ':!docs/tasks/TEMPLATE.md' ':!docs/tasks/TEMPLATE-LIGHT.md' ':!docs/tasks/README.md' | sort -u)
[ "$status" -eq 0 ] && echo "check-card-refs: every card path that is named exists"
exit "$status"
