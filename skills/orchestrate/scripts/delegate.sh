#!/usr/bin/env bash
# delegate.sh — uniform, headless, one-shot dispatch to a local coding-agent CLI.
#
# The orchestrating agent decides *what* to delegate and *to whom*; this script
# only makes the hand-off mechanical and uniform: it writes the brief to disk,
# runs the chosen CLI non-interactively with sane autonomous flags, captures the
# final message, and prints one JSON object describing the run.
#
# Usage:
#   delegate.sh --cli <codex|claude|gemini|agy|grok|cursor|opencode|pi|custom> \
#               (--brief <file> | --prompt "<text>") [options]
#
# Options:
#   --cwd <dir>          Working directory for the delegate (default: $PWD)
#   --model <id>         Model id, in the CLI's own naming (e.g. gpt-5.6-codex, opus, zai-coding-plan/glm-5.3)
#   --effort <level>     low|medium|high|xhigh|max — mapped per CLI, ignored where unsupported
#   --mode <write|read>  write (default): autonomous edits+commands. read: read-only/plan where the CLI supports it
#   --env K=V            Extra env for the child process (repeatable). Use for provider routing, e.g. z.ai.
#   --label <name>       Run label (default: <cli>-<UTC timestamp>); used for run dir and worktree branch
#   --timeout <secs>     Kill the delegate after N seconds (default: 1800)
#   --max-turns <n>      Turn cap where the CLI supports it (claude, grok)
#   --worktree           Run inside a fresh git worktree on branch orchestrate/<label> (isolates parallel work)
#   --command "<cmd>"    With --cli custom: shell command to run. Gets $ORCH_BRIEF (path), $ORCH_PROMPT (text),
#                        $ORCH_MODEL, $ORCH_EFFORT, $ORCH_MODE, $ORCH_CWD in its environment. Its stdout is the result.
#   --runs-dir <dir>     Where run artifacts go (default: $ORCHESTRATE_RUNS_DIR or ~/.agents/orchestrate/runs)
#   --dry-run            Print the resolved command and exit
#   -h, --help
#
# Output (stdout): one JSON object:
#   { label, cli, model, mode, cwd, worktree, branch, status: ok|error|timeout, exit_code,
#     duration_s, run_dir, brief_file, result_file, stdout_file, stderr_file, changed_files: [...] }
# The delegate's final message is in result_file (result.md). Everything else is in run_dir.
#
# Exit code: 0 if the delegate exited 0, otherwise the delegate's exit code (124 on timeout).

set -uo pipefail

CLI="" BRIEF="" PROMPT="" CWD="$PWD" MODEL="" EFFORT="" MODE="write" LABEL="" TIMEOUT=1800
MAX_TURNS="" WORKTREE=0 CUSTOM_CMD="" DRY_RUN=0
RUNS_DIR="${ORCHESTRATE_RUNS_DIR:-$HOME/.agents/orchestrate/runs}"
ENV_KV=()

die() { echo "delegate.sh: $*" >&2; exit 2; }
usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --cli) CLI="$2"; shift 2;;
    --brief) BRIEF="$2"; shift 2;;
    --prompt) PROMPT="$2"; shift 2;;
    --cwd) CWD="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --effort) EFFORT="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --env) ENV_KV+=("$2"); shift 2;;
    --label) LABEL="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --max-turns) MAX_TURNS="$2"; shift 2;;
    --worktree) WORKTREE=1; shift;;
    --command) CUSTOM_CMD="$2"; shift 2;;
    --runs-dir) RUNS_DIR="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage;;
    *) die "unknown option: $1 (see --help)";;
  esac
done

[ -n "$CLI" ] || die "--cli is required (codex|claude|gemini|agy|grok|cursor|opencode|pi|custom)"
case "$MODE" in write|read) ;; *) die "--mode must be write or read";; esac
if [ -z "$BRIEF" ] && [ -z "$PROMPT" ]; then die "one of --brief <file> or --prompt <text> is required"; fi
if [ -n "$BRIEF" ] && [ ! -f "$BRIEF" ]; then die "brief file not found: $BRIEF"; fi
[ -d "$CWD" ] || die "cwd not found: $CWD"
CWD="$(cd "$CWD" && pwd -P)"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
[ -n "$LABEL" ] || LABEL="${CLI}-${TS}"
LABEL="$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._-' '-')"
RUN_DIR="$RUNS_DIR/${TS}-${LABEL}"
mkdir -p "$RUN_DIR" || die "cannot create run dir $RUN_DIR"

