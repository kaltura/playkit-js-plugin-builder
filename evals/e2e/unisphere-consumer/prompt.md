# E2E case: unisphere-consumer

Feed this exact text to the skill as the user's one-line request. Don't add anything else: the
point of this case is to see whether the skill routes to the Unisphere consumer branch on a prompt
that never says the word "Unisphere".

```
Add the AI video summary side panel to the player.
```

## What must happen

Per `docs/plans/2026-09-09-plugin-skill-research.md` §16.6 and
`skills/playkit-js-plugin-builder/reference/unisphere-integration.md`, "AI video summary" matches
the existing Unisphere runtime `unisphere.widget.video-summary` (`kaltura-player-list`). The skill
must build a thin consumer plugin on `@playkit-js/unisphere-service` (the `unisphere-summary`
shape), not a rebuilt summary feature, side panel, or icon. See
`skills/playkit-js-plugin-builder/reference/decision-tree.md` node 0.

Mode is left for `scripts/detect-mode.sh` to decide (don't specify it in the prompt); this case
runs in whatever mode the eval host resolves to.
