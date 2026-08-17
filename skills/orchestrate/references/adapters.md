# Adapters — per-CLI headless invocation (what `scripts/delegate.sh` does under the hood)

Read this when: adding a new CLI, debugging a failed run, choosing models/effort for an agent, or
calling a CLI by hand. Verified Aug 2026 (versions noted); CLIs move fast — when a flag errors, run
`<cli> --help` and update this file.

Legend: **write** = autonomous edits + commands; **read** = read-only / plan where the CLI supports it.

| cli | binary | prompt in | write flags | read flags | model | effort | cwd | result field |
|---|---|---|---|---|---|---|---|---|
| codex | `codex exec` | stdin (`-`) | `-s workspace-write` | `-s read-only` | `-m` | `-c model_reasoning_effort="low\|medium\|high\|xhigh"` | `-C` | `-o file` (final message) |
| claude | `claude -p` | stdin | `--permission-mode bypassPermissions` | `--allowedTools "Read Glob Grep …"` | `--model` | `--effort low…max` | `cd` | json `.result` |
| agy | `agy -p` | arg | `--dangerously-skip-permissions` | (omit → shell soft-denied) | `--model` | `--effort low\|medium\|high` | `cd` | json `.response` |
| gemini | `gemini -p` | arg | `--approval-mode yolo` | `--approval-mode plan` | `-m auto\|pro\|flash` | — | `cd` | json `.response` |
| grok | `grok --prompt-file` | file | `--permission-mode bypassPermissions` | `--permission-mode plan` | `-m` | `--reasoning-effort` | `--cwd` | json `.text` |
| cursor | `agent -p` (old: `cursor-agent`) | arg | `--force` | (omit → proposes only) | `--model` | — | `cd` | json `.result` |
| opencode | `opencode run` | arg | `--auto` | `--auto --agent plan` | `-m provider/model` | `--variant` | `--dir` | stdout text |
| pi | `pi -p` | arg | (no permissions exist) | `--tools read,grep,find,ls` | `--model provider/id[:thinking]` | `--thinking` | `cd` | stdout text |

All get `--output-format json` where it exists; `delegate.sh` extracts the field above into `result.md`
and keeps the raw JSON in `raw.json`. Stdin is fed from the brief (codex, claude) or `/dev/null`.

## Per-CLI notes

### codex (OpenAI Codex CLI 0.147) — `codex exec`
- Runs on your ChatGPT plan (`codex login`), so it costs no orchestrator tokens. Prefer the default model from `~/.codex/config.toml`; ChatGPT-plan accounts reject slugs they don't offer (400 "model is not supported").
- `-` as the prompt reads stdin; `--skip-git-repo-check` lets it run outside a repo; `-o` writes only
  the final message (best result capture); `--json` gives JSONL events if you need progress.
- Sandbox: `read-only` for review/analysis, `workspace-write` for implementation (can write in cwd and
  /tmp), `danger-full-access` never by default. `--add-dir` for extra writable dirs.
- Follow-ups: `codex exec resume <session-id> "…"` (id is printed in the run header / stderr.log).
- Also: `codex review --uncommitted|--base main` for reviews; image gen tool built in.
- Docs: https://developers.openai.com/codex/ · skill install: `~/.agents/skills` (native).

### claude (Claude Code 2.1.x) — `claude -p`
- `--output-format json` → `{result, session_id, total_cost_usd, is_error, num_turns}`; add
  `--json-schema` for structured output (`.structured_output`).
- Write: `--permission-mode bypassPermissions` (headless never prompts; denied tools just fail).
  Read: `--permission-mode default --allowedTools "Read Glob Grep WebFetch WebSearch Bash(git diff:*) …"`.
- `--max-turns`, `--max-budget-usd`, `--append-system-prompt`, `--add-dir`, `--no-session-persistence`.
- Nested inside a Claude Code session: unset `CLAUDECODE` (delegate.sh does).
- **z.ai GLM route** (z.ai has no CLI): env
  `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic ANTHROPIC_AUTH_TOKEN=$ZAI_API_KEY
  ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3 ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3 ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7 API_TIMEOUT_MS=3000000`
  then `--model glm-5.3`. Docs: https://docs.z.ai/devpack/tool/claude
- Docs: https://code.claude.com/docs/en/headless

