# LLM rubric: side-panel-ui

Grader: `evals/grade.py e2e --case-dir evals/e2e/side-panel-ui --transcript <agent-output>`.

Read the agent's final message and its intake echo-back line. Answer each criterion `correct` or
`incorrect`, with one sentence of reasoning first.

1. **Branch named correctly.** The agent states it is building a side-panel-UI plugin (the services
   registry, a dedicated panel) before scaffolding, not a component-UI overlay.
2. **Signal cited.** The agent's reasoning points at "chapters list" / "panel" needing its own
   space, not a small fixed control, as the reason it isn't component UI.
3. **No rebuild-of-Unisphere confusion.** The agent does not treat this as the Unisphere
   video-summary branch; cue points are explicitly the operator's own data, not an AI runtime.
4. **i18n named.** The agent's plan states it will ship `en` plus at least one more locale (plan §8
   item 8), not `en` only, since this plugin has user-visible text.
5. **Defaults stated back.** The agent states the plugin name, mode, and second locale it chose
   before writing code, so the operator can correct any of them.
6. **At most one open question.** The echo-back line asks at most one open question total.

## Verdict

`all_correct` if every criterion above is `correct`. Otherwise list which criteria failed and why.
