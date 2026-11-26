#!/usr/bin/env python3
"""Install or update vicky-skills into an Antigravity plugin directory.

Flattens grouped skills into Antigravity's skills/<name>/SKILL.md layout,
rewrites relative and ${CLAUDE_PLUGIN_ROOT}/${CLAUDE_PLUGIN_DATA} paths, copies
hooks.json and .claude-plugin/plugin.json, and converts Claude agent
frontmatter into Antigravity subagent definitions with execution-batching rules.
"""
import argparse
import json
import os
import re
import shutil

TOOL_MAP = {
    "Read": ["read_file"],
    "Glob": ["read_file"],
    "Grep": ["read_file"],
    "Edit": ["edit_file"],
    "MultiEdit": ["edit_file"],
    "Write": ["write_file"],
    "Bash": ["run_command", "manage_task"],
    "WebSearch": ["search_web"],
    "WebFetch": ["search_web"],
}
DEFAULT_TOOLS = [
    "read_file",
    "edit_file",
    "write_file",
    "run_command",
    "manage_task",
    "search_web",
]

AGY_SUBAGENT_FOOTER = (
    "\n## Antigravity execution\n\n"
    "- **Batch turns:** Issue every independent `read_file` and `run_command` for the current step in one turn "
    "(all law/standard files and `git diff --name-only` in turn 1; all marked files in turn 2). Never read one file per turn.\n"
    "- **Synchronous runs:** Set `WaitMsBeforeAsync: 10000` on `run_command` calls expected to finish within 10s "
    "so fast `git`, `pytest`, and `cap.sh` checks return in the same turn without `manage_task` polling.\n"
    "- **Large data diffs:** On JSON, lock, or generated files over 400 lines, inspect `git diff <fixed-point>...HEAD -- <file>` "
    "before reading line ranges.\n"
)


def rewrite_paths(text, dest_dir, data_dir, groups):
    if groups:
        groups_alt = "|".join(re.escape(g) for g in sorted(groups))
        text = re.sub(
            rf"\$\{{CLAUDE_PLUGIN_ROOT\}}/skills/(?:{groups_alt})/",
            f"{dest_dir}/skills/",
            text,
        )
        text = re.sub(rf"\.\./\.\./(?:{groups_alt})/", "../", text)
    text = text.replace("${CLAUDE_PLUGIN_ROOT}", dest_dir)
    text = text.replace("${CLAUDE_PLUGIN_DATA}", data_dir)
    text = re.sub(r"\.\./\.\./(CHARTER|GATES|STANDARDS)", r"../\1", text)
    return text


