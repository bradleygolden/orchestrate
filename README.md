# orchestrate

An [Agent Skill](https://agentskills.io) that turns whichever coding agent you're sitting in into an
**orchestrator + router** for the other agent CLIs on your machine.

You keep one agent as the brain (say, Claude Code on Fable). It inventories what's installed —
Codex, Grok, Antigravity (`agy`), Cursor, OpenCode, pi, z.ai GLM via any Anthropic/OpenAI-compatible
CLI — reads *your* routing preferences, and then, using judgment, decides per task whether to do the
work itself or hand it to the agent you prefer for that kind of work. Delegates run headlessly
(optionally in parallel git worktrees); the orchestrator reads their diffs, re-runs the gates, and
lands the result. Never trusts a self-report.

```
you ──▶ orchestrator (Claude Code / Codex / Grok / …)
             │  inventory.sh  → what's installed & authed
             │  orchestrate.yaml → your lanes: implement→codex, review→grok, research→agy, docs→glm …
             ├──▶ delegate.sh --cli codex  … (worktree A)   ┐
             ├──▶ delegate.sh --cli glm    … (worktree B)   ├─ headless, parallel, bounded reports
             └──▶ delegate.sh --cli grok --mode read …      ┘
             ▼
        verify (diff + gates + cross-vendor review) → merge → report
```

Works from any host that can run shell commands and reads Agent Skills: Claude Code, Codex, Grok
Build, Cursor, OpenCode, pi, Gemini/Antigravity, Amp, Copilot CLI, …

## Install

```bash
# one-liner (symlinks into ~/.agents/skills and ~/.claude/skills, seeds ~/.agents/orchestrate.yaml)
curl -fsSL https://raw.githubusercontent.com/bradleygolden/orchestrate/main/install.sh | bash

# or via skills.sh (installs into every agent dir it knows about)
npx skills add bradleygolden/orchestrate -g

# or as a Claude Code plugin
/plugin marketplace add bradleygolden/orchestrate
/plugin install orchestrate@bradleygolden-orchestrate

# per-repo (project-scoped, commit it): from the repo root
npx skills add bradleygolden/orchestrate
```

Then edit `~/.agents/orchestrate.yaml` (or `<repo>/.agents/orchestrate.yaml` for a project fleet):

```yaml
agents:
  codex: { cli: codex, effort: high }              # model omitted → CLI default
  grok:  { cli: grok,  model: grok-4.6 }
  agy:   { cli: agy }
  glm:   { cli: claude, model: glm-5.3, env: { ANTHROPIC_BASE_URL: https://api.z.ai/api/anthropic, ANTHROPIC_AUTH_TOKEN: $ZAI_API_KEY } }
routes:
  implement: [codex, glm]
  review:    [grok, codex]      # builder ≠ reviewer
  research:  [agy, grok, self]
  docs:      [glm, self]
  default:   [codex]
policy:
  delegate_threshold: medium
  parallel_max: 3
  worktree: auto
```

## Use

In your agent: *"orchestrate: implement the export feature, tests included"*, *"delegate this to codex"*,
*"get a second opinion from grok on this diff"*, *"parallelize the migration across my fleet"*.

The skill's loop: **inventory → classify lane → pick agent (pin > project > user > defaults) →
write a self-contained brief → `delegate.sh` → verify (diff, gates, cross-vendor review on risk) →
land → report.**

## Layout

```
skills/orchestrate/
├── SKILL.md                    # the method (≈150 lines; loaded when the skill activates)
├── scripts/inventory.sh        # what's installed/authed, provider keys, config files (table|--json)
├── scripts/delegate.sh         # uniform headless dispatch: --cli … --brief … [--model --effort --mode read|write --env --worktree --timeout]
├── references/adapters.md      # per-CLI flags, models, quirks (codex, claude, agy, gemini, grok, cursor, opencode, pi, custom)
├── references/config.md        # orchestrate.yaml schema + resolution rules
├── references/brief.md         # how to write a delegate brief
└── assets/orchestrate.example.yaml
```

Run artifacts (brief, stdout/stderr, raw JSON, `result.md`) live under `~/.agents/orchestrate/runs/<ts>-<label>/`;
worktrees under `~/.agents/orchestrate/runs/worktrees/`.

## Design notes (what this borrows from)

- Agent Skills spec + best practices — short SKILL.md, progressive disclosure, scripts that emit JSON. ([agentskills.io](https://agentskills.io/specification))
- *Solo is the default; delegate for parallelism, capability/cost gaps, or a second vendor* — Anthropic's harness/context-engineering posts, Osmani's "Code Agent Orchestra".
- *Builder ≠ reviewer; cross-vendor review; never trust self-reports; you land the commit* — codex-gate, gaffer, Yegge's Gas Town ("Rule of Five", worktree per worker, serial merge).
- *Bounded reports back to the parent; full logs on disk* — Anthropic multi-agent research system.
- *Registry of lanes → agents with fallbacks; discovery script; brief template with real gates* — delegate-skills, sub-agents-skills, Symphony.
- *Google: `agy` first, `gemini` API-key fallback* — Gemini CLI → Antigravity CLI transition (2026-06-18).

## Contributing

Add an adapter: a `case` arm in `scripts/delegate.sh`, a probe in `scripts/inventory.sh`, a row in
`references/adapters.md`. Verify with `delegate.sh --cli <x> --prompt "say OK" --dry-run` then a real run.

MIT.
