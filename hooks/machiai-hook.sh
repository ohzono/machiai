#!/bin/bash
# Machiai capture hook for Claude Code (UserPromptSubmit).
#
# Writes the prompt to the Machiai inbox as a `pending` entry, then translates it in a fully
# detached background job and rewrites the entry as `done` or `failed`.
#
# Contract: never block the agent, never print to stdout, always exit 0. See docs/SPEC.md §4.3.

set -u

[ -n "${MACHIAI_CHILD:-}" ] && exit 0

MACHIAI_HOME="${MACHIAI_HOME:-$HOME/Library/Application Support/Machiai}"
[ -f "$MACHIAI_HOME/enabled" ] || exit 0

if [ -f "$MACHIAI_HOME/config.env" ]; then
  # shellcheck disable=SC1091
  . "$MACHIAI_HOME/config.env" 2>/dev/null
fi
MACHIAI_MAX_CHARS="${MACHIAI_MAX_CHARS:-1200}"
MACHIAI_TARGET_LANG="${MACHIAI_TARGET_LANG:-English}"

JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ=jq

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INBOX="$MACHIAI_HOME/inbox"
LOG="$MACHIAI_HOME/hook.log"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG" 2>/dev/null; }

input="$(cat)"

# --- skip rules (docs/SPEC.md §4.3) -----------------------------------------------------------
# Empty, slash commands, shell passthrough, plain ASCII (already English), or too long.
verdict="$(printf '%s' "$input" | "$JQ" -r --argjson max "$MACHIAI_MAX_CHARS" '
  (.prompt // "") as $p
  | ($p | sub("^\\s+"; "")) as $t
  | if $t == "" then "skip"
    elif ($t | startswith("/")) or ($t | startswith("!")) then "skip"
    elif ($p | explode | any(. > 127) | not) then "skip"
    elif ($p | length) > $max then "skip"
    else "take" end' 2>/dev/null)"
[ "$verdict" = "take" ] || exit 0
prompt="$(printf '%s' "$input" | "$JQ" -r '.prompt')"

mkdir -p "$INBOX" 2>/dev/null || exit 0

id="$(uuidgen)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp="$INBOX/.$id.tmp"
dest="$INBOX/$id.json"

# write_entry <status> <translation-or-empty> <error-or-empty>
write_entry() {
  printf '%s' "$input" | "$JQ" \
    --arg id "$id" --arg status "$1" --arg created "$now" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg lang "$MACHIAI_TARGET_LANG" \
    --arg translation "$2" --arg error "$3" '{
      version: 1,
      id: $id,
      status: $status,
      agent: "claude-code",
      created_at: $created,
      updated_at: $updated,
      session_id: (.session_id // null),
      cwd: (.cwd // null),
      source_text: .prompt,
      target_lang: $lang,
      translation: (if $translation == "" then null else $translation end),
      error: (if $error == "" then null else $error end)
    }' > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest"
}

write_entry pending "" "" || { log "failed to write pending entry"; exit 0; }

# --- detached translation ----------------------------------------------------------------------
# stdin/stdout/stderr must all be detached, otherwise Claude Code waits for the job to finish.
(
  errfile="$INBOX/.$id.err"
  if translation="$(printf '%s' "$prompt" | MACHIAI_CHILD=1 "$HOOK_DIR/translate.sh" 2>"$errfile")" \
    && [ -n "$(printf '%s' "$translation" | tr -d '[:space:]')" ]; then
    write_entry done "$translation" ""
  else
    err="$(head -c 300 "$errfile" 2>/dev/null)"
    [ -z "$err" ] && err="Translator returned no output"
    log "translate failed for $id: $err"
    write_entry failed "" "$err"
  fi
  rm -f "$errfile"
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
