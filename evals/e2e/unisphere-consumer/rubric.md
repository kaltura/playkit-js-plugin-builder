# LLM rubric: unisphere-consumer

Grader: `evals/grade.py e2e --case-dir evals/e2e/unisphere-consumer --transcript <agent-output>`
(rubric grader; see `evals/README.md` for the "reason first, then verdict" contract).

Read the agent's final message and its intake echo-back line (the "building X as Y, say so if
wrong" line from plan §4 phase 0). Answer each criterion `correct` or `incorrect`, with one sentence
of reasoning first.

1. **Branch named correctly.** The agent states it is building on the Unisphere consumer branch
   (or names `@playkit-js/unisphere-service` / the `unisphere.widget.video-summary` runtime) before
   scaffolding, not after.
2. **No rebuild framing.** The agent never describes writing its own summary UI, side panel, or
   workspace loader — it describes consuming an existing runtime. Supplying a value for the layout
   config's required `header.icon` field (even a disclosed placeholder pending a real asset) is not
   a rebuild; only a hand-built icon *rendering system* (its own icon font, component, or asset
   pipeline replacing what the runtime already provides) counts against this criterion.
3. **Runtime cited, not guessed.** The agent names the specific widget id
   (`unisphere.widget.video-summary`) and, if it names a runtime name, the runtime it cites matches
   `reference/unisphere-integration.md` rather than an invented one.
4. **Loader-URL gap surfaced.** The agent's `PLAN.md` echo (or final message) names the Unisphere
   loader URL / runtime entitlement as the open question, if the operator's player type is unknown,
   rather than silently assuming a SaaS embed.
5. **At most one open question.** The echo-back line asks at most one open question total (plan
   §4 phase 0 constraint), even if this branch has its own known gap (item 4).
6. **Defaults stated back.** The agent states the plugin name and mode it inferred before writing
   code, so the operator can correct it.

## Verdict

`all_correct` if every criterion above is `correct`. Otherwise list which criteria failed and why.
