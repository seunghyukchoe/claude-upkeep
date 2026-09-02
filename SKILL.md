---
name: claude-upkeep
description: Audit and prune the local Claude Code installation — stale runtime caches, unused skills and plugins and their per-session token cost, dead hooks, MCP servers never authorized, orphaned project entries in .claude.json, stale AI-CLI dot-directories in $HOME, and model routing (which model actually does the work — the session model should orchestrate, opus/sonnet agents execute). Use monthly, when sessions feel slow to start, when spend looks high, or when the user asks to clean up / optimize their Claude setup, skills, hooks, agents, or config. Triggers on "claude 정리", "설정 최적화", "skill 정리", "모델 라우팅", "clean up my claude config", "why is startup slow", "why is Fable doing everything".
---

# Claude upkeep

Recurring maintenance for `~/.claude` and the surrounding agent-CLI footprint.
Three scripts: **audit** (default, read-only), **prune** (moves things to Trash — never `rm`),
and **install-routing** (installs the model-routing policy and pinned-model agents).

## Run the audit

```bash
bash ~/.claude/skills/claude-upkeep/scripts/audit.sh
```

Report the output as a short table, then recommend actions. Do not prune, and do not edit
`settings.json`, without saying what will change and getting a yes. Installing the routing
templates is additive (new files plus a marked block in `CLAUDE.md`) and may proceed when
the user asked for routing or orchestration to be fixed.

## What the audit checks, and the thresholds that matter

| Check | Healthy | Act when |
|---|---|---|
| Skill descriptions injected per session | < 3k tokens | > 5k tokens → archive dormant skills |
| Skills never invoked (`skillUsage` in `.claude.json`) | < 30% of installed | > 50% → archive |
| Plugin agents/skills/commands injected per session | every enabled plugin has `usageCount` > 0 | a never-used plugin costing > 500 tokens → disable it |
| `session-env/` entries | < 200 | > 400, or any older than 7d |
| `telemetry/1p_failed_events.*` | absent | present (they never retry; pure dead weight) |
| `projects/*.jsonl` older than 60d | none | present → offer to trash |
| `.claude.json` project entries pointing at deleted dirs | 0 | > 0 → prune |
| Hook commands whose target file is missing | 0 | > 0 → remove the hook from settings.json |
| MCP servers dialed at startup but never authorized | 0 | > 0 → authorize, or disable the plugin/connector that brings them |
| Routing policy in `~/.claude/CLAUDE.md` | present | missing → `install-routing.sh --apply` |
| Custom agents without a `model:` pin | 0 | > 0 → pin them; an unpinned agent inherits the session model |
| Top-tier model's share of last-session spend | < 50% | > 80% → the orchestrator is doing the typing; fix routing |
| `$HOME` agent-CLI dot-dirs untouched > 30d | — | report size; the user decides |

### The skill-context rule

Every installed skill's `name` + `description` is injected into **every** session's system
prompt, whether or not the skill is used. The same is true of every enabled plugin's agents,
skills, and commands. That is the single largest recurring cost of a big skill library.
Dormant skills belong in `~/.claude/skills-archive/`, which Claude Code does not load.
Archiving is a `mv`, fully reversible:

```bash
mv ~/.claude/skills-archive/<name> ~/.claude/skills/
```

Never archive a skill that appears in `skillUsage` with a recent `lastUsedAt`. When a whole
cluster is dormant (e.g. all 8 `gsap-*`), archive the cluster — partial clusters leave
cross-references dangling. A never-used plugin is disabled with `"<name>": false` under
`enabledPlugins` in `settings.json`; flip it back when needed.

### The model-routing rule

The expensive model should orchestrate — decide, delegate, verify — and cheaper models
should execute. Three mechanisms, in order of leverage:

1. **`CLAUDE_CODE_SUBAGENT_MODEL`** under `env` in `settings.json`. Every Agent call,
   agent-team teammate, and workflow agent without an explicit `model` resolves to this
   instead of the session model. Set it to `sonnet`. This alone stops the built-in agents
   (`Explore`, `Plan`, `general-purpose`) from silently running on the session model.
2. **Pinned agents** in `~/.claude/agents/`: `scout` (sonnet · low), `worker` (sonnet · medium),
   `implementer`, `planner`, `reviewer` (opus · high). Frontmatter `model:` and `effort:`
   (`low|medium|high|xhigh|max`). Resolution order is per-call `model` > agent frontmatter >
   env var > session model.
3. **The routing block** in `~/.claude/CLAUDE.md`, marked `<!-- claude-upkeep:routing -->`:
   the rules the orchestrator follows — never spawn the top-tier model, delegate anything
   that is neither tiny nor genuinely hard, effort by task, standalone delegation prompts,
   verify before reporting.

```bash
bash ~/.claude/skills/claude-upkeep/scripts/install-routing.sh          # dry run
bash ~/.claude/skills/claude-upkeep/scripts/install-routing.sh --apply  # write
```

Re-running updates the marked block in place and leaves the rest of `CLAUDE.md` alone. Agent
files you have edited are kept unless `--force` (originals go to Trash). The script reports
whether `CLAUDE_CODE_SUBAGENT_MODEL` is set but does not edit `settings.json` — add it by hand:

```json
"env": { "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet" }
```

The spend line in the audit is a sample (the last session of each project), not a total.
Its job is the *ratio*: if the top-tier model carries more than 80%, delegation is not happening.

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
3. **Duplicate registrations.** The same command under many *events* is usually one installer
   run repeatedly. The same command under several *matchers of one event* is normal —
   `SessionStart` with `startup|resume|clear|compact` in a single matcher is the tidy form.
4. **Stale `enabledPlugins`** whose `pluginUsage.usageCount` is 0 — each one injects its agents
   and skills into every session and may pull an MCP server that is dialed at every startup.
5. **`CLAUDE_CODE_SUBAGENT_MODEL`** present under `env`, and every file in `~/.claude/agents/`
   carrying a `model:` pin.

## Cadence

Monthly is right. To automate the audit half:

```bash
/loop 30d bash ~/.claude/skills/claude-upkeep/scripts/audit.sh
```

or register it as a routine with the `schedule` skill. Keep **prune** manual.

## After a prune or a routing change

Append a one-line entry to `~/.claude/projects/-/memory/MEMORY.md` recording the date, what
was reclaimed or installed, and what was decided — so the next run knows what was already
settled and does not re-litigate it.
