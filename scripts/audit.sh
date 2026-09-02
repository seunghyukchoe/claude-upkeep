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
def toks(s):
    # ASCII runs ~4 chars/token; Hangul/CJK closer to 1.5 chars/token.
    a=sum(1 for ch in s if ord(ch)<128)
    return a//4 + (len(s)-a)*2//3
def desc_of(path):
    t=open(path,encoding='utf-8',errors='replace').read()
    m=re.search(r'^---\n(.*?)\n---',t,re.S)
    fm=m.group(1) if m else ''
    d=re.search(r'^description:\s*(.*?)(?=\n[A-Za-z_-]+:|\Z)',fm,re.S|re.M)
    return d.group(1).strip() if d else ''
base=os.path.expanduser('~/.claude/skills')
chars=0;tot=0;n=0
for s in sorted(os.listdir(base)):
    p=os.path.join(base,s,'SKILL.md')
    if not os.path.isfile(p): continue
    d=desc_of(p); chars+=len(d)+len(s)+20; tot+=toks(d+s)+5; n+=1
print(f"  {n} active skills  ~{chars} chars  ~{tot} tokens per session")
try:
    su=json.load(open(os.path.expanduser('~/.claude.json'))).get('skillUsage',{})
except Exception:
    su={}
used={k.split(':')[-1] for k in su}
never=[s for s in sorted(os.listdir(base)) if os.path.isdir(os.path.join(base,s)) and s not in used]
print(f"  never invoked: {len(never)}/{n}")
if never: print("   ", ", ".join(never))
PY

hr "PLUGIN CONTEXT COST  (agents + skills + commands of enabled plugins)"
python3 - <<'PY'
import os,re,json,glob
h=os.path.expanduser
def toks(s):
    a=sum(1 for ch in s if ord(ch)<128)
    return a//4 + (len(s)-a)*2//3
def desc_of(path):
    t=open(path,encoding='utf-8',errors='replace').read()
    m=re.search(r'^---\n(.*?)\n---',t,re.S)
    fm=m.group(1) if m else ''
    d=re.search(r'^description:\s*(.*?)(?=\n[A-Za-z_-]+:|\Z)',fm,re.S|re.M)
    return d.group(1).strip() if d else '', fm
try: s=json.load(open(h('~/.claude/settings.json')))
except Exception: s={}
try: inst=json.load(open(h('~/.claude/plugins/installed_plugins.json'))).get('plugins',{})
except Exception: inst={}
try: pu=json.load(open(h('~/.claude.json'))).get('pluginUsage',{})
except Exception: pu={}
enabled=[k for k,v in (s.get('enabledPlugins') or {}).items() if v]
if not enabled: print("  no plugins enabled in settings.json")
grand=0
for name in enabled:
    paths=[e.get('installPath') for e in inst.get(name,[]) if e.get('installPath')]
    root=next((p for p in paths if os.path.isdir(p)),None)
    uses=pu.get(name,{}).get('usageCount',0)
    if not root:
        print(f"  {name}: enabled but not installed (installPath missing)"); continue
    files=glob.glob(root+'/agents/*.md')+glob.glob(root+'/skills/*/SKILL.md')+glob.glob(root+'/commands/*.md')
    t=0;unpinned=[]
    for f in files:
        d,fm=desc_of(f); t+=toks(d+os.path.basename(f))+5
        if f.endswith('.md') and '/agents/' in f and not re.search(r'^model:\s*\S',fm,re.M):
            unpinned.append(os.path.basename(f))
    hooks=0
    try:
        hk=json.load(open(root+'/hooks/hooks.json')).get('hooks',{})
        hooks=sum(len(x.get('hooks',[])) for gs in hk.values() for x in gs)
    except Exception: pass
    grand+=t
    flag="  <- NEVER USED: disable it or accept the cost" if uses==0 else ""
    print(f"  {name:36s} ~{t:5d} tokens/session  {len(files):2d} items  {hooks} hooks  used {uses}x{flag}")
    if unpinned: print(f"     agents without model pin (inherit session model): {', '.join(unpinned)}")
if enabled: print(f"  total plugin context ~{grand} tokens per session")
PY

