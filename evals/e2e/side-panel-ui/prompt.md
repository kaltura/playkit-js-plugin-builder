# E2E case: side-panel-ui

Feed this exact text to the skill as the user's one-line request.

```
Build a plugin that shows a chapters list side panel, generated from the video's cue points. We
also need it in French, not just English.
```

## What must happen

No Unisphere runtime covers hand-authored cue-point chapters (only the AI video summary runtime
does, and this prompt asks for cue points, not AI). Node 0 of
`skills/playkit-js-plugin-builder/reference/decision-tree.md` should record "no Unisphere runtime
covers this" and fall through to node 2: this needs a dedicated panel, so the branch is side-panel
UI, built against the services registry (`sidePanelsManager`), not `ui.addComponent`. See
`skills/playkit-js-plugin-builder/reference/services-and-ui-managers.md`.

The prompt's explicit French request is this case's signal for `reference/ui-components.md` §4's
"every locale the operator asked for": the plugin ships `translations/en.i18n.json` **and**
`translations/fr.i18n.json`, not `en` only (design decision plan §5.12 defaults to `en`-only when
nothing is asked — this prompt asks, so that default does not apply here).

Mode is left for `scripts/detect-mode.sh` to decide.
