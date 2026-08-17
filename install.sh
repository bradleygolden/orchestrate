#!/usr/bin/env bash
# install.sh — link (or copy) the `orchestrate` skill into every agent skill directory on this machine.
#
#   curl -fsSL https://raw.githubusercontent.com/bradleygolden/orchestrate/main/install.sh | bash
#   # or from a clone:  ./install.sh [--copy] [--uninstall]
#
# Where it goes:
#   ~/.agents/skills/orchestrate   — read by Codex, Grok, Cursor, OpenCode, pi, Amp, Copilot, Gemini/agy
#   ~/.claude/skills/orchestrate   — Claude Code (does not read ~/.agents/skills)
# Also seeds ~/.agents/orchestrate.yaml from the example if you don't have one yet.
#
# Alternative installers: `npx skills add bradleygolden/orchestrate -g` (skills.sh) or, in Claude Code,
# `/plugin marketplace add bradleygolden/orchestrate` then `/plugin install orchestrate`.

set -euo pipefail
REPO_URL="https://github.com/bradleygolden/orchestrate"
MODE="link"; UNINSTALL=0
for a in "$@"; do case "$a" in --copy) MODE=copy;; --uninstall) UNINSTALL=1;; -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0;; esac; done

TARGETS=("$HOME/.agents/skills/orchestrate" "$HOME/.claude/skills/orchestrate")

if [ "$UNINSTALL" = 1 ]; then
  for t in "${TARGETS[@]}"; do [ -e "$t" ] || [ -L "$t" ] && { rm -rf "$t"; echo "removed $t"; }; done
  echo "config kept at ~/.agents/orchestrate.yaml (delete manually if you want)"; exit 0
fi

# Locate the skill source: from a clone (this script's dir) or by cloning to ~/.agents/orchestrate/src
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || true)"
if [ -n "$HERE" ] && [ -f "$HERE/skills/orchestrate/SKILL.md" ]; then
  SRC="$HERE/skills/orchestrate"
else
  CLONE="$HOME/.agents/orchestrate/src"
  if [ -d "$CLONE/.git" ]; then git -C "$CLONE" pull -q --ff-only || true; else mkdir -p "$(dirname "$CLONE")"; git clone -q "$REPO_URL" "$CLONE"; fi
  SRC="$CLONE/skills/orchestrate"
fi
[ -f "$SRC/SKILL.md" ] || { echo "cannot find skills/orchestrate/SKILL.md under $SRC" >&2; exit 1; }
chmod +x "$SRC"/scripts/*.sh

for t in "${TARGETS[@]}"; do
  mkdir -p "$(dirname "$t")"
  if [ -L "$t" ] || [ -e "$t" ]; then rm -rf "$t"; fi
  if [ "$MODE" = link ]; then ln -s "$SRC" "$t"; else cp -R "$SRC" "$t"; fi
  echo "installed → $t ($MODE)"
done

CFG="$HOME/.agents/orchestrate.yaml"
if [ ! -f "$CFG" ]; then cp "$SRC/assets/orchestrate.example.yaml" "$CFG"; echo "seeded $CFG — edit it to match your fleet"; else echo "config exists: $CFG"; fi

echo; echo "Fleet inventory:"; "$SRC/scripts/inventory.sh" || true
echo; echo "Done. In your agent, try: \"orchestrate: <task>\" or \"delegate this to codex\"."
