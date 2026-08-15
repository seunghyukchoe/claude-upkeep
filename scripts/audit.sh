#!/usr/bin/env bash
# Read-only audit of the local Claude Code installation.
set -uo pipefail
C=~/.claude
J=~/.claude.json

hr() { printf '\n\033[1m%s\033[0m\n' "$1"; }
sz() { du -sh "$1" 2>/dev/null | cut -f1; }

# BSD/macOS stat and GNU stat disagree on how to ask for mtime.
if stat -f '%m' . >/dev/null 2>&1; then STATFMT="-f%m"; else STATFMT="-c%Y"; fi

hr "DISK"
printf "  .claude total      %s\n" "$(sz $C)"
printf "  projects (history) %s\n" "$(sz $C/projects)"
printf "  skills (active)    %s\n" "$(sz $C/skills)"
[ -d $C/skills-archive ] && printf "  skills (archived)  %s\n" "$(sz $C/skills-archive)"
df -h / | awk 'NR==2{printf "  volume free        %s of %s\n",$4,$2}'

hr "SKILL CONTEXT COST  (injected into every session)"
python3 - <<'PY'
import os,re,json
base=os.path.expanduser('~/.claude/skills')
tot=0;n=0
for s in sorted(os.listdir(base)):
    p=os.path.join(base,s,'SKILL.md')
    if not os.path.isfile(p): continue
    t=open(p,encoding='utf-8',errors='replace').read()
    m=re.search(r'^---\n(.*?)\n---',t,re.S)
    fm=m.group(1) if m else ''
    d=re.search(r'^description:\s*(.*?)(?=\n[a-z_-]+:|\Z)',fm,re.S|re.M)
    tot+=len(d.group(1).strip() if d else '')+len(s)+20; n+=1
print(f"  {n} active skills  ~{tot} chars  ~{tot//4} tokens per session")
try:
    su=json.load(open(os.path.expanduser('~/.claude.json'))).get('skillUsage',{})
except Exception:
    su={}
used={k.split(':')[-1] for k in su}
never=[s for s in sorted(os.listdir(base)) if os.path.isdir(os.path.join(base,s)) and s not in used]
print(f"  never invoked: {len(never)}/{n}")
if never: print("   ", ", ".join(never))
PY

hr "STALE RUNTIME"
printf "  session-env entries      %s (older than 7d: %s)\n" \
  "$(ls $C/session-env 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find $C/session-env -maxdepth 1 -mindepth 1 -mtime +7 2>/dev/null | wc -l | tr -d ' ')"
printf "  telemetry failed events  %s files\n" "$(ls $C/telemetry/1p_failed_events.*.json 2>/dev/null | wc -l | tr -d ' ')"
printf "  transcripts >60d         %s files, %s\n" \
  "$(find $C/projects -name '*.jsonl' -mtime +60 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find $C/projects -name '*.jsonl' -mtime +60 -print0 2>/dev/null | xargs -0 du -ch 2>/dev/null | tail -1 | cut -f1)"
printf "  .claude.json backups     %s\n" "$(ls $C/backups 2>/dev/null | wc -l | tr -d ' ')"
printf "  shell-snapshots >7d      %s\n" "$(find $C/shell-snapshots -mtime +7 2>/dev/null | wc -l | tr -d ' ')"

hr "CONFIG HEALTH"
python3 - <<'PY'
import json,os,re
h=os.path.expanduser
try: s=json.load(open(h('~/.claude/settings.json')))
except Exception as e: print("  settings.json unreadable:",e); raise SystemExit
cmds=[]
for ev,gs in (s.get('hooks') or {}).items():
    for g in gs:
        for hk in g.get('hooks',[]):
            cmds.append((ev,g.get('matcher','-'),hk.get('command','')))
print(f"  hook registrations: {len(cmds)} across {len(s.get('hooks') or {})} events")
seen={}
for ev,m,c in cmds: seen.setdefault(c,[]).append(f"{ev}:{m}")
for c,evs in seen.items():
    if len(evs)>3: print(f"   duplicated x{len(evs)}: {c[:60]}...")
for c in seen:
    for p in re.findall(r"(/[^\s'\"]+|~/[^\s'\"]+)",c):
        p2=h(p)
        if ('/' in p) and not os.path.exists(p2) and not p.endswith(('/','*')):
            print(f"   MISSING target: {p}")
            break
hot=[e for e,m,c in cmds if e in ('PreToolUse','PostToolUse') and m=='*']
if hot: print(f"   fires on EVERY tool call: {len(hot)} hook(s) -> {sorted(set(hot))}")
try: j=json.load(open(h('~/.claude.json')))
except Exception: j={}
pr=j.get('projects',{}); miss=[k for k in pr if not os.path.exists(k)]
print(f"  .claude.json project entries: {len(pr)} ({len(miss)} pointing at deleted dirs)")
for m in miss: print("   orphan:",m)
pu=j.get('pluginUsage',{})
for name,meta in (s.get('enabledPlugins') or {}).items():
    n=pu.get(name,{}).get('usageCount')
    if not n: print(f"   enabled but never used: {name}")
PY

hr "AGENT-CLI DIRS IN \$HOME (untouched >30d)"
cd ~ || exit
now=$(date +%s)
for d in .*/; do
  d="${d%/}"
  case "$d" in .|..|.Trash|.claude|.ssh|.gnupg|.config|.local|.cache) continue;; esac
  n=$(find "$d" -type f -exec stat $STATFMT {} + 2>/dev/null | sort -nr | head -1)
  [ -z "$n" ] && continue
  days=$(( (now - n) / 86400 ))
  [ "$days" -gt 30 ] && printf "  %-22s %8s  %sd stale\n" "$d" "$(sz "$d")" "$days"
done
echo