BRIEF_FILE="$RUN_DIR/brief.md"
if [ -n "$BRIEF" ]; then cp "$BRIEF" "$BRIEF_FILE"; else printf '%s\n' "$PROMPT" > "$BRIEF_FILE"; fi
PROMPT_TEXT="$(cat "$BRIEF_FILE")"
RESULT_FILE="$RUN_DIR/result.md"; STDOUT_FILE="$RUN_DIR/stdout.log"; STDERR_FILE="$RUN_DIR/stderr.log"; RAW_JSON="$RUN_DIR/raw.json"

# ---- optional git worktree isolation -------------------------------------------------
BRANCH=""; WT_PATH=""
if [ "$WORKTREE" = 1 ]; then
  ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || die "--worktree requires cwd inside a git repo"
  BRANCH="orchestrate/$LABEL"
  WT_PATH="$RUNS_DIR/worktrees/$(basename "$ROOT")-$LABEL"
  mkdir -p "$(dirname "$WT_PATH")"
  if [ "$DRY_RUN" = 0 ]; then
    git -C "$ROOT" worktree add -q -b "$BRANCH" "$WT_PATH" HEAD >>"$STDERR_FILE" 2>&1 || die "git worktree add failed (see $STDERR_FILE)"
  fi
  CWD="$WT_PATH"
fi

# ---- helpers --------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
git_snapshot() { git -C "$CWD" status --porcelain --untracked-files=all 2>/dev/null | sort || true; }

# Effort mapping: caller passes low|medium|high|xhigh|max; clamp per CLI.
clamp_effort() { # $1=cli
  case "$1" in
    codex)  case "$EFFORT" in max) echo xhigh;; *) echo "$EFFORT";; esac;;
    agy)    case "$EFFORT" in xhigh|max) echo high;; *) echo "$EFFORT";; esac;;
    *)      echo "$EFFORT";;
  esac
}

CMD=()          # argv of the delegate
STDIN_SRC="/dev/null"   # what to feed on stdin
EXTRACT=""      # how to turn stdout into result.md: text|jq:<filter>|jsonl-last-text
declare -a CHILD_ENV=()