hr "STALE RUNTIME"
printf "  session-env entries      %s (older than 7d: %s)\n" \
  "$(ls $C/session-env 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find $C/session-env -maxdepth 1 -mindepth 1 -mtime +7 2>/dev/null | wc -l | tr -d ' ')"
printf "  telemetry failed events  %s files, %s\n" \
  "$(ls $C/telemetry/1p_failed_events.*.json 2>/dev/null | wc -l | tr -d ' ')" \
  "$(du -ch $C/telemetry/1p_failed_events.*.json 2>/dev/null | tail -1 | cut -f1)"
printf "  transcripts >60d         %s files, %s\n" \
  "$(find $C/projects -name '*.jsonl' -mtime +60 2>/dev/null | wc -l | tr -d ' ')" \
  "$(find $C/projects -name '*.jsonl' -mtime +60 -print0 2>/dev/null | xargs -0 du -ch 2>/dev/null | tail -1 | cut -f1)"
printf "  .claude.json backups     %s (prune keeps newest 2)\n" "$(ls -A $C/backups 2>/dev/null | grep -c 'claude.json.backup')"
printf "  shell-snapshots >7d      %s\n" "$(find $C/shell-snapshots -mtime +7 2>/dev/null | wc -l | tr -d ' ')"

hr "CONFIG HEALTH"
python3 - <<'PY'
import json,os,re,shutil,collections
h=os.path.expanduser
try: s=json.load(open(h('~/.claude/settings.json')))
except Exception as e: print("  settings.json unreadable:",e); raise SystemExit
cmds=[]
for ev,gs in (s.get('hooks') or {}).items():
    for g in gs:
        for hk in g.get('hooks',[]):
            cmds.append((ev,g.get('matcher','-'),hk.get('command','')))
print(f"  hook registrations: {len(cmds)} across {len(s.get('hooks') or {})} events")
# Same command under many *events* is usually an installer run repeatedly.
# Same command under several *matchers of one event* (SessionStart startup/resume/...) is normal.
byevent={}
for ev,m,c in cmds: byevent.setdefault(c,set()).add(ev)
for c,evs in byevent.items():
    if len(evs)>3: print(f"   same command under {len(evs)} events: {c[:60]}")
for (ev,m,c),n in collections.Counter(cmds).items():
    if n>1: print(f"   exact duplicate x{n}: {ev}:{m} {c[:50]}")
for c in byevent:
    for p in re.findall(r"(/[^\s'\"]+|~/[^\s'\"]+)",c):
        p2=h(p)
        if ('/' in p) and not os.path.exists(p2) and not p.endswith(('/','*')):
            print(f"   MISSING target: {p}")
            break
hot=[e for e,m,c in cmds if e in ('PreToolUse','PostToolUse') and m in ('*','')]
if hot: print(f"   fires on EVERY tool call: {len(hot)} hook(s) -> {sorted(set(hot))}")
try: j=json.load(open(h('~/.claude.json')))
except Exception: j={}
pr=j.get('projects',{}); miss=[k for k in pr if not os.path.exists(k)]
print(f"  .claude.json project entries: {len(pr)} ({len(miss)} pointing at deleted dirs)")
for m in miss: print("   orphan:",m)
# MCP servers
seen=set()
for src in ('~/.claude/.mcp.json','~/.claude.json'):
    try: ms=json.load(open(h(src))).get('mcpServers',{})
    except Exception: ms={}
    for name,cfg in ms.items():
        cmd=cfg.get('command')
        if cmd and name not in seen and not (os.path.exists(h(cmd)) or shutil.which(cmd)):
            print(f"   MCP '{name}' command missing: {cmd}")
        seen.add(name)
try: need=json.load(open(h('~/.claude/mcp-needs-auth-cache.json')))
except Exception: need={}
if need:
    print(f"  MCP servers dialed at startup but never authorized: {len(need)}")
    print("   ", ", ".join(sorted(need)))
    print("    -> authorize the ones you use; disable the plugin/connector that brings the rest")
PY

