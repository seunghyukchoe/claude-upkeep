#!/usr/bin/env bash
# Install the model-routing policy (a marked block in ~/.claude/CLAUDE.md) and the
# pinned-model agents (~/.claude/agents/*.md) from templates/.
# Usage: install-routing.sh [--apply] [--force]
#   default  dry run — prints what would change
#   --apply  write files
#   --force  also replace agent files you have edited (originals -> ~/.Trash/claude-upkeep-<date>/agents/)
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
T="$HERE/templates"
C=~/.claude
APPLY=0; FORCE=0
for a in "$@"; do case "$a" in --apply) APPLY=1;; --force) FORCE=1;; esac; done
Q=~/.Trash/claude-upkeep-$(date +%Y-%m-%d)

[ "$APPLY" -eq 1 ] && echo "APPLY" || echo "DRY RUN (pass --apply to write)"

# 1. The routing block in CLAUDE.md. Marked, so re-running updates it in place and
#    never touches anything you wrote outside the markers.
python3 - "$C/CLAUDE.md" "$T/CLAUDE.routing.md" "$APPLY" <<'PY'
import sys,os,re
md,tp,apply=sys.argv[1],sys.argv[2],sys.argv[3]=="1"
new=open(tp,encoding='utf-8').read().rstrip('\n')
pat=re.compile(r'<!-- claude-upkeep:routing -->.*?<!-- /claude-upkeep:routing -->',re.S)
if not os.path.isfile(md):
    print("  CLAUDE.md: create from template")
    if apply: open(md,'w',encoding='utf-8').write(new+'\n')
else:
    t=open(md,encoding='utf-8').read()
    m=pat.search(t)
    if m and m.group(0)==new:
        print("  CLAUDE.md: routing block up to date")
    elif m:
        print("  CLAUDE.md: replace routing block (rest of file kept)")
        if apply: open(md,'w',encoding='utf-8').write(t[:m.start()]+new+t[m.end():])
    else:
        print("  CLAUDE.md: append routing block (existing content kept)")
        if apply: open(md,'a',encoding='utf-8').write(('\n' if not t.endswith('\n') else '')+'\n'+new+'\n')
PY

# 2. Agents. Never overwrite an edited file unless --force.
for f in "$T"/agents/*.md; do
  n=$(basename "$f"); dst=$C/agents/$n
  if [ ! -f "$dst" ]; then
    echo "  agents/$n: install"
    [ "$APPLY" -eq 1 ] && { mkdir -p "$C/agents"; cp "$f" "$dst"; }
  elif diff -q "$f" "$dst" >/dev/null; then
    echo "  agents/$n: up to date"
  elif [ "$FORCE" -eq 1 ]; then
    echo "  agents/$n: replace (your copy -> $Q/agents/)"
    [ "$APPLY" -eq 1 ] && { mkdir -p "$Q/agents"; mv "$dst" "$Q/agents/$n"; cp "$f" "$dst"; }
  else
    echo "  agents/$n: exists and differs -> kept (pass --force to replace)"
  fi
done

# 3. The subagent default. Reported only — settings.json is yours to edit.
if python3 - <<'PY' 2>/dev/null
import json,os,sys
s=json.load(open(os.path.expanduser('~/.claude/settings.json')))
sys.exit(0 if (s.get('env') or {}).get('CLAUDE_CODE_SUBAGENT_MODEL') else 1)
PY
then echo "  settings.json: CLAUDE_CODE_SUBAGENT_MODEL is set"
else
  echo "  settings.json: CLAUDE_CODE_SUBAGENT_MODEL not set -> unpinned subagents inherit the session model"
  echo '    add:  "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet" }'
fi