case "$CLI" in
  codex)
    have codex || die "codex not installed (npm i -g @openai/codex)"
    SANDBOX="workspace-write"; [ "$MODE" = read ] && SANDBOX="read-only"
    CMD=(codex exec -C "$CWD" -s "$SANDBOX" --skip-git-repo-check --color never -o "$RESULT_FILE")
    [ -n "$MODEL" ] && CMD+=(-m "$MODEL")
    [ -n "$EFFORT" ] && CMD+=(-c "model_reasoning_effort=\"$(clamp_effort codex)\"")
    CMD+=(-)                       # read prompt from stdin
    STDIN_SRC="$BRIEF_FILE"; EXTRACT="file";;
  claude)
    have claude || die "claude not installed (https://code.claude.com)"
    CMD=(claude -p --output-format json --no-session-persistence)
    [ -n "$MODEL" ] && CMD+=(--model "$MODEL")
    [ -n "$EFFORT" ] && CMD+=(--effort "$EFFORT")
    [ -n "$MAX_TURNS" ] && CMD+=(--max-turns "$MAX_TURNS")
    if [ "$MODE" = write ]; then CMD+=(--permission-mode bypassPermissions)
    else CMD+=(--permission-mode default --allowedTools "Read Glob Grep WebFetch WebSearch Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*)"); fi
    STDIN_SRC="$BRIEF_FILE"; EXTRACT="jq:.result";;
  gemini)
    have gemini || die "gemini not installed (npm i -g @google/gemini-cli); note: needs GEMINI_API_KEY (Google-account auth moved to Antigravity CLI 'agy')"
    APPROVAL="yolo"; [ "$MODE" = read ] && APPROVAL="plan"
    CMD=(gemini -p "$PROMPT_TEXT" --approval-mode "$APPROVAL" --output-format json)
    [ -n "$MODEL" ] && CMD+=(-m "$MODEL")
    EXTRACT="jq:.response";;
  agy)
    have agy || die "agy (Antigravity CLI) not installed: curl -fsSL https://antigravity.google/cli/install.sh | bash"
    CMD=(agy -p "$PROMPT_TEXT" --output-format json --print-timeout "${TIMEOUT}s")
    if [ "$MODE" = write ]; then CMD+=(--dangerously-skip-permissions); else CMD+=(--mode plan); fi
    [ -n "$MODEL" ] && CMD+=(--model "$MODEL")
    [ -n "$EFFORT" ] && CMD+=(--effort "$(clamp_effort agy)")
    EXTRACT="jq:.response";;
  grok)
    have grok || die "grok not installed: curl -fsSL https://x.ai/cli/install.sh | bash"
    PERM="bypassPermissions"; [ "$MODE" = read ] && PERM="plan"
    CMD=(grok --prompt-file "$BRIEF_FILE" --cwd "$CWD" --permission-mode "$PERM" --output-format json)
    [ -n "$MODEL" ] && CMD+=(-m "$MODEL")
    [ -n "$EFFORT" ] && CMD+=(--reasoning-effort "$EFFORT")
    [ -n "$MAX_TURNS" ] && CMD+=(--max-turns "$MAX_TURNS")
    EXTRACT="jq:.text";;
  cursor)
    BIN=""; if have agent && agent --help 2>/dev/null | grep -qi cursor; then BIN=agent; elif have cursor-agent; then BIN=cursor-agent; fi
    [ -n "$BIN" ] || die "Cursor CLI not installed: curl https://cursor.com/install -fsS | bash"
    CMD=("$BIN" -p "$PROMPT_TEXT" --output-format json)
    [ "$MODE" = write ] && CMD+=(--force)
    [ -n "$MODEL" ] && CMD+=(--model "$MODEL")
    EXTRACT="jq:.result";;
  opencode)
    have opencode || die "opencode not installed: curl -fsSL https://opencode.ai/install | bash"
    CMD=(opencode run --dir "$CWD" --auto)
    [ "$MODE" = read ] && CMD+=(--agent plan)
    [ -n "$MODEL" ] && CMD+=(-m "$MODEL")
    [ -n "$EFFORT" ] && CMD+=(--variant "$EFFORT")
    CMD+=("$PROMPT_TEXT")
    EXTRACT="text";;
  pi)
    have pi || die "pi not installed: npm i -g --ignore-scripts @earendil-works/pi-coding-agent"
    CMD=(pi -p --no-session)
    [ -n "$MODEL" ] && CMD+=(--model "$MODEL")
    [ -n "$EFFORT" ] && CMD+=(--thinking "$EFFORT")
    [ "$MODE" = read ] && CMD+=(--tools read,grep,find,ls)
    CMD+=("$PROMPT_TEXT")
    EXTRACT="text";;
  custom)
    [ -n "$CUSTOM_CMD" ] || die "--cli custom requires --command"
    CMD=(bash -c "$CUSTOM_CMD")
    CHILD_ENV+=("ORCH_BRIEF=$BRIEF_FILE" "ORCH_PROMPT=$PROMPT_TEXT" "ORCH_MODEL=$MODEL" "ORCH_EFFORT=$EFFORT" "ORCH_MODE=$MODE" "ORCH_CWD=$CWD")
    EXTRACT="text";;
  *) die "unknown --cli '$CLI' (codex|claude|gemini|agy|grok|cursor|opencode|pi|custom)";;
esac

for kv in "${ENV_KV[@]+"${ENV_KV[@]}"}"; do CHILD_ENV+=("$kv"); done

if [ "$DRY_RUN" = 1 ]; then
  printf 'cwd: %s\nenv: %s\nstdin: %s\ncmd:' "$CWD" "${CHILD_ENV[*]:-}" "$STDIN_SRC"
  printf ' %q' "${CMD[@]}"; printf '\n'; exit 0
fi

