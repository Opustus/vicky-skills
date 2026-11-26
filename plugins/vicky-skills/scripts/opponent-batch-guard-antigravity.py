#!/usr/bin/env python3
"""Antigravity PreToolUse hook (invoke_subagent): enforces deathmatch's batch.sh
cap, keeps holds-opponent fighting alone, and blocks explicit Model="pro"."""
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
import time

CEILING = 3
DEFAULT_LIMIT = 1
BURST_WINDOW_SECS = 30
AT_ONCE_RE = re.compile(r"at once:\s*([0-9]+)")
CONV_ID_RE = re.compile(r'"conversationId"\s*:\s*"([0-9a-f-]{8,})"')


def allow():
    print('{"decision": "allow"}')


def deny(reason):
    print(json.dumps({"decision": "deny", "reason": reason}))


def parse_transcript(path):
    limit = DEFAULT_LIMIT
    pending = []
    active = {}
    parent_model = ""
    if not os.path.isfile(path):
        return limit, active, parent_model
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            try:
                d = json.loads(line)
            except Exception:
                continue
            stype = d.get("type")
            content = d.get("content") or ""
            if stype == "GENERIC" and "at once:" in content:
                matches = AT_ONCE_RE.findall(content)
                if matches:
                    val = int(matches[-1])
                    if 1 <= val <= CEILING:
                        limit = val
            elif stype == "PLANNER_RESPONSE":
                pending.clear()
                if d.get("model"):
                    parent_model = str(d["model"])
                for tc in d.get("tool_calls") or []:
                    if tc.get("name") == "invoke_subagent":
                        tname = str((tc.get("args") or {}).get("TypeName") or "")
                        if tname.endswith("-opponent"):
                            pending.append(tname)
            elif stype == "GENERIC" and "Created the following subagent:" in content:
                m = CONV_ID_RE.search(content)
                if m and pending:
                    active[m.group(1)] = pending.pop(0)
            elif stype == "GENERIC" and pending and "tool call denied" in content:
                pending.pop(0)
            elif stype == "SYSTEM_MESSAGE":
                for cid in [c for c in active if c in content]:
                    active.pop(cid, None)
    return limit, active, parent_model


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except Exception:
        return allow()
    tc = payload.get("toolCall") or {}
    if tc.get("name") != "invoke_subagent":
        return allow()
    args = tc.get("args") or {}
    tname = str(args.get("TypeName") or "")
    if not tname.endswith("-opponent"):
        return allow()
    req_model = str(args.get("Model") or "")
    if req_model == "pro":
        return deny("opponent-batch-guard: do not set Model='pro' on deathmatch opponents. Nothing was dispatched.")

    transcript = payload.get("transcriptPath") or ""
    conv_id = payload.get("conversationId") or "default"
    tool_id = str(tc.get("id") or "")
    base = os.environ.get("PLUGIN_DATA") or tempfile.gettempdir()
    state_dir = os.path.join(base, "opponent-batch")
    os.makedirs(state_dir, exist_ok=True)
    key = hashlib.sha256(conv_id.encode("utf-8")).hexdigest()[:24]
    rec_path = os.path.join(state_dir, f"{key}.json")

    with open(os.path.join(state_dir, f"{key}.lock"), "w", encoding="utf-8") as lock_f:
        fcntl.flock(lock_f.fileno(), fcntl.LOCK_EX)  # mutant-ok delete: serializes concurrent hook processes
        limit, active, parent_model = parse_transcript(transcript)
        pm_lower = parent_model.lower()
        if pm_lower.startswith("claude-") and req_model in ("flash", "flash_lite"):
            return deny(
                f"opponent-batch-guard: parent model is Claude ({parent_model}); use Model='inherit' on "
                f"deathmatch opponents instead of '{req_model}' (which crosses into Gemini's quota pool). "
                "Nothing was dispatched."
            )
        if pm_lower.startswith("gemini-") and "-pro" in pm_lower and req_model in ("", "inherit"):
            return deny(
                f"opponent-batch-guard: parent model is Pro-tier Gemini ({parent_model}); set Model='flash' "
                f"or 'flash_lite' on deathmatch opponents instead of '{req_model or 'inherit'}'. "
                "Nothing was dispatched."
            )
        now = time.time()
        try:
            with open(rec_path, "r", encoding="utf-8") as rf:
                recent = [r for r in json.load(rf) if now - float(r.get("ts", 0)) < BURST_WINDOW_SECS]
        except Exception:
            recent = []
        running = list(active.values())
        recent_only = [r["type"] for r in recent if not tool_id or r.get("id") != tool_id]
        count = max(len(running), len(recent_only))
        names = running if len(running) >= len(recent_only) else recent_only

        if tname == "holds-opponent":
            if count > 0:
                return deny(f"opponent-batch-guard: holds-opponent fights alone ({', '.join(names)} still fight). Nothing was dispatched.")
        else:
            if "holds-opponent" in names:
                return deny("opponent-batch-guard: holds-opponent fights alone and is still fighting. Nothing was dispatched.")
            if count >= limit:
                return deny(f"opponent-batch-guard: {count} opponent(s) fighting ({', '.join(names)}); batch.sh allows at most {limit}. Nothing was dispatched.")

        recent.append({"id": tool_id, "type": tname, "ts": now})
        with open(rec_path, "w", encoding="utf-8") as wf:
            json.dump(recent, wf)
    allow()


if __name__ == "__main__":
    main()
