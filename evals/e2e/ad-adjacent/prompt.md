# E2E case: ad-adjacent

Feed this exact text to the skill as the user's one-line request.

```
Build a plugin that shows a small promotional overlay banner over the video whenever it's paused,
and hides it again on play.
```

## What must happen

No Unisphere runtime matches (pause overlays aren't a documented runtime). The prompt names an
overlay, a fixed small area, not a panel, so node 2 of
`skills/playkit-js-plugin-builder/reference/decision-tree.md` resolves to component UI:
`this.player.ui.addComponent(...)`, called from `loadMedia()`, with the returned remove function
stored and called from both `reset()` and `destroy()` (the official template's known leak, per the
decision tree). The show/hide-on-pause behavior is driven by `this.eventManager.listen(...)` on the
player's pause/play events, not a second raw listener.

Mode is left for `scripts/detect-mode.sh` to decide.
