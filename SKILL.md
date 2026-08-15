---
name: claude-upkeep
description: Audit and prune the local Claude Code installation — stale runtime caches, unused skills and their per-session token cost, dead hooks and MCP servers, orphaned project entries in .claude.json, and stale AI-CLI dot-directories in $HOME. Use monthly, when sessions feel slow to start, when disk pressure appears, or when the user asks to clean up / optimize their Claude setup, skills, hooks, or config. Triggers on "claude 정리", "설정 최적화", "skill 정리", "clean up my claude config", "why is startup slow".
---

# Claude upkeep

Recurring maintenance for `~/.claude` and the surrounding agent-CLI footprint.
Two modes: **audit** (default, read-only) and **prune** (moves things to Trash — never `rm`).

## Run the audit

```bash
bash ~/.claude/skills/claude-upkeep/scripts/audit.sh
```

Report the output as a short table, then recommend actions. Do not prune without saying
what will move and getting a yes.

## What the audit checks, and the thresholds that matter

| Check | Healthy | Act when |
|---|---|---|
| Skill descriptions injected per session | < 3k tokens | > 5k tokens → archive dormant skills |
| Skills never invoked (`skillUsage` in `.claude.json`) | < 30% of installed | > 50% → archive |
| `session-env/` entries | < 200 | > 400, or any older than 7d |
| `telemetry/1p_failed_events.*` | absent | present (they never retry; pure dead weight) |
| `projects/*.jsonl` older than 60d | none | present → offer to trash |
| `.claude.json` project entries pointing at deleted dirs | 0 | > 0 → prune |
| Hook commands whose target file is missing | 0 | > 0 → remove the hook from settings.json |
| MCP servers configured but never authorized | 0 | > 0 → remove or authorize; each costs startup time |
| `$HOME` agent-CLI dot-dirs untouched > 30d | — | report size; the user decides |

### The skill-context rule

Every installed skill's `name` + `description` is injected into **every** session's system
prompt, whether or not the skill is used. That is the single largest recurring cost of a
big skill library. Dormant skills belong in `~/.claude/skills-archive/`, which Claude Code
does not load. Archiving is a `mv`, fully reversible:

```bash
mv ~/.claude/skills-archive/<name> ~/.claude/skills/
```

Never archive a skill that appears in `skillUsage` with a recent `lastUsedAt`. When a whole
cluster is dormant (e.g. all 8 `gsap-*`), archive the cluster — partial clusters leave
cross-references dangling.

## Prune

```bash
bash ~/.claude/skills/claude-upkeep/scripts/prune.sh          # dry run
bash ~/.claude/skills/claude-upkeep/scripts/prune.sh --apply  # move to Trash
```

Everything lands in `~/.Trash/claude-upkeep-<date>/`. Recoverable until the user empties
Trash — that emptying is theirs to do, never yours.

Never touch: `projects/*.jsonl` newer than 60d (that is `/resume` history), `settings.json`,
`skills/` contents, `plugins/`, `.claude.json` (edit only when no Claude session is running —
the app rewrites it on exit and will clobber concurrent edits).

## Config hygiene pass

Read `~/.claude/settings.json` and check:

1. **Dead hook targets.** Every `command` that references a path — confirm it exists and is
   executable. Vendor installers (Orca, Copilot, codebase-memory) add hooks and do not
   remove them on uninstall.
2. **Hook fan-out.** A hook registered on `PreToolUse`/`PostToolUse` with matcher `*` runs on
   every single tool call. Time it: `time (for i in $(seq 1 20); do echo '{}' | sh <hook>; done)`.
   Over ~10ms per call, restrict the matcher or drop the hook.
3. **Duplicate registrations.** The same command registered under many events is usually one
   installer run repeatedly.
4. **Stale `enabledPlugins`** whose `pluginUsage.usageCount` is 0 — each one may pull an MCP
   server that is dialed at every startup.

## Cadence

Monthly is right. To automate the audit half:

```bash
/loop 30d bash ~/.claude/skills/claude-upkeep/scripts/audit.sh
```

or register it as a routine with the `schedule` skill. Keep **prune** manual.

## After a prune

Append a one-line entry to `~/.claude/projects/-/memory/MEMORY.md` recording the date, what
was reclaimed, and what was archived — so the next run knows what was already decided and
does not re-litigate it.
