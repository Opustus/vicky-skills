#!/usr/bin/env bash
# A >15-file diff with one symptom fix and a large multi-section law file,
# testing that non-Standards opponents inspect the diff first and read only the
# relevant law sections rather than reading every file and the entire law file.
set -eu
git init -q -b main .
mkdir -p src
printf '# Agent rules\n\nFix causes, not symptoms.\n' > AGENTS.md
cat > law.md <<'MD'
# Project Law

## Formatting and naming
Use two-space indents and snake_case identifiers.

## Cause over symptoms
A fix must address the root cause rather than silencing the failure with a retry or fallback.
MD
for i in $(seq -w 1 18); do
  printf '#!/usr/bin/env bash\necho "module %s"\n' "$i" > "src/mod_${i}.sh"
done
printf '#!/usr/bin/env bash\n# Fails on empty input.\n[ -n "${1:-}" ] || exit 1\necho "$1"\n' > src/handler.sh
git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -q -m start
git switch -q -c feature
for i in $(seq -w 1 18); do
  printf '# touched %s\n' "$i" >> "src/mod_${i}.sh"
done
printf '#!/usr/bin/env bash\n# Symptom fix: hide failure.\n[ -n "${1:-}" ] || exit 0\necho "$1"\n' > src/handler.sh
git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "fix: stop handler from failing on empty input"
