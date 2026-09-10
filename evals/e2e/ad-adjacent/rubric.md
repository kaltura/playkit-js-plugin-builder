# LLM rubric: ad-adjacent

Grader: `evals/grade.py e2e --case-dir evals/e2e/ad-adjacent --transcript <agent-output>`.

Read the agent's final message and its intake echo-back line. Answer each criterion `correct` or
`incorrect`, with one sentence of reasoning first.

1. **Branch named correctly.** The agent states it is building a component-UI plugin (a small
   overlay, not a panel) before scaffolding.
2. **Signal cited.** The agent's reasoning points at "small", "overlay", "banner" in the prompt as
   the signal for component UI over side-panel UI.
3. **Leak avoided, and said so.** The agent's plan or final message notes that the addComponent
   remove function is called on both `reset()` and `destroy()`, naming the template's known leak as
   the reason.
4. **Defaults stated back.** The agent states the plugin name and mode it inferred before writing
   code.
5. **At most one open question.** The echo-back line asks at most one open question total.

## Verdict

`all_correct` if every criterion above is `correct`. Otherwise list which criteria failed and why.
