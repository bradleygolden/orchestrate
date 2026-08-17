---
name: orchestrate
description: Act as an orchestrator/router across the coding-agent CLIs installed on this machine (Codex, Claude Code, Antigravity/Gemini, Grok, Cursor, OpenCode, pi, z.ai GLM). Inventory what is available, read the user's routing preferences (orchestrate.yaml), decide with judgment which tasks to do inline and which to delegate to which agent by task type (implement, fix, test, review, research, ui, docs), write self-contained briefs, run delegates headlessly (optionally in parallel git worktrees), then verify their work yourself and land it. Use when the user says "orchestrate", "delegate", "route this to", "have codex/grok/gemini/glm do it", "use my fleet", "parallelize this across agents", "get a second opinion from another model", or when a task is large/parallelizable and the user has expressed model/CLI preferences. Not for small single-file edits you can do faster inline, or for tasks that need the conversation's context or the user's live input.
license: MIT
compatibility: Requires bash, git, jq and at least one installed+authenticated agent CLI (codex, claude, agy, gemini, grok, agent/cursor-agent, opencode, pi). Host-agnostic — works from Claude Code, Codex, Grok, Cursor, OpenCode, pi, or any agent that can run shell commands.
metadata:
  author: bradleygolden
  version: "0.1.0"
  repo: https://github.com/bradleygolden/orchestrate
---

# Orchestrate — route work to the right agent, verify it yourself

You are the **orchestrator**: the human-facing agent that owns judgment, architecture, scope,
verification and the final commit. Other agent CLIs on this machine are **delegates**: cheap,
parallel, disposable hands. Your token budget is the scarce resource; theirs is often on a separate
subscription. Route accordingly — but *solo is the default*. Delegation costs coordination and
context, so only pay it when it buys parallelism, a capability/cost gap, a fresh perspective, or
what the user asked for.

## 0. Ground rules (read once, apply always)