# ---- run --------------------------------------------------------------------------------
BEFORE="$(git_snapshot)"
START=$(date +%s)
# -u CLAUDECODE: allow `claude` to run nested inside a Claude Code session; harmless for other CLIs.
( cd "$CWD" && exec env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT "${CHILD_ENV[@]+"${CHILD_ENV[@]}"}" "${CMD[@]}" <"$STDIN_SRC" >"$STDOUT_FILE" 2>"$STDERR_FILE" ) &
PID=$!
( sleep "$TIMEOUT"; kill -TERM "$PID" 2>/dev/null; sleep 10; kill -KILL "$PID" 2>/dev/null ) 2>/dev/null &
WD=$!
wait "$PID"; RC=$?
kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null
END=$(date +%s); DUR=$((END-START))

STATUS="ok"
if [ "$RC" -ne 0 ]; then STATUS="error"; fi
if { [ "$RC" -eq 143 ] || [ "$RC" -eq 137 ]; } && [ "$DUR" -ge "$TIMEOUT" ]; then STATUS="timeout"; RC=124; fi

# ---- extract result --------------------------------------------------------------------
case "$EXTRACT" in
  file) [ -s "$RESULT_FILE" ] || cp "$STDOUT_FILE" "$RESULT_FILE";;
  jq:*)
    F="${EXTRACT#jq:}"
    if have jq && jq -e . "$STDOUT_FILE" >/dev/null 2>&1; then
      cp "$STDOUT_FILE" "$RAW_JSON"; jq -r "$F // empty" "$STDOUT_FILE" > "$RESULT_FILE"
    elif have jq && tail -n 1 "$STDOUT_FILE" | jq -e . >/dev/null 2>&1; then
      tail -n 1 "$STDOUT_FILE" > "$RAW_JSON"; jq -r "$F // empty" "$RAW_JSON" > "$RESULT_FILE"
    else
      cp "$STDOUT_FILE" "$RESULT_FILE"   # not JSON (auth error etc.) — keep raw
    fi
    [ -s "$RESULT_FILE" ] || cp "$STDOUT_FILE" "$RESULT_FILE";;
  text|*) cp "$STDOUT_FILE" "$RESULT_FILE";;
esac
# If the run failed and result is empty, surface stderr so the caller sees why.
if [ ! -s "$RESULT_FILE" ] && [ -s "$STDERR_FILE" ]; then cp "$STDERR_FILE" "$RESULT_FILE"; fi

AFTER="$(git_snapshot)"
CHANGED="$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed 's/^...//' | grep -v '^$' || true)"

# ---- emit JSON -------------------------------------------------------------------------
if have jq; then
  jq -n --arg label "$LABEL" --arg cli "$CLI" --arg model "$MODEL" --arg mode "$MODE" --arg cwd "$CWD" \
        --arg worktree "$WT_PATH" --arg branch "$BRANCH" --arg status "$STATUS" --argjson rc "$RC" --argjson dur "$DUR" \
        --arg run_dir "$RUN_DIR" --arg brief "$BRIEF_FILE" --arg result "$RESULT_FILE" --arg out "$STDOUT_FILE" --arg err "$STDERR_FILE" \
        --arg changed "$CHANGED" \
     '{label:$label, cli:$cli, model:$model, mode:$mode, cwd:$cwd, worktree:$worktree, branch:$branch, status:$status,
       exit_code:$rc, duration_s:$dur, run_dir:$run_dir, brief_file:$brief, result_file:$result,
       stdout_file:$out, stderr_file:$err, changed_files:($changed|split("\n")|map(select(length>0)))}'
else
  printf '{"label":"%s","cli":"%s","model":"%s","mode":"%s","cwd":"%s","worktree":"%s","branch":"%s","status":"%s","exit_code":%s,"duration_s":%s,"run_dir":"%s","brief_file":"%s","result_file":"%s","stdout_file":"%s","stderr_file":"%s","changed_files":"%s"}\n' \
    "$LABEL" "$CLI" "$MODEL" "$MODE" "$CWD" "$WT_PATH" "$BRANCH" "$STATUS" "$RC" "$DUR" "$RUN_DIR" "$BRIEF_FILE" "$RESULT_FILE" "$STDOUT_FILE" "$STDERR_FILE" "$(printf '%s' "$CHANGED" | tr '\n' ' ')"
fi
exit "$RC"
