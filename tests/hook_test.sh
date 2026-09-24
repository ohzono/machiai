#!/bin/bash
# Shell tests for hooks/. No network: the translator is faked with MACHIAI_TRANSLATE_CMD.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/machiai-hook.sh"
INSTALL="$ROOT/hooks/install.sh"
JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ=jq

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ng()   { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check() { if eval "$2"; then ok "$1"; else ng "$1" "$2"; fi; }

new_home() {
  H="$(mktemp -d)"
  mkdir -p "$H/inbox"
  touch "$H/enabled"
  export MACHIAI_HOME="$H"
}

payload() { "$JQ" -nc --arg p "$1" '{session_id:"s-1", cwd:"/tmp/proj", hook_event_name:"UserPromptSubmit", prompt:$p}'; }

run_hook() { payload "$1" | "$HOOK"; }

entries() { find "$MACHIAI_HOME/inbox" -maxdepth 1 -name '*.json' | sort; }
count() { entries | grep -c . || true; }

# wait_status <status> <seconds>
wait_status() {
  local i=0 f
  while [ "$i" -lt $(( $2 * 10 )) ]; do
    f="$(entries | head -1)"
    if [ -n "$f" ] && [ "$("$JQ" -r .status "$f")" = "$1" ]; then return 0; fi
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }

echo "hook: capture"

new_home
export MACHIAI_TRANSLATE_CMD='sleep 10; echo "translated"'
t0=$(now_ms); out="$(run_hook 'ビルドが遅い原因を調べて')"; rc=$?; t1=$(now_ms)
check "does not wait for the 10s translator ($((t1 - t0)) ms)" "[ $((t1 - t0)) -lt 3000 ]"
check "exit 0" "[ $rc -eq 0 ]"
check "prints nothing to stdout" "[ -z \"\$out\" ]"
check "writes one pending entry immediately" "[ \"\$(count)\" = 1 ] && [ \"\$(\$JQ -r .status \"\$(entries)\")\" = pending ]"
f="$(entries)"
check "pending entry has contract fields" "\$JQ -e '.version == 1 and (.id|length) > 0 and .agent == \"claude-code\" and .source_text == \"ビルドが遅い原因を調べて\" and .session_id == \"s-1\" and .cwd == \"/tmp/proj\" and .translation == null and (.created_at|test(\"Z$\"))' \"$f\" >/dev/null"
check "file name matches id" "[ \"\$(basename \"$f\" .json)\" = \"\$(\$JQ -r .id \"$f\")\" ]"
check "becomes done with translation" "wait_status done 20"
check "done entry keeps id and created_at" "\$JQ -e '.translation == \"translated\" and .error == null' \"\$(entries)\" >/dev/null"
check "no temp files left" "[ -z \"\$(find \"\$MACHIAI_HOME/inbox\" -name '.*')\" ]"

echo "hook: failure"
new_home
export MACHIAI_TRANSLATE_CMD='echo "boom" >&2; exit 3'
run_hook 'テスト'
check "becomes failed" "wait_status failed 5"
check "failed entry has error" "\$JQ -e '.error | contains(\"boom\")' \"\$(entries)\" >/dev/null"

new_home
export MACHIAI_TRANSLATE_CMD='printf "  \n"'
run_hook 'テスト'
check "blank translator output is a failure" "wait_status failed 5"

echo "hook: late results"
new_home
export MACHIAI_TRANSLATE_CMD='sleep 2; echo late'
run_hook 'テスト'
rm -f "$(entries)"
sleep 3
check "deleted entry is not recreated by a late translation" "[ \"\$(count)\" = 0 ] && [ -z \"\$(find \"\$MACHIAI_HOME/inbox\" -name '.*')\" ]"

echo "hook: hostile prompt text"
new_home
export MACHIAI_TRANSLATE_CMD='cat'
hostile="$(printf '引用 "x" と '"'"'y'"'"' と $(touch %s/pwned) と `id` と $HOME\n改行も' "$MACHIAI_HOME")"
run_hook "$hostile"
check "hostile prompt is stored verbatim" "wait_status done 5 && [ \"\$(\$JQ -r .source_text \"\$(entries)\")\" = \"\$hostile\" ]"
check "hostile prompt is not executed" "[ ! -e \"\$MACHIAI_HOME/pwned\" ]"

echo "hook: skip rules"
export MACHIAI_TRANSLATE_CMD='echo x'
for p in '' '   ' '/clear' '  /model sonnet' '!ls' 'already english text' "$(printf 'あ%.0s' $(seq 1 1300))"; do
  new_home; run_hook "$p"
  check "skips: ${p:0:20}" "[ \"\$(count)\" = 0 ]"
done
new_home; echo 'not json' | "$HOOK"; rc=$?
check "invalid JSON input is ignored with exit 0" "[ $rc -eq 0 ] && [ \"\$(count)\" = 0 ]"

echo "hook: switches"
new_home; rm "$MACHIAI_HOME/enabled"; run_hook 'テスト'
check "disabled flag -> nothing written" "[ \"\$(count)\" = 0 ]"
new_home; payload 'テスト' | MACHIAI_CHILD=1 "$HOOK"
check "recursion guard -> nothing written" "[ \"\$(count)\" = 0 ]"
new_home; printf 'MACHIAI_MAX_CHARS=3\n' > "$MACHIAI_HOME/config.env"; run_hook 'テストです'
check "config.env MACHIAI_MAX_CHARS is honored" "[ \"\$(count)\" = 0 ]"

echo "install.sh"
new_home
S="$(mktemp -d)"
mkdir -p "$S/dotfiles"
printf '{\n  "model": "opus",\n  "hooks": {\n    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "other.sh"}]}]\n  }\n}\n' > "$S/dotfiles/settings.json"
ln -s "$S/dotfiles/settings.json" "$S/settings.json"
export CLAUDE_SETTINGS="$S/settings.json"
out="$("$INSTALL")"
check "reports install (not removal)" "echo \"\$out\" | grep -q 'Installed Machiai hook'"
check "keeps settings.json a symlink" "[ -L \"$S/settings.json\" ]"
check "adds exactly one machiai hook" "[ \"\$(\$JQ '[.hooks.UserPromptSubmit[].hooks[] | select(.command|contains(\"machiai-hook.sh\"))] | length' \"$S/settings.json\")\" = 1 ]"
check "keeps other hooks and keys" "\$JQ -e '.model == \"opus\" and ([.hooks.UserPromptSubmit[].hooks[].command] | index(\"other.sh\") != null)' \"$S/settings.json\" >/dev/null"
check "copies executable hooks" "[ -x \"\$MACHIAI_HOME/hooks/machiai-hook.sh\" ] && [ -x \"\$MACHIAI_HOME/hooks/translate.sh\" ]"
check "creates enabled flag" "[ -f \"\$MACHIAI_HOME/enabled\" ]"
check "writes a backup under MACHIAI_HOME" "ls \"\$MACHIAI_HOME\"/backups/settings.json.* >/dev/null 2>&1"
check "leaves nothing next to settings.json" "[ \"\$(ls \"$S/dotfiles\")\" = settings.json ]"
before="$(cat "$S/dotfiles/settings.json")"
out="$("$INSTALL")"
check "second install is a no-op" "[ \"\$before\" = \"\$(cat \"$S/dotfiles/settings.json\")\" ] && echo \"\$out\" | grep -q 'No change'"
"$INSTALL" --uninstall >/dev/null
check "uninstall removes only machiai" "\$JQ -e '.model == \"opus\" and ([.hooks.UserPromptSubmit[].hooks[].command] == [\"other.sh\"])' \"$S/settings.json\" >/dev/null"

chmod 600 "$S/dotfiles/settings.json"
"$INSTALL" >/dev/null
check "keeps the settings file mode" "[ \"\$(stat -f %Lp \"$S/dotfiles/settings.json\")\" = 600 ]"
"$INSTALL" --uninstall >/dev/null

L="$(mktemp -d)"; ln -s "$L/b.json" "$L/a.json"; ln -s "$L/a.json" "$L/b.json"
CLAUDE_SETTINGS="$L/a.json" "$INSTALL" >/dev/null 2>&1; rc=$?
check "symlink loop fails instead of hanging" "[ $rc -ne 0 ]"

S2="$(mktemp -d)"; export CLAUDE_SETTINGS="$S2/settings.json"
"$INSTALL" >/dev/null; "$INSTALL" --uninstall >/dev/null
check "install+uninstall on a fresh file leaves {}" "[ \"\$(\$JQ -c . \"$S2/settings.json\")\" = '{}' ]"
check "--print outputs the snippet" "\"$INSTALL\" --print | \$JQ -e '.hooks.UserPromptSubmit[0].hooks[0].type == \"command\"' >/dev/null"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
