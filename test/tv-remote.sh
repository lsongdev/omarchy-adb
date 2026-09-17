#!/usr/bin/env bash
# Runs the shim against a fake adb (test/fake-adb) and checks what it prints
# and what it asks the device to do. The only half of the plugin that can be
# tested without a compositor and a TV, so it is.
#
#   ./test/tv-remote.sh          # exit 0 when every case passes
set -u
here=$(cd "$(dirname "$0")" && pwd)
shim="$here/../tv-remote"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

# run <name> [VAR=value ...] -- <shim args...>
# Runs the shim with the fake adb first on PATH and the given environment.
run() {
  name=$1; shift
  envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  FAKE_LOG="$tmp/$name.log"; rm -f "$FAKE_LOG" "$FAKE_LOG.state"
  out=$(env PATH="$here/fake-adb:$PATH" FAKE_LOG="$FAKE_LOG" "${envs[@]}" "$shim" "$@" 2>"$tmp/err")
  status=$?
}
# What the shim sent to the device shell, one command per line.
shelled() { grep -E '^-s [^ ]+ shell ' "$FAKE_LOG" 2>/dev/null | sed -E 's/^-s [^ ]+ shell //' || true; }

check() {  # check <what> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass+1))
  else fail=$((fail+1)); printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$2" "$3"; fi
}

TV=1.2.3.4:5555
on="TV_ADB_ADDR=$TV FAKE_TV=$TV"

# ---- status --------------------------------------------------------------
# A PATH with bash on it and nothing else, so the shim runs but finds no adb.
mkdir -p "$tmp/nobin" && ln -s "$(command -v bash)" "$tmp/nobin/bash"
run "noadb" PATH="$tmp/nobin" -- status
check "status with no adb" "noadb" "$out"

run "no-addr" FAKE_TV= FAKE_STATE= -- status
check "status with no address and no device" "down" "$out"

run "up" $on FAKE_STATE=device -- status;          check "status: device" "up" "$out"
run "unauth" $on FAKE_STATE=unauthorized -- status; check "status: unauthorized" "unauth" "$out"
run "offline" $on FAKE_STATE=offline -- status;    check "status: offline" "down" "$out"
run "absent" $on FAKE_STATE= -- status;            check "status: not listed" "down" "$out"

run "other-serial" TV_ADB_ADDR=$TV FAKE_TV=9.9.9.9:5555 FAKE_STATE=device -- status
check "status: only another serial is up" "down" "$out"

# An address is full of dots; a regex match would let 1x2x3x4 pass for 1.2.3.4.
run "dots" TV_ADB_ADDR=$TV FAKE_TV=1x2x3x4:5555 FAKE_STATE=device -- status
check "status: dots are not wildcards" "down" "$out"

run "reconnect" $on FAKE_STATE= FAKE_CONNECT=device -- status
check "status: reconnects a dropped TV" "up" "$out"
check "status: reconnect called connect" "1" "$(grep -c "^connect $TV" "$FAKE_LOG")"

# ---- reauth ----------------------------------------------------------------
run "reauth-up" $on FAKE_STATE=device -- reauth;          check "reauth: accepted" "up" "$out"
run "reauth-unauth" $on FAKE_STATE=unauthorized -- reauth; check "reauth: still waiting" "unauth" "$out"
run "reauth-absent" $on FAKE_STATE= -- reauth;             check "reauth: gone" "down" "$out"
check "reauth: bounced the server" "kill-server
start-server" "$(grep -E '^(kill|start)-server' "$FAKE_LOG")"

# ---- what reaches the device -----------------------------------------------
run "key" $on FAKE_STATE=device -- key KEYCODE_HOME
check "key" "input keyevent KEYCODE_HOME" "$(shelled)"

run "app" $on FAKE_STATE=device -- app com.netflix.ninja
check "app" "monkey -p com.netflix.ninja -c android.intent.category.LEANBACK_LAUNCHER 1" "$(shelled)"

run "text" $on FAKE_STATE=device -- text "it's 100%" enter
check "text: quoted for the device shell, then ENTER in the same process" \
  "input text 'it'\\''s 100%'
input keyevent KEYCODE_ENTER" "$(shelled)"

run "text-empty" $on FAKE_STATE=device -- text ""
check "text: nothing to send" "" "$(shelled)"

run "clear3" $on FAKE_STATE=device -- clear 3
check "clear: jumps to the end first, one round trip" \
  "input keyevent KEYCODE_MOVE_END KEYCODE_DEL KEYCODE_DEL KEYCODE_DEL" "$(shelled)"

run "clear-default" $on FAKE_STATE=device -- clear
check "clear: default count" "24" "$(shelled | grep -o KEYCODE_DEL | wc -l)"

run "clear-cap" $on FAKE_STATE=device -- clear 999
check "clear: capped" "200" "$(shelled | grep -o KEYCODE_DEL | wc -l)"

run "clear-junk" $on FAKE_STATE=device -- clear abc
check "clear: junk count falls back" "24" "$(shelled | grep -o KEYCODE_DEL | wc -l)"

run "inputs" $on FAKE_STATE=device -- inputs
check "inputs: keycode then the picker intent" \
  "input keyevent KEYCODE_TV_INPUT
am start -a android.media.tv.action.SETUP_INPUTS" "$(shelled)"

shot="$tmp/screen.png"
run "screenshot" $on FAKE_STATE=device -- screenshot "$shot"
check "screenshot: adb command" "-s $TV exec-out screencap -p" "$(grep 'exec-out screencap' "$FAKE_LOG")"
check "screenshot: PNG saved" "89504e470d0a1a0a" "$(od -An -tx1 -N8 "$shot" | tr -d ' \n')"

# ---- failure paths ---------------------------------------------------------
run "unreachable" $on FAKE_STATE= -- key KEYCODE_HOME
check "action on a dead TV exits 1" "1" "$status"
check "action on a dead TV sends nothing" "" "$(shelled)"

run "usage" $on FAKE_STATE=device -- bogus
check "unknown verb exits 2" "2" "$status"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