hr "MODEL ROUTING  (who does the work)"
python3 - <<'PY'
import json,os,re,glob,collections
h=os.path.expanduser
try: s=json.load(open(h('~/.claude/settings.json')))
except Exception: s={}
print(f"  settings.json model: {s.get('model','(unset -> app default)')}   effortLevel: {s.get('effortLevel','(unset)')}")
cm=h('~/.claude/CLAUDE.md')
if os.path.isfile(cm):
    t=open(cm,encoding='utf-8',errors='replace').read()
    has=('claude-upkeep:routing' in t) or bool(re.search(r'model routing|subagent[^\n]*model|delegat',t,re.I))
    print(f"  ~/.claude/CLAUDE.md: present ({len(t)} chars), routing policy {'found' if has else 'NOT found'}")
else:
    print("  ~/.claude/CLAUDE.md: MISSING -> no global routing policy; every Agent call inherits the session model")
ag=sorted(glob.glob(h('~/.claude/agents/*.md')))
nopin=[]
for f in ag:
    t=open(f,encoding='utf-8',errors='replace').read()
    m=re.search(r'^---\n(.*?)\n---',t,re.S); fm=m.group(1) if m else ''
    mm=re.search(r'^model:\s*(\S+)',fm,re.M)
    if not mm or mm.group(1)=='inherit': nopin.append(os.path.basename(f))
print(f"  custom agents (~/.claude/agents): {len(ag)}   without model pin: {len(nopin)}")
for n in nopin: print("   unpinned (inherits session model):",n)
if not ag: print("   none -> install the routing templates: bash ~/.claude/skills/claude-upkeep/scripts/install-routing.sh --apply")
try: j=json.load(open(h('~/.claude.json')))
except Exception: j={}
agg=collections.defaultdict(lambda:[0,0.0,0])
for p,pv in j.get('projects',{}).items():
    for m,u in (pv.get('lastModelUsage') or {}).items():
        agg[m][0]+=1; agg[m][1]+=float(u.get('costUSD') or 0); agg[m][2]+=int(u.get('outputTokens') or 0)
if agg:
    tot=sum(v[1] for v in agg.values()) or 1.0
    print("  last-session spend by model (one session per project; a sample, not a total):")
    for m,(n,c,o) in sorted(agg.items(), key=lambda kv:-kv[1][1]):
        print(f"   {m:34s} {n:3d} sess  ${c:8.2f}  {c/tot*100:4.0f}%  {o:>10,} out-tok")
    fab=sum(v[1] for m,v in agg.items() if 'fable' in m or 'mythos' in m)
    if fab/tot>0.8:
        print(f"   top-tier model carries {fab/tot*100:.0f}% of spend -> route execution to opus/sonnet agents (SKILL.md: Model routing)")
PY

hr "DOT-DIRS IN \$HOME (untouched >30d)  [ai] = agent/LLM CLI footprint"
cd ~ || exit
now=$(date +%s)
for d in .*/; do
  d="${d%/}"
  case "$d" in .|..|.Trash|.claude|.ssh|.gnupg|.config|.local|.cache) continue;; esac
  # plain toolchain caches: not this skill's business
  case "$d" in .gradle|.m2|.npm|.nvm|.cargo|.rustup|.pyenv|.docker|.vscode*|.android|.bun|.deno|.yarn|.pnpm|.conda|.jupyter|.matplotlib|.zsh*|.bash*|.oh-my-zsh|.CFUserTextEncoding|.DS_Store) continue;; esac
  n=$(find "$d" -type f -exec stat $STATFMT {} + 2>/dev/null | sort -nr | head -1)
  [ -z "$n" ] && continue
  days=$(( (now - n) / 86400 ))
  [ "$days" -le 30 ] && continue
  tag="    "
  case "$d" in
    *agent*|*claude*|*codex*|*copilot*|*cursor*|*gemini*|*gpt*|*grok*|*hermes*|*kimi*|*kiro*|*llm*|*ollama*|*openclaw*|*openclaude*|.pi|*qwen*|*trae*|*windsurf*|*cline*|*aider*|*goose*|.factory|*commandcode*|*antigravity*|*vibe*|*augment*|*opencode*|.amp|*crush*|*droid*|*jules*|*devin*|*openhands*|*figma-ds*|.omp) tag="[ai]";;
  esac
  printf "  %s %-22s %8s  %sd stale\n" "$tag" "$d" "$(sz "$d")" "$days"
done
echo