1. **Never assume the fleet.** Run `scripts/inventory.sh` before the first delegation of a session.
   Route only to agents reported `ready` (or `unknown` if you're willing to try). Never call a CLI
   directly — always go through `scripts/delegate.sh` so runs get uniform envelopes, logs and timeouts.
2. **Preferences beat defaults, pins beat preferences.** Resolution order:
   explicit user pin ("use codex") → project `<repo>/.agents/orchestrate.yaml` → user
   `~/.agents/orchestrate.yaml` → built-in defaults below. If no config exists, propose one from the
   inventory (copy `assets/orchestrate.example.yaml`) and continue with defaults.
3. **Delegates get briefs, not conversations.** A delegate sees nothing you've seen. The brief must be
   self-contained (see §3). One task per brief.
4. **Never trust a delegate's self-report.** Read its diff, re-run the real gates yourself, check
   scope creep against the brief. Builder ≠ reviewer: review with a *different vendor* when it matters.
5. **Bounded context.** Read `result.md` and the changed-file list; do not ingest raw logs unless
   debugging a failure. Keep what flows back to you to a summary.
6. **You land the work.** Delegates don't commit unless the config says so. Isolate parallel or risky
   work in worktrees and merge deliberately — merging is the bottleneck, so partition tasks to minimise
   overlapping files.
7. **Keep judgment at home.** Architecture, scope decisions, ambiguous requirements, anything needing
   the user's live input, security-sensitive design → you (or the user), not a delegate.

## 1. Decide: inline or delegate?

Classify the request into a **lane** (`implement`, `fix`, `refactor`, `test`, `review`, `research`,
`ui`, `docs`, `mechanical`, or a user-defined lane), then decide:

| Do it **inline** when… | **Delegate** when… |
|---|---|
| it's a small/single-file change you can finish faster than writing a brief | it's well-scoped, multi-file, or ≥ ~15 min of agent work |
| it depends on conversation context or unresolved ambiguity | 2+ independent chunks can run in parallel |
| the user expects *your* judgment (design, trade-offs) | the config routes this lane elsewhere, or the user pinned an agent |
| it's security/architecture-critical design | you want a second opinion / adversarial review from another vendor |
| `policy.delegate_threshold: never` | quota/cost: bulk mechanical work belongs on a cheaper subscription |

Unclear scope → do the *understanding* yourself first (or a `research` delegate), then split into
delegable units. Fully specify before slinging; delegates should never need to guess.

## 2. Pick the agent

1. Look up `routes.<lane>` in the config → ordered candidates; take the first one `inventory.sh`
   says is ready. `self` means do it inline.
2. Honour `agents.<name>` (cli, model, effort, env) → they map 1:1 onto `delegate.sh` flags.
3. **Review lane rule:** skip whichever agent produced the code being reviewed.
4. If nothing configured is ready, fall back to built-in defaults: implement/fix/refactor/test →
   `codex`; review/research → `grok` then `agy`; ui → `claude`; else the first ready agent.
5. Tell the user what you routed where and why (one line per delegation) — before or as you dispatch.

## 3. Write the brief

Write it to a temp file (`mktemp`) and pass `--brief`. Template (also in `references/brief.md`):

```
# Task: <one-line goal>
## Context
- Repo: <abs path>; branch <x>. Relevant files: <paths>. Conventions: <how the repo does things>.
- Current state / why: <2-5 lines>
## Requirements
- <numbered, testable requirements>
## Constraints
- Do NOT touch: <paths/areas>. Do not commit. Do not install global deps. Stay inside <dir>.
## Verification (run these before you finish)
- <the repo's REAL commands you discovered: e.g. `pnpm test`, `mix test`, `ruff check .`>
## Report (final message)
- What you changed (files), how you verified (commands + results), anything you could not do, open questions.
```

Discover the actual gate commands from the repo (package.json, Makefile, mix.exs, CI config) — never
invent them. Ask for the report contract explicitly; it's what lands in `result.md`.

## 4. Dispatch

```bash
S=<absolute path of this skill dir>/scripts   # e.g. ~/.agents/skills/orchestrate/scripts
$S/delegate.sh --cli codex --cwd /path/to/repo --brief /tmp/brief-x.md \
  --effort high --mode write --label impl-x --timeout 1800   # add --model only if the config sets one
```

- `--mode read` for review/research/analysis (read-only sandbox / plan mode where the CLI supports it).
- `--env K=V` for provider routing (e.g. the z.ai GLM route through `claude`); secrets by `$VAR`.
- `--worktree` for anything running in parallel or touching many files (branch `orchestrate/<label>`).
- Long tasks: run in the background (your host's background-shell facility) and poll; keep
  ≤ `policy.parallel_max` concurrent. Don't watch delegates work — collect results when they finish.
- The script prints one JSON object (`status`, `exit_code`, `duration_s`, `result_file`,
  `changed_files`, `worktree`, `run_dir`). Everything is kept under `~/.agents/orchestrate/runs/`.
- Per-CLI flags, models, quirks: `references/adapters.md`. Config schema: `references/config.md`.

## 5. Verify, then land

For every delegate run:
1. `cat result.md` — read the report; note claims.
2. Inspect the diff (`git -C <cwd> diff`, plus untracked files from `changed_files`). Check: does it
   match the brief? scope creep? touched forbidden paths? left debug junk?
3. **Re-run the gates yourself.** A delegate's "tests pass" is a claim, not evidence.
4. Risky change (auth, payments, migrations, security, public API) or `policy.verify` includes
   `cross-review-on-risk` → dispatch a `review` lane run in `--mode read` with a *different vendor*,
   brief = spec + diff + "verdict PASS/FAIL with file:line findings".
5. Land it: if it ran in a worktree, `git -C <repo> merge --no-ff orchestrate/<label>` (or
   cherry-pick / apply the diff), then `git worktree remove --force <path>` (delegates leave caches) and delete the branch. Commit
   yourself with an honest message; do not claim verification you didn't do.

Failure handling: `status: error|timeout` or gates fail → re-brief **once** with the failure output
appended as correction context (same agent, `--label <x>-retry`). Still failing → next candidate in
the route. After `policy.escalate_after` total attempts, stop and report to the user with the
run dirs; don't loop.

## 6. Report to the user

End with a compact table: task → agent (model) → status → duration → verification result → where the
work landed (branch/commit). Mention anything you did inline vs delegated and why. Keep it short.

## Patterns worth using

- **Race** (`--label a-codex` / `a-grok`, both `--worktree`): same brief to two vendors, keep the
  better diff, discard the other worktree. Use for hard bugs or when quality matters more than cost.
- **Pipeline**: research (read, agy/grok) → implement (codex/glm, worktree) → review (different
  vendor, read) → you land. Default shape for medium features.
- **Swarm** for mechanical sweeps: split by directory/file group, ≤ `parallel_max` cheap delegates
  in worktrees, merge serially, run gates once at the end.
- **Second opinion**: `--mode read` brief containing your plan/diff, ask for holes. Cheap, high value.

## Gotchas

- Delegates read stdin: `delegate.sh` always closes/feeds it correctly; if you call a CLI by hand, add `</dev/null`.
- Nested `claude` inside Claude Code works because the script unsets `CLAUDECODE`.
- Cursor: never run `agent status`/`cursor-agent status` non-interactively (starts a login flow).
- pi has **no** permission prompts — always `--worktree` or trust the brief.
- Google: `agy` (Antigravity CLI) is the current terminal agent; `gemini` only works with a paid `GEMINI_API_KEY`.
- z.ai/GLM has no CLI: route through `claude` (Anthropic-compatible endpoint), `opencode`, or `pi`. See adapters.md.
- If a delegate's `result.md` looks like an auth or config error, fix/skip that agent and move on — don't retry blindly.
- Model slugs are CLI-native and account-dependent (e.g. Codex on a ChatGPT plan rejects unknown slugs). Prefer omitting `--model` (CLI default) unless the config pins one that inventory/`<cli> models` confirms.
