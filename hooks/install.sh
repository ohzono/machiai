#!/bin/bash
# Install / uninstall the Machiai capture hook for Claude Code. See docs/SPEC.md §4.5.
#
#   install.sh              copy hooks to $MACHIAI_HOME/hooks and register them in settings.json
#   install.sh --uninstall  remove Machiai's entry from settings.json
#   install.sh --print      print the settings snippet without changing anything
#
# CLAUDE_SETTINGS overrides the settings file (default ~/.claude/settings.json).

set -u

MACHIAI_HOME="${MACHIAI_HOME:-$HOME/Library/Application Support/Machiai}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$MACHIAI_HOME/hooks"
HOOK_CMD="\"$DEST_DIR/machiai-hook.sh\""

JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(command -v jq)" || { echo "jq is required" >&2; exit 1; }

mode="install"
case "${1:-}" in
  --uninstall) mode="uninstall" ;;
  --print) mode="print" ;;
  "") ;;
  *) echo "usage: $0 [--uninstall|--print]" >&2; exit 64 ;;
esac

snippet() {
  "$JQ" -n --arg cmd "$HOOK_CMD" \
    '{hooks: {UserPromptSubmit: [{hooks: [{type: "command", command: $cmd}]}]}}'
}

if [ "$mode" = "print" ]; then
  snippet
  exit 0
fi

# Resolve symlinks so dotfiles-managed settings are edited in place, not replaced by a file.
target="$SETTINGS"
while [ -L "$target" ]; do
  link="$(readlink "$target")"
  case "$link" in /*) target="$link" ;; *) target="$(dirname "$target")/$link" ;; esac
done

if [ -f "$target" ]; then
  "$JQ" empty "$target" 2>/dev/null || { echo "Refusing to edit: $target is not valid JSON" >&2; exit 1; }
  current="$(cat "$target")"
else
  current='{}'
fi

# Remove every UserPromptSubmit hook whose command mentions machiai-hook.sh; drop empty groups.
strip='
  if .hooks.UserPromptSubmit then
    .hooks.UserPromptSubmit |= (
      map(.hooks |= map(select((.command // "") | contains("machiai-hook.sh") | not)))
      | map(select((.hooks | length) > 0))
    )
    | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
    | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end'

if [ "$mode" = "install" ]; then
  mkdir -p "$DEST_DIR" "$MACHIAI_HOME/inbox"
  for f in machiai-hook.sh translate.sh; do
    cp "$SRC_DIR/$f" "$DEST_DIR/$f"
    chmod +x "$DEST_DIR/$f"
  done
  touch "$MACHIAI_HOME/enabled"
  already="$(printf '%s' "$current" | "$JQ" --arg cmd "$HOOK_CMD" \
    '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == $cmd)] | length')"
  if [ "$already" = "1" ]; then
    updated="$current"
  else
    updated="$(printf '%s' "$current" | "$JQ" --arg cmd "$HOOK_CMD" "$strip"'
      | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{hooks: [{type: "command", command: $cmd}]}])')"
  fi
else
  updated="$(printf '%s' "$current" | "$JQ" "$strip")"
fi

canon() { printf '%s' "$1" | "$JQ" -S -c .; }
if [ "$(canon "$updated")" = "$(canon "$current")" ]; then
  echo "No change: $target"
  exit 0
fi

mkdir -p "$(dirname "$target")"
if [ -f "$target" ]; then
  backup="$target.machiai-backup-$(date +%Y%m%d%H%M%S)"
  cp "$target" "$backup"
  echo "Backup: $backup"
fi
tmp="$target.machiai-tmp.$$"
printf '%s\n' "$updated" > "$tmp" && mv -f "$tmp" "$target"

if [ "$mode" = "install" ]; then
  echo "Installed Machiai hook into $target"
  echo "Capture is ON. New Claude Code sessions will send prompts to Machiai."
else
  echo "Removed Machiai hook from $target"
fi
