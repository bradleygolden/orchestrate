#!/usr/bin/env bash
# inventory.sh — discover which coding-agent CLIs are installed/authenticated on this machine,
# which provider keys are present, and which orchestrate config files apply.
#
# Usage: inventory.sh [--json|--table] [--cwd <dir>]
# Never hardcode presence: run this at the start of an orchestration session and route only to
# agents whose status is "ready" (or "unknown" if you are willing to try).
#
# Auth checks are cheap and non-interactive. Some CLIs (Cursor) start a login flow on any status
# call, so we only inspect files/env for those and report "unknown".

set -uo pipefail
FORMAT="table"; CWD="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT=json; shift;;
    --table) FORMAT=table; shift;;
    --cwd) CWD="$2"; shift 2;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
ver() { timeout 10 "$@" 2>/dev/null | head -n1 | tr -d '\r' || true; }
# portable timeout wrapper (macOS lacks GNU timeout unless coreutils installed)
timeout() { if command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"; elif command -v /usr/bin/timeout >/dev/null 2>&1 || command -v /opt/homebrew/bin/timeout >/dev/null 2>&1; then command timeout "$@"; else shift; "$@"; fi; }

D=$'\x1f'   # field delimiter (models strings contain "|")
ROWS=()   # name D binary D installed D version D auth D models D notes
add() { ROWS+=("$1$D$2$D$3$D$4$D$5$D$6$D$7"); }

# ---- codex ---------------------------------------------------------------------------------
if have codex; then
  v="$(ver codex --version)"; a="unknown"
  s="$(timeout 15 codex login status 2>&1 | head -n1)"
  case "$s" in *"Logged in"*) a="ready";; *"Not logged in"*|*"not logged"*) a="needs-login (codex login)";; esac
  add codex codex yes "$v" "$a" "gpt-5.x-codex (default from ~/.codex/config.toml)" "headless: codex exec; sandbox -s read-only|workspace-write"
else add codex codex no "" "" "" "npm i -g @openai/codex"; fi

# ---- claude --------------------------------------------------------------------------------
if have claude; then
  v="$(ver claude --version)"; a="unknown"
  s="$(env -u CLAUDECODE timeout 15 claude auth status 2>/dev/null)"
  case "$s" in *'"loggedIn": true'*|*'"loggedIn":true'*) a="ready";; *'"loggedIn": false'*) a="needs-login (claude auth login)";; esac
  [ -n "${ANTHROPIC_API_KEY:-}" ] && a="ready (ANTHROPIC_API_KEY)"
  add claude claude yes "$v" "$a" "fable|opus|sonnet|haiku" "headless: claude -p; also the z.ai GLM route via ANTHROPIC_BASE_URL"
else add claude claude no "" "" "" "https://code.claude.com"; fi

# ---- antigravity (agy) — Google's current terminal agent ------------------------------------
if have agy; then
  v="$(ver agy --version)"; a="unknown"
  [ -n "${GEMINI_API_KEY:-}" ] && a="ready (GEMINI_API_KEY)"
  [ -d "$HOME/.gemini/antigravity-cli" ] && [ "$a" = unknown ] && a="probably (settings dir exists)"
  add agy agy yes "$v" "$a" "gemini-3.x (e.g. gemini-3.7-flash-high)" "headless: agy -p --dangerously-skip-permissions --output-format json"
else add agy agy no "" "" "" "curl -fsSL https://antigravity.google/cli/install.sh | bash  (replaces Gemini CLI for Google-account auth)"; fi

# ---- gemini cli (API-key only since 2026-06-18) --------------------------------------------
if have gemini; then
  v="$(ver gemini --version)"; a="needs GEMINI_API_KEY (Google-account auth moved to agy)"
  [ -n "${GEMINI_API_KEY:-}" ] && a="ready (GEMINI_API_KEY)"
  add gemini gemini yes "$v" "$a" "auto|pro|flash|flash-lite" "headless: gemini -p --approval-mode yolo --output-format json"
else add gemini gemini no "" "" "" "npm i -g @google/gemini-cli (only if you have a paid GEMINI_API_KEY; otherwise use agy)"; fi

# ---- grok build ----------------------------------------------------------------------------
if have grok; then
  v="$(ver grok --version)"; a="unknown"; m=""
  s="$(timeout 20 grok models 2>&1)"
  case "$s" in *"logged in"*) a="ready";; *"not logged"*|*"login"*) a="needs-login (grok login)";; esac
  [ -n "${XAI_API_KEY:-}" ] && a="ready (XAI_API_KEY)"
  m="$(printf '%s\n' "$s" | grep -E '^[[:space:]]*[*-] ' | sed -E 's/^[[:space:]]*[*-] //; s/ \(default\)//' | tr '\n' ' ')"
  add grok grok yes "$v" "$a" "${m:-grok-4.x}" "headless: grok -p|--prompt-file --cwd --permission-mode bypassPermissions --output-format json"
else add grok grok no "" "" "" "curl -fsSL https://x.ai/cli/install.sh | bash"; fi

