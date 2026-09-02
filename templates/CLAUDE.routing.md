<!-- claude-upkeep:routing -->
# Model routing

The session model orchestrates. Execution goes to cheaper models with an explicit pin.
On a Fable session this is the whole point: Fable decides, delegates, verifies. It does not type the code.

## Who does what

| Work | `subagent_type` | Model · effort |
|---|---|---|
| Find files, read code, answer "where/how is X" | `scout` | sonnet · low |
| Well-specified edits, boilerplate, tests, docs, scripts, mechanical refactors | `worker` | sonnet · medium |
| Implement a feature or fix from a spec; multi-file changes | `implementer` | opus · high |
| Draft an implementation plan for the orchestrator to approve | `planner` | opus · high |
| Review a diff for bugs before the orchestrator's final acceptance | `reviewer` | opus · high |
| Second opinion from another model family | `codex:codex-rescue` | Codex |

Unpinned Agent calls fall back to `CLAUDE_CODE_SUBAGENT_MODEL` (sonnet). Pass `model: "opus"` explicitly when a built-in agent (`Explore`, `Plan`, `general-purpose`) needs it.

## Rules

1. **Fable never spawns Fable.** `model: "fable"` on an Agent call only when the user asks for it by name.
2. **Fable works directly only when** the task is small (one file, fully understood, under ~10 lines) or genuinely hard (cross-cutting refactor, bug with no clear root cause, novel design) and delegating would cost more than doing it. Everything in between is delegated.
3. **Effort follows the task, not the model.** Lookups low, routine medium, implementation and review high. `xhigh`/`max` only after a high-effort attempt has actually failed.
4. **Delegation prompts stand alone**: goal, files, constraints, definition of done, what to report back. The subagent sees none of this conversation.
5. **Fan out in one message.** Independent delegations go in a single response. Serialize only real dependencies.
6. **Verify before reporting.** Read the diff or run the check yourself. A subagent saying "done" is a claim, not a result.
7. **Workflows**: pass `model` on every `agent()` call (sonnet for fan-out and mechanical stages, opus for verify/judge) or use `agentType: 'reviewer'` etc. to carry a pin. Do not rely on inheritance. Fable never appears inside a workflow script.

## Sessions that start on Opus or Sonnet

Do the work yourself at the session's effort. Delegate only to fan out. Never escalate to Fable on your own.
<!-- /claude-upkeep:routing -->