def rewrite_md_tree(root_dir, dest_dir, data_dir, groups):
    for dirpath, _, filenames in os.walk(root_dir):
        for fn in filenames:
            if not fn.endswith(".md"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                orig = f.read()
            updated = rewrite_paths(orig, dest_dir, data_dir, groups)
            if updated != orig:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(updated)


def map_tools(raw_tools):
    if not raw_tools:
        return DEFAULT_TOOLS
    mapped = []
    for item in re.split(r"[,\s]+", raw_tools.strip("[] ")):
        item = item.strip().strip("'\"")
        if not item:
            continue
        for t in TOOL_MAP.get(item, []):
            if t not in mapped:
                mapped.append(t)
    return mapped or DEFAULT_TOOLS


def convert_agent(src_path, dst_path, dest_dir, data_dir, groups):
    with open(src_path, "r", encoding="utf-8") as f:
        text = f.read()
    m = re.match(r"^---\n(.*?)\n---\n?(.*)", text, re.S)
    base_name = os.path.splitext(os.path.basename(src_path))[0]
    name = base_name
    desc = ""
    raw_tools = ""
    body = text
    if m:
        fm, body = m.group(1), m.group(2)
        nm = re.search(r"^name:\s*(.+)$", fm, re.M)
        if nm:
            name = nm.group(1).strip().strip("'\"")
        dm = re.search(r"^description:\s*(.+)$", fm, re.M)
        if dm:
            desc = dm.group(1).strip()
        tm = re.search(r"^tools:\s*(.+)$", fm, re.M)
        if tm:
            raw_tools = tm.group(1).strip()
    if not desc:
        first_line = next((l.strip() for l in body.splitlines() if l.strip()), name)
        desc = json.dumps(first_line)

    tools = map_tools(raw_tools)
    body = rewrite_paths(body, dest_dir, data_dir, groups).strip() + "\n" + AGY_SUBAGENT_FOOTER
    out = (
        "---\n"
        f"name: {name}\n"
        f"description: {desc}\n"
        "subagent: true\n"
        "mainAgent: false\n"
        f"tools: [{', '.join(tools)}]\n"
        "---\n\n"
        f"{body}"
    )
    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(out)


def install(src_root, dest_dir, data_dir):
    plugin_src = os.path.join(src_root, "plugins", "vicky-skills")
    if not os.path.isdir(plugin_src):
        plugin_src = src_root

    dest_dir = os.path.abspath(os.path.expanduser(dest_dir))
    data_dir = os.path.abspath(os.path.expanduser(data_dir))
    os.makedirs(os.path.dirname(dest_dir), exist_ok=True)
    os.makedirs(data_dir, exist_ok=True)

    staging = dest_dir + ".staging"
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.makedirs(os.path.join(staging, "skills"), exist_ok=True)
    os.makedirs(os.path.join(staging, "agents"), exist_ok=True)

    src_manifest = os.path.join(plugin_src, ".claude-plugin", "plugin.json")
    manifest_data = {}
    if os.path.isfile(src_manifest):
        os.makedirs(os.path.join(staging, ".claude-plugin"), exist_ok=True)
        shutil.copy2(src_manifest, os.path.join(staging, ".claude-plugin", "plugin.json"))
        with open(src_manifest, "r", encoding="utf-8") as f:
            manifest_data = json.load(f)

    plugin_meta = {
        "name": manifest_data.get("name") or "vicky-skills",
        "displayName": "Vicky Skills",
        "version": "1.0.0",
        "description": manifest_data.get("description") or "Engineering and workflow skills.",
    }
    if manifest_data.get("repository"):
        plugin_meta["repository"] = manifest_data["repository"]
    with open(os.path.join(staging, "plugin.json"), "w", encoding="utf-8") as f:
        json.dump(plugin_meta, f, indent=2)
        f.write("\n")

    src_scripts = os.path.join(plugin_src, "scripts")
    if os.path.isdir(src_scripts):
        shutil.copytree(src_scripts, os.path.join(staging, "scripts"))

    src_hooks_json = os.path.join(plugin_src, "hooks.json")
    if os.path.isfile(src_hooks_json):
        shutil.copy2(src_hooks_json, os.path.join(staging, "hooks.json"))

    src_skills_root = os.path.join(plugin_src, "skills")
    groups = [
        d for d in os.listdir(src_skills_root)
        if os.path.isdir(os.path.join(src_skills_root, d))
        and not os.path.isfile(os.path.join(src_skills_root, d, "SKILL.md"))
    ]

    for fn in sorted(os.listdir(src_skills_root)):
        fp = os.path.join(src_skills_root, fn)
        if os.path.isfile(fp) and fn.endswith(".md"):
            shutil.copy2(fp, os.path.join(staging, "skills", fn))

    skill_count = 0
    for dirpath, dirnames, filenames in os.walk(src_skills_root):
        if "SKILL.md" in filenames:
            skill_name = os.path.basename(dirpath)
            shutil.copytree(dirpath, os.path.join(staging, "skills", skill_name))
            skill_count += 1
            dirnames[:] = []

    rewrite_md_tree(os.path.join(staging, "skills"), dest_dir, data_dir, groups)

    src_agents = os.path.join(plugin_src, "agents")
    agent_count = 0
    if os.path.isdir(src_agents):
        for fn in sorted(os.listdir(src_agents)):
            if fn.endswith(".md"):
                convert_agent(
                    os.path.join(src_agents, fn),
                    os.path.join(staging, "agents", fn),
                    dest_dir,
                    data_dir,
                    groups,
                )
                agent_count += 1

    backup = dest_dir + ".old"
    if os.path.exists(backup):
        shutil.rmtree(backup)
    if os.path.exists(dest_dir):
        os.rename(dest_dir, backup)
    os.rename(staging, dest_dir)
    if os.path.exists(backup):
        shutil.rmtree(backup)

    return skill_count, agent_count


def main():
    default_src = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", default=default_src, help="Path to vicky-skills checkout")
    parser.add_argument(
        "--dest",
        default=os.path.join(os.path.expanduser("~"), ".gemini", "config", "plugins", "vicky-skills"),
        help="Destination Antigravity plugin folder",
    )
    parser.add_argument(
        "--data-dir",
        default=os.path.join(os.path.expanduser("~"), ".gemini", "antigravity", "plugin_data", "vicky-skills"),
        help="Antigravity plugin_data folder",
    )
    args = parser.parse_args()
    skills, agents = install(args.src, args.dest, args.data_dir)
    print(f"Installed vicky-skills to {args.dest}: {skills} skills, {agents} agents")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
