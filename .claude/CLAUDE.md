@../AGENTS.md

Repo-specific notes on top of the global guidance:

- This is a Claude Code skill/plugin under construction. Don't assert Kaltura API facts from memory —
  everything must trace to `docs/plans/2026-09-09-plugin-skill-research.md` or a live source.
- A dev-time symlink `.claude/skills/playkit-js-plugin-builder` points at the real
  `skills/playkit-js-plugin-builder` so this skill can be dogfooded in this same session while it's
  being built. There is no separate command; the skill is user-invocable directly.
