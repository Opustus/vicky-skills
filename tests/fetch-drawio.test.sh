#!/usr/bin/env bash
# fetch-drawio.sh keeps an archive only when its SHA-256 matches the pin, and
# unpacks it once. A fixture archive, served from a file URL, stands in for
# the real release, so the test needs no network.
set -u
fetch="$(cd "$(dirname "$0")/.." && pwd)/plugins/vicky-skills/skills/planning/drawing-board/scripts/fetch-drawio.sh"
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
python3 -I -c 'import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z: z.writestr("index.html", "<title>draw.io</title>")' "$dir/app.war"
python3 -I -c 'import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z: z.writestr("../escape.txt", "x")' "$dir/bad.war"
good=$(sha256sum "$dir/app.war" | cut -d' ' -f1)
bad=$(sha256sum "$dir/bad.war" | cut -d' ' -f1)
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
run() { CLAUDE_PLUGIN_DATA="$dir/data" DRAWIO_URL="file://$dir/$1" DRAWIO_SHA256="$2" bash "$fetch" 2>"$dir/err"; }
mkdir -p "$dir/data"
home=$(run app.war "$good")
check "a matching archive is unpacked and named" '[ -f "$home/index.html" ] && [ "$home" = "$dir/data/drawio/$good" ]'
check "a second run reuses it" 'again=$(run missing.war "$good") && [ "$again" = "$home" ]'
check "a download that fails keeps nothing and says so" '! run missing.war 1111 >/dev/null && grep -q "could not download" "$dir/err" && [ ! -d "$dir/data/drawio/1111" ]'
check "a wrong hash keeps nothing" '! run app.war 0000 >/dev/null && grep -q "not the pinned" "$dir/err" && [ ! -d "$dir/data/drawio/0000" ]'
check "an entry outside the folder is refused" '! run bad.war "$bad" >/dev/null && [ ! -f "$dir/data/escape.txt" ] && [ ! -d "$dir/data/drawio/$bad" ]'
check "no data folder, no fetch" '! CLAUDE_PLUGIN_DATA= PLUGIN_DATA= bash "$fetch" >/dev/null 2>&1'
check "the fetch folder is cleaned up" '[ -z "$(ls -d "$dir/data"/drawio-fetch.* 2>/dev/null)" ]'
mkdir -p "$dir/pd"
pd_home=$(CLAUDE_PLUGIN_DATA= PLUGIN_DATA="$dir/pd" DRAWIO_URL="file://$dir/app.war" DRAWIO_SHA256="$good" bash "$fetch" 2>/dev/null)
check "PLUGIN_DATA works when CLAUDE_PLUGIN_DATA is unset" '[ -f "$pd_home/index.html" ] && [ "$pd_home" = "$dir/pd/drawio/$good" ]'
agy_root="$dir/.gemini/config/plugins/vicky-skills"
mkdir -p "$agy_root/scripts" "$agy_root/skills/drawing-board/scripts" "$dir/.gemini/antigravity/plugin_data/vicky-skills"
cp "$(dirname "$fetch")/../../../../scripts/plugin-data.sh" "$agy_root/scripts/"
cp "$fetch" "$agy_root/skills/drawing-board/scripts/"
agy_home=$(CLAUDE_PLUGIN_DATA= PLUGIN_DATA= DRAWIO_URL="file://$dir/app.war" DRAWIO_SHA256="$good" bash "$agy_root/skills/drawing-board/scripts/fetch-drawio.sh" 2>/dev/null)
check "Antigravity flattened plugin resolves plugin_data" '[ -f "$agy_home/index.html" ] && [ "$agy_home" = "$dir/.gemini/antigravity/plugin_data/vicky-skills/drawio/$good" ]'
exit $fail
