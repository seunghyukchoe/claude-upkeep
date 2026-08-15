#!/usr/bin/env bash
# Move stale Claude runtime files to Trash. Nothing is ever rm'd.
# Usage: prune.sh [--apply]   (default: dry run)
set -uo pipefail
C=~/.claude
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
Q=~/.Trash/claude-upkeep-$(date +%Y-%m-%d)

act() { # act <label> <path...>
  local label="$1"; shift
  [ "$#" -eq 0 ] && return
  local n=0
  for p in "$@"; do [ -e "$p" ] && n=$((n+1)); done
  [ "$n" -eq 0 ] && return
  printf "  %-26s %s item(s)\n" "$label" "$n"
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$Q/$label"
    for p in "$@"; do [ -e "$p" ] && mv "$p" "$Q/$label/" 2>/dev/null; done
  fi
}

[ "$APPLY" -eq 1 ] && echo "APPLY -> $Q" || echo "DRY RUN (pass --apply to move)"

IFS=$'\n'
act session-env    $(find $C/session-env -maxdepth 1 -mindepth 1 -mtime +7 2>/dev/null)
act telemetry      $(ls $C/telemetry/1p_failed_events.*.json 2>/dev/null)
act shell-snapshots $(find $C/shell-snapshots -mtime +7 -type f 2>/dev/null)
act paste-cache    $(find $C/paste-cache -maxdepth 1 -mindepth 1 -mtime +7 2>/dev/null)
act json-backups   $(ls -t $C/backups/.claude.json.backup.* 2>/dev/null | tail -n +3)
act old-transcripts $(find $C/projects -name '*.jsonl' -mtime +60 2>/dev/null)
unset IFS

echo
echo "Not touched by design: settings.json, skills/, plugins/, .claude.json,"
echo "transcripts newer than 60d. Skill archiving is a separate, explicit step:"
echo "  mv ~/.claude/skills/<name> ~/.claude/skills-archive/"