### agy (Antigravity CLI) — Google's current terminal agent
- Gemini CLI stopped serving Google-account (free/AI Pro/Ultra) users on 2026-06-18; `agy` replaced
  it. Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`. Auth: interactive
  Google login once, or API-key mode (`modelProvider: "gemini"` in `~/.gemini/antigravity-cli/settings.json` + `GEMINI_API_KEY`).
- `-p` (alias `--print`), `--print-timeout 10m` (default 5m — delegate.sh passes the run timeout),
  `--model gemini-3.x-…`, `--effort low|medium|high`, `--output-format json` → `.response`,
  `--json-schema`. Headless soft-denies shell unless `--dangerously-skip-permissions`.
- Docs: https://antigravity.google/docs/cli/headless

### gemini (Gemini CLI, API-key only now)
- Still open source and works with a paid `GEMINI_API_KEY` / Vertex / Code Assist Standard+.
- `-p` forces non-interactive; **stdin is prepended to the prompt** — delegate.sh feeds `/dev/null`.
- `--approval-mode yolo|auto_edit|plan|default`, `--output-format json` → `.response`,
  `--include-directories a,b`. Exit 53 = turn limit.
- Docs: https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/headless.md

### grok (Grok Build CLI 0.2.x)
- Auth: `grok login` or `XAI_API_KEY`. Models: `grok models` (grok-4.6 default, grok-4.5).
- One-shot is a **top-level** flag: `-p "<prompt>"` / `--prompt-file <path>` / `--prompt-json`;
  `grok agent …` subcommands are IDE/SDK server modes, not one-shot.
- `--cwd`, `-w/--worktree [name]`, `--permission-mode default|acceptEdits|auto|dontAsk|bypassPermissions|plan`,
  `--always-approve`, `--allow/--deny <rule>`, `--tools`, `--no-subagents`, `--max-turns N`,
  `--best-of-n N` (race N attempts, headless only), `--check` (self-verification loop),
  `--json-schema`, `--rules "<extra system prompt>"`, `--output-format plain|json|streaming-json`.
- JSON: `{text, stopReason, sessionId, usage, num_turns, total_cost_usd, modelUsage}`.
- Docs: https://docs.x.ai/build/cli/headless-scripting

### cursor (Cursor CLI)
- Current binary is `agent` (`curl https://cursor.com/install -fsS | bash`); `cursor-agent` is the
  old build. Auth: `agent login` or `CURSOR_API_KEY`. **Never** run `agent status` non-interactively.
- `-p --output-format json` → `{type:"result", result, is_error, session_id}`; `--force` applies
  edits/commands (without it, `-p` only proposes); newer builds add `--workspace`, `--sandbox`, `--mode plan`.
- Docs: https://cursor.com/docs/cli/headless

### opencode
- Install: `curl -fsSL https://opencode.ai/install | bash`. `opencode run --dir <d> --auto -m provider/model "<msg>"`.
- `--auto` auto-approves everything not denied (without it headless runs can stall). Read-only:
  `--agent plan`. `--variant` = reasoning effort. `--format json` is an event stream (delegate.sh
  keeps text output).
- z.ai: provider `zai-coding-plan` (`ZHIPU_API_KEY`), models `glm-5.3`, `glm-5-turbo`, `glm-4.7`.
- Docs: https://opencode.ai/docs/cli/

### pi (badlogic/earendil-works pi coding agent)
- Install: `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` (or `curl -fsSL https://pi.dev/install.sh | sh`).
- `-p "<prompt>" --no-session`, `--model provider/id[:thinking]`, `--thinking off…max`,
  `--tools read,grep,find,ls` for read-only, `--mode json` for JSONL events, `--api-key`.
- **No permission prompts at all** — treat like a container: use `--worktree`.
- z.ai built in: provider `zai` (`ZAI_API_KEY`), e.g. `--model zai/glm-5.3:high`.
- Docs: https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/README.md

### custom
`--cli custom --command '<shell>'` runs any command in cwd with `ORCH_BRIEF` (path), `ORCH_PROMPT`,
`ORCH_MODEL`, `ORCH_EFFORT`, `ORCH_MODE`, `ORCH_CWD` in env; stdout becomes `result.md`. Use for
CLIs not listed here (amp, copilot, kimi, qwen, aider…) — then add a proper adapter and PR it.

## Adding an adapter to delegate.sh
Add a `case` arm that sets `CMD=(...)`, `STDIN_SRC` (brief file or /dev/null) and `EXTRACT`
(`file`, `jq:<filter>`, or `text`); add an inventory probe in `inventory.sh`; add a row above.
