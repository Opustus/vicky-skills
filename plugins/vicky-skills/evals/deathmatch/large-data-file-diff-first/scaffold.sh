#!/usr/bin/env bash
# shellcheck disable=SC2016 # the generated handler scripts keep literal $1
# A small-file-count diff containing a 500-line data file and one symptom fix,
# testing that opponents inspect the diff first on large data files regardless of
# total file count and batch independent reads per turn.
set -eu
git init -q -b main .
mkdir -p src data
printf '# Agent rules\n\nFix causes, not symptoms.\n' > AGENTS.md
cat > law.md <<'MD'
# Project Law

## Formatting and naming
Use two-space indents and snake_case identifiers.

## Cause over symptoms
A fix must address the root cause rather than silencing the failure with a retry or fallback.
MD
python3 -c '
import json
items = [{"id": i, "name": f"item_{i}", "enabled": True} for i in range(1, 101)]
print(json.dumps({"items": items}, indent=2))
' > data/catalog.json
printf '#!/usr/bin/env bash\n# Fails on empty input.\n[ -n "${1:-}" ] || exit 1\necho "$1"\n' > src/handler.sh
git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -q -m start
git switch -q -c feature
python3 -c '
import json
with open("data/catalog.json") as f:
    d = json.load(f)
d["items"][42]["enabled"] = False
with open("data/catalog.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
'
printf '#!/usr/bin/env bash\n# Symptom fix: hide failure.\n[ -n "${1:-}" ] || exit 0\necho "$1"\n' > src/handler.sh
git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "fix: silence empty handler input and disable item 43"