# ---- cursor --------------------------------------------------------------------------------
CB=""; if have agent && agent --help 2>/dev/null | grep -qi cursor; then CB=agent; elif have cursor-agent; then CB=cursor-agent; fi
if [ -n "$CB" ]; then
  v="$(ver "$CB" --version)"; a="unknown (do NOT run '$CB status' non-interactively — it starts a login flow)"
  [ -n "${CURSOR_API_KEY:-}" ] && a="ready (CURSOR_API_KEY)"
  n="headless: $CB -p --force --output-format json"; [ "$CB" = cursor-agent ] && n="$n; NOTE: old build — reinstall (curl https://cursor.com/install -fsS | bash) to get 'agent'"
  add cursor "$CB" yes "$v" "$a" "gpt-5*, sonnet-4*, opus*, etc. (see '$CB models')" "$n"
else add cursor agent no "" "" "" "curl https://cursor.com/install -fsS | bash"; fi

# ---- opencode ------------------------------------------------------------------------------
if have opencode; then
  v="$(ver opencode --version)"; a="ready (free opencode/* models; add providers with 'opencode auth login')"
  [ -n "${ZHIPU_API_KEY:-}" ] && a="ready (+ zai-coding-plan via ZHIPU_API_KEY)"
  [ -s "$HOME/.local/share/opencode/auth.json" ] && grep -q '"' "$HOME/.local/share/opencode/auth.json" 2>/dev/null && a="ready (providers in auth.json + free models)"
  add opencode opencode yes "$v" "$a" "opencode/big-pickle (free default), opencode/*-free, zai-coding-plan/glm-5.3, anthropic/*, openai/*" "headless: opencode run --dir --auto -m provider/model"
else add opencode opencode no "" "" "" "curl -fsSL https://opencode.ai/install | bash"; fi

# ---- pi ------------------------------------------------------------------------------------
if have pi; then
  v="$(ver pi --version)"; a="unknown"
  [ -n "${ZAI_API_KEY:-}" ] && a="ready for zai (ZAI_API_KEY)"
  [ -f "$HOME/.pi/agent/auth.json" ] && a="probably (auth.json exists)"
  add pi pi yes "$v" "$a" "provider/model[:thinking], e.g. zai/glm-5.3:high" "headless: pi -p --no-session; NO permission prompts at all"
else add pi pi no "" "" "" "npm i -g --ignore-scripts @earendil-works/pi-coding-agent"; fi

# ---- provider keys present (for routing custom providers) ---------------------------------
KEYS=""
for k in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY XAI_API_KEY CURSOR_API_KEY ZAI_API_KEY ZHIPU_API_KEY OPENROUTER_API_KEY; do
  [ -n "${!k:-}" ] && KEYS="$KEYS $k"
done

# ---- config discovery -----------------------------------------------------------------------
CFGS=""
for c in "${ORCHESTRATE_CONFIG:-}" "$CWD/.agents/orchestrate.yaml" "$CWD/.orchestrate.yaml" "$HOME/.agents/orchestrate.yaml" "$HOME/.config/orchestrate/config.yaml"; do
  [ -n "$c" ] && [ -f "$c" ] && CFGS="$CFGS $c"
done
# also walk up from cwd to git root for a project config
ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$ROOT" ] && [ "$ROOT" != "$CWD" ]; then
  for c in "$ROOT/.agents/orchestrate.yaml" "$ROOT/.orchestrate.yaml"; do [ -f "$c" ] && CFGS="$CFGS $c"; done
fi

# ---- output ---------------------------------------------------------------------------------
if [ "$FORMAT" = json ] && command -v jq >/dev/null 2>&1; then
  {
    printf '{"agents":['
    first=1
    for r in "${ROWS[@]}"; do
      IFS="$D" read -r n b i v a m x <<<"$r"
      [ $first = 1 ] || printf ','; first=0
      jq -cn --arg n "$n" --arg b "$b" --arg i "$i" --arg v "$v" --arg a "$a" --arg m "$m" --arg x "$x" \
        '{name:$n,binary:$b,installed:($i=="yes"),version:$v,auth:$a,models:$m,notes:$x}'
    done
    printf '],"provider_keys":%s,"config_files":%s,"cwd":%s}\n' \
      "$(printf '%s\n' "$KEYS" | jq -Rc 'split(" ")|map(select(length>0))')" \
      "$(printf '%s\n' "$CFGS" | jq -Rc 'split(" ")|map(select(length>0))')" \
      "$(printf '%s\n' "$CWD" | jq -Rc .)"
  }
else
  printf '%-9s %-13s %-4s %-14s %-45s %s\n' AGENT BINARY INST VERSION AUTH MODELS
  for r in "${ROWS[@]}"; do
    IFS="$D" read -r n b i v a m x <<<"$r"
    printf '%-9s %-13s %-4s %-14s %-45s %s\n' "$n" "$b" "$i" "${v:0:14}" "${a:0:45}" "$m"
  done
  echo
  echo "provider keys in env:${KEYS:- (none)}"
  echo "orchestrate config files:${CFGS:- (none found — see assets/orchestrate.example.yaml)}"
  echo
  echo "notes:"; for r in "${ROWS[@]}"; do IFS="$D" read -r n b i v a m x <<<"$r"; [ -n "$x" ] && echo "  $n: $x"; done
fi
