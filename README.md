# claude-upkeep

A maintenance skill for [Claude Code](https://claude.com/claude-code). It audits your local
install and tells you the two numbers nobody thinks to measure:

1. **How many tokens your installed skills and plugins cost you in every single session,
   whether or not you use them.** Every skill's `name` and `description` — and every enabled
   plugin's agents, skills, and commands — is injected into the system prompt on every
   session. A large library is a standing tax you never see in `du` output.
2. **Which model is actually doing the work.** If your session runs on the top-tier model and
   every subagent silently inherits it, the orchestrator is typing the boilerplate. The audit
   shows the spend ratio per model and whether a routing policy exists.

On the machine this was written for: skill descriptions went **8,244 → 2,062 tokens per
session (−75%)** by archiving 53 never-invoked skills, and the last-session spend sample
showed the top-tier model carrying **93%** of cost with zero pinned agents — which is what
the routing templates fix.

## What it checks

| Check | Flags when |
|---|---|
| Skill descriptions injected per session | > 5k tokens |
| Skills never invoked (from `skillUsage`) | > 50% of installed |
| Enabled plugins never used (from `pluginUsage`) | any — shown with their per-session token cost and hook count |
| `session-env/` entries | > 400, or older than 7d |
| `telemetry/1p_failed_events.*` | present — these never retry |
| Transcripts older than 60d | present |
| `.claude.json` entries for deleted directories | any |
| Hook commands whose target file is missing | any |
| Hooks on `PreToolUse`/`PostToolUse` with matcher `*` | any — these run on *every tool call* |
| MCP servers dialed at startup but never authorized | any |
| Routing policy in `~/.claude/CLAUDE.md` | missing |
| Custom agents without a `model:` pin | any — they inherit the session model |
| Top-tier model's share of last-session spend | > 80% |
| Agent-CLI dot-dirs in `$HOME` untouched > 30d | reported with size, tagged `[ai]` |

The last one earns its keep on its own. Every AI CLI you have ever tried left a directory in
`$HOME` and none of them clean up after themselves.

## Install

```bash
git clone https://github.com/seunghyukchoe/claude-upkeep ~/.claude/skills/claude-upkeep
chmod +x ~/.claude/skills/claude-upkeep/scripts/*.sh
```

Claude Code picks the skill up on next start. Then just ask it to clean up your Claude
config, or run the scripts directly.

## Use

```bash
bash ~/.claude/skills/claude-upkeep/scripts/audit.sh              # read-only
bash ~/.claude/skills/claude-upkeep/scripts/prune.sh              # dry run
bash ~/.claude/skills/claude-upkeep/scripts/prune.sh --apply      # move stale runtime to Trash
bash ~/.claude/skills/claude-upkeep/scripts/install-routing.sh    # dry run
bash ~/.claude/skills/claude-upkeep/scripts/install-routing.sh --apply
```

Sample audit output:

```
PLUGIN CONTEXT COST  (agents + skills + commands of enabled plugins)
  codex@openai-codex                   ~  363 tokens/session  12 items  3 hooks  used 588x
  humanize-korean@im-not-ai            ~ 1572 tokens/session  12 items  0 hooks  used 0x  <- NEVER USED

MODEL ROUTING  (who does the work)
  settings.json model: opus[1m]   effortLevel: medium
  ~/.claude/CLAUDE.md: MISSING -> no global routing policy; every Agent call inherits the session model
  custom agents (~/.claude/agents): 0   without model pin: 0
  last-session spend by model (one session per project; a sample, not a total):
   claude-fable-5                       6 sess  $  139.17    93%     497,743 out-tok
   claude-sonnet-5                      2 sess  $    8.70     6%      30,366 out-tok
   top-tier model carries 93% of spend -> route execution to opus/sonnet agents
```

## Model routing

The expensive model should orchestrate — decide, delegate, verify — and cheaper models
should execute. `install-routing.sh` puts three things in place:

- **A marked block in `~/.claude/CLAUDE.md`** (`<!-- claude-upkeep:routing -->`) with the
  rules: who does what, never spawn the top-tier model, delegate anything that is neither
  tiny nor genuinely hard, effort by task, standalone delegation prompts, verify before
  reporting. Re-running replaces the block in place; the rest of the file is untouched.
- **Five pinned agents** in `~/.claude/agents/`:

  | Agent | Model · effort | Job |
  |---|---|---|
  | `scout` | sonnet · low | read-only recon: where is X, how does Y work |
  | `worker` | sonnet · medium | bounded, well-specified edits, tests, docs, scripts |
  | `implementer` | opus · high | a feature or fix from a spec, multi-file |
  | `planner` | opus · high | read-only implementation plan for the orchestrator to approve |
  | `reviewer` | opus · high | read-only bug review of a diff before final acceptance |

  Edited agent files are kept unless you pass `--force`; originals then go to Trash.
- **A reminder to set `CLAUDE_CODE_SUBAGENT_MODEL`** in `settings.json` — the script does
  not edit that file. With it set to `sonnet`, every unpinned Agent call, agent-team teammate,
  and workflow agent stops inheriting the session model:

  ```json
  "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet" }
  ```

Resolution order, per the Claude Code docs: per-call `model` > agent frontmatter `model:` >
`CLAUDE_CODE_SUBAGENT_MODEL` > session model.

## What prune never touches

`settings.json`, `skills/`, `plugins/`, `.claude.json`, and any transcript newer than 60 days
(that is your `/resume` history). Everything it does move goes to
`~/.Trash/claude-upkeep-<date>/` — nothing is ever `rm`'d.

## License

MIT
