# E2E case: event-bridge

Feed this exact text to the skill as the user's one-line request.

```
Build a plugin that sends play, pause, and complete events to our analytics endpoint at
https://analytics.example.com/collect. There's no visible UI, it just reports events.
```

## What must happen

No Unisphere runtime matches ("send events to an endpoint" is not a known runtime). The prompt's
verbs ("reacts to X and reports Y", no mention of a control/panel) mean node 1 of
`skills/playkit-js-plugin-builder/reference/decision-tree.md` resolves to no-UI, so the branch is
event-bridge. Events are consumed through `this.eventManager.listen(...)`, never
`player.addEventListener`, and the plugin never calls `ui.addComponent`.

Mode is left for `scripts/detect-mode.sh` to decide.
