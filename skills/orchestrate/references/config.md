# orchestrate.yaml — schema and resolution rules

Read this when: creating a config for a user/repo, or interpreting an existing one.
Full annotated example: `assets/orchestrate.example.yaml`.

## Locations (project overlays user; keys merge, arrays replace)
1. `$ORCHESTRATE_CONFIG` — explicit path
2. `<git root>/.agents/orchestrate.yaml` (or `.orchestrate.yaml`) — project fleet, committable
3. `~/.agents/orchestrate.yaml` (or `~/.config/orchestrate/config.yaml`) — personal fleet

The config is read by *you* (the orchestrating agent). Scripts don't parse it; you translate an
`agents.<name>` entry into `delegate.sh` flags. That keeps the file human-friendly and the scripts
dependency-free.

## Schema (v1)

```yaml
version: 1
agents:                      # named agents; names are what routes reference
  <name>:
    cli: codex|claude|agy|gemini|grok|cursor|opencode|pi|custom   # required
    model: <cli-native id>   # optional  → --model
    effort: low|medium|high|xhigh|max                              # optional  → --effort (clamped per CLI)
    env: {K: V, …}           # optional  → --env K=V (values like $ZAI_API_KEY are expanded by your shell)
    command: "<shell>"       # only for cli: custom → --command
    strengths: [tags…]       # free-form hints for your judgment; not machine-read
    notes: "<free text>"
routes:                      # lane → ordered candidates; first *ready* agent wins; "self" = inline
  implement: [..]  fix: [..]  refactor: [..]  test: [..]  review: [..]  research: [..]
  ui: [..]  docs: [..]  mechanical: [..]  default: [..]  <custom-lane>: [..]
policy:
  delegate_threshold: never|small|medium|large   # default medium
  parallel_max: <int>                            # default 3
  worktree: always|auto|never                    # default auto
  timeout_s: <int>                               # default 1800
  delegate_may_commit: true|false                # default false
  verify: [gates, diff, cross-review-on-risk]    # default all three
  retry: <int>                                   # default 1
  escalate_after: <int>                          # default 3
```

## Resolution order for "which agent"
1. Explicit user pin in the request ("use grok", "have codex do it") — always wins, even if the
   inventory says unknown auth (try, then report).
2. `routes.<lane>` from project config, else user config.
3. Built-in defaults: implement/fix/refactor/test/mechanical → `codex`; review/research → `grok`,
   then `agy`; ui → `claude`; docs → `self`; default → first ready agent in inventory order.
4. Skip candidates that inventory marks not installed / needs-login. For `review`, skip the agent
   that produced the code.

## Bootstrapping a config
Run `scripts/inventory.sh`, copy `assets/orchestrate.example.yaml` to `~/.agents/orchestrate.yaml`,
delete agents that aren't ready, ask the user (once, briefly) which lanes they want on which agent,
and write it. Prefer *fewer* agents with clear roles over a long list.
