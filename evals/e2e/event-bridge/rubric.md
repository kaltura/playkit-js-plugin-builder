# LLM rubric: event-bridge

Grader: `evals/grade.py e2e --case-dir evals/e2e/event-bridge --transcript <agent-output>`.

Read the agent's final message and its intake echo-back line. Answer each criterion `correct` or
`incorrect`, with one sentence of reasoning first.

1. **Branch named correctly.** The agent states it is building an event-bridge plugin (no UI)
   before scaffolding, not a UI plugin.
2. **Signal cited.** The agent's reasoning for the branch points at the prompt's own wording
   ("reports events", "no visible UI"), not a guess.
3. **Endpoint treated as config, validated at the boundary.** The analytics endpoint URL is a typed
   config field checked at construction/`isValid()`, not a hardcoded string used directly.
4. **Failure mode named.** The agent states (in `PLAN.md` or its final message) what happens when
   the analytics endpoint is unreachable: playback is never blocked by it.
5. **Defaults stated back.** The agent states the plugin name and mode it inferred before writing
   code.
6. **At most one open question.** The echo-back line asks at most one open question total.

## Verdict

`all_correct` if every criterion above is `correct`. Otherwise list which criteria failed and why.
