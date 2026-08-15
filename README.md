# claude-upkeep

A maintenance skill for [Claude Code](https://claude.com/claude-code). It audits your local
install — and tells you the one number nobody thinks to measure: **how many tokens your
installed skills cost you in every single session, whether or not you use them.**

Every skill's `name` and `description` is injected into the system prompt on every session,
used or not. A large skill library is a standing tax you never see in `du` output.

On the machine this was written for: **8,244 tokens → 2,617 tokens per session (−68%)**,
by archiving 53 skills that `skillUsage` showed had never once been invoked.

## What it checks

| Check | Flags when |
|---|---|
| Skill descriptions injected per session | > 5k tokens |
| Skills never invoked (from `skillUsage`) | > 50% of installed |
| `session-env/` entries | > 400, or older than 7d |
| `telemetry/1p_failed_events.*` | present — these never retry |
| Transcripts older than 60d | present |
| `.claude.json` entries for deleted directories | any |
| Hook commands whose target file is missing | any |
| Hooks on `PreToolUse`/`PostToolUse` with matcher `*` | any — these run on *every tool call* |
| Plugins enabled but never used | any — each may dial an MCP server at startup |
| Agent-CLI dot-dirs in `$HOME` untouched > 30d | reported with size |

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
bash ~/.claude/skills/claude-upkeep/scripts/audit.sh    # read-only
bash ~/.claude/skills/claude-upkeep/scripts/prune.sh    # dry run
bash ~/.claude/skills/claude-upkeep/scripts/prune.sh --apply
```

Sample audit output:

```
SKILL CONTEXT COST  (injected into every session)
  72 active skills  ~32977 chars  ~8244 tokens per session
  never invoked: 60/72
    adhd, animation-vocabulary, apple-design, banner-design, brand, ...

CONFIG HEALTH
  hook registrations: 16 across 11 events
   duplicated x10: if [ -f '~/.some-vendor/agent-hooks/claude-hook....
   fires on EVERY tool call: 2 hook(s) -> ['PostToolUse', 'PreToolUse']
  .claude.json project entries: 25 (4 pointing at deleted dirs)
   enabled but never used: some-plugin@some-marketplace
```

## Safety

`prune.sh` **never calls `rm`.** Everything moves to `~/.Trash/claude-upkeep-<date>/` and stays
recoverable until you empty the Trash yourself.

Never touched, by design:

- `settings.json`, `skills/`, `plugins/` — config is yours to change deliberately
- transcripts newer than 60 days — that is your live `/resume` history
- `.claude.json` — the running app rewrites it on exit, so edits during a session get
  clobbered. Prune its orphan entries only with Claude Code closed.

Skill archiving is deliberately **not** automated. It is a `mv` into `~/.claude/skills-archive/`,
which Claude Code does not load, and it is reversed by moving the directory back. Archive
dormant *clusters* whole — pulling three of eight `gsap-*` skills leaves cross-references
dangling.

## Cadence

Monthly. To automate the read-only half:

```bash
/loop 30d bash ~/.claude/skills/claude-upkeep/scripts/audit.sh
```

Keep `prune` manual.

## Compatibility

macOS and Linux. Requires `bash`, `python3`, and GNU or BSD `stat` (both are handled).
Written against Claude Code's `~/.claude` layout as of 2026-08.

## License

MIT
