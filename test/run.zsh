#!/usr/bin/env zsh
# ---------------------------------------------------------------------------
# claude-usage test harness — hermetic, no network.
#
# Every test pre-seeds a fresh cache file for a throwaway account dir, so the
# warm path serves it directly (a cache newer than the TTL never triggers a
# background refresh, so the OAuth/curl code is never reached). Run: zsh test/run.zsh
# ---------------------------------------------------------------------------
emulate -L zsh
setopt pipe_fail

here=${0:a:h}
root=${here:h}
source "$root/claude-usage.zsh"

tmp=$(mktemp -d)
export TMPDIR="$tmp/"
# Neutralise ambient config that would skew assertions.
unset NO_COLOR CLAUDE_USAGE_COLORS CLAUDE_USAGE_THRESHOLDS \
      CLAUDE_USAGE_BAR_CHARS CLAUDE_USAGE_BRACKETS CLAUDE_USAGE_DIM \
      CLAUDE_USAGE_THEME CLAUDE_USAGE_SEP 2>/dev/null

esc=$'\e'
integer pass=0 fail=0

# seed <name> <json> → prints the account dir on stdout; writes its cache.
seed() {
  local name=$1
  local json=$2
  local d="$tmp/$name"
  mkdir -p "$d"
  print -r -- "$json" > "$TMPDIR/claude-oauth-usage.$name.json"
  print -r -- "$d"
}
ok()  { (( pass++ )); print "ok   - $1"; }
bad() { (( fail++ )); print "FAIL - $1"; print "       got: ${(qqq)2}"; [[ -n ${3:-} ]] && print "       want: ${(qqq)3}"; }
eq()     { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "$2" "$3"; }
has()    { [[ "$2" == *"$3"* ]] && ok "$1" || bad "$1" "$2" "contains: ${(qqq)3}"; }
hasnot() { [[ "$2" != *"$3"* ]] && ok "$1" || bad "$1" "$2" "must NOT contain: ${(qqq)3}"; }

RL='{"limits":[
  {"kind":"weekly_all","percent":20,"severity":"normal"},
  {"kind":"weekly_scoped","percent":27,"severity":"normal","scope":{"model":{"display_name":"Opus"}}},
  {"kind":"session","percent":49,"severity":"normal"}]}'
USD='{"spend":{"enabled":true,"used":{"amount_minor":14250,"exponent":2},
  "limit":{"amount_minor":30000,"exponent":2},"percent":47.5}}'

rl=$(seed ratelimit "$RL")
usd=$(seed usd "$USD")

# ---- text mode (deterministic with --show-reset=false) --------------------
eq "text rate-limit" \
  "$(claude-usage --dir $rl --text-only --show-reset=false)" \
  "7d 20% | Opus 27% | 5h 49%"
eq "text custom sep" \
  "$(claude-usage --dir $rl --text-only --show-reset=false --sep ' / ')" \
  "7d 20% / Opus 27% / 5h 49%"
eq "text USD cap" \
  "$(claude-usage --dir $usd --text-only --show-reset=false)" \
  "\$142.5 / \$300 (48%)"

# ---- pretty: default theme ------------------------------------------------
p=$(claude-usage --dir $rl --show-reset=false)
has    "pretty green SGR"   "$p" "${esc}[32m"
has    "pretty 7d label"    "$p" "7d"
has    "pretty full block"  "$p" "█"
has    "pretty empty block" "$p" "░"

# ---- mono: no colour, bars kept, separators still faint -------------------
m=$(claude-usage --dir $rl --show-reset=false --theme mono)
hasnot "mono no green"   "$m" "${esc}[32m"
has    "mono keeps bars" "$m" "▕"
has    "mono faint sep"  "$m" "${esc}[2m"

# ---- --no-color: no SGR at all, bars kept ---------------------------------
n=$(claude-usage --dir $rl --show-reset=false --no-color)
hasnot "no-color has no ESC" "$n" "$esc"
has    "no-color keeps bars" "$n" "▕"

# ---- NO_COLOR env var (no-color.org) --------------------------------------
e=$(NO_COLOR=1 claude-usage --dir $rl --show-reset=false)
hasnot "NO_COLOR has no ESC" "$e" "$esc"
has    "NO_COLOR keeps bars" "$e" "▕"

# ---- ascii theme ----------------------------------------------------------
a=$(claude-usage --dir $rl --show-reset=false --theme ascii)
has    "ascii open bracket"  "$a" "["
has    "ascii fill glyph"    "$a" "#"
hasnot "ascii no block char" "$a" "█"

# ---- neon theme (256-colour) ----------------------------------------------
has "neon 256-colour" "$(claude-usage --dir $rl --show-reset=false --theme neon)" "${esc}[38;5;46m"

# ---- per-field overrides --------------------------------------------------
has "threshold override → red" \
  "$(CLAUDE_USAGE_THRESHOLDS='10:15' claude-usage --dir $rl --show-reset=false)" "${esc}[31m"
has "colour override" \
  "$(CLAUDE_USAGE_COLORS='34:35:36' claude-usage --dir $rl --show-reset=false)" "${esc}[34m"
oc=$(CLAUDE_USAGE_BAR_CHARS='=::-' claude-usage --dir $rl --show-reset=false)
has "bar-chars full glyph"  "$oc" "="
has "bar-chars empty glyph" "$oc" "-"
hasnot "bar-chars no block" "$oc" "█"
hasnot "brackets none" \
  "$(CLAUDE_USAGE_BRACKETS=':' claude-usage --dir $rl --show-reset=false)" "▕"

# ---- USD pretty -----------------------------------------------------------
u=$(claude-usage --dir $usd --show-reset=false)
has "USD amount"   "$u" "\$142.5/\$300"
has "USD bar"      "$u" "▕"

# ---- json -----------------------------------------------------------------
claude-usage --dir $usd --json | jq -e '.spend.enabled==true and .spend.limit==300 and (.spend.percent==47.5)' >/dev/null \
  && ok "json spend shape" || bad "json spend shape" "$(claude-usage --dir $usd --json)"
claude-usage --dir $rl --json | jq -e '(.limits|length)==3 and (.limits[0].label=="7d")' >/dev/null \
  && ok "json limits shape" || bad "json limits shape" "$(claude-usage --dir $rl --json)"

# ---- meta flags -----------------------------------------------------------
eq "version" "$(claude-usage --version)" "claude-usage $CLAUDE_USAGE_VERSION"
eq "list-themes" "$(claude-usage --list-themes)" "default mono ascii bright neon"

claude-usage --dir $rl --theme bogus >/dev/null 2>&1
(( $? == 1 )) && ok "unknown theme → rc 1" || bad "unknown theme → rc 1" "rc=$?"

claude-usage --bogus-flag >/dev/null 2>&1
(( $? == 1 )) && ok "unknown flag → rc 1" || bad "unknown flag → rc 1" "rc=$?"

# ---------------------------------------------------------------------------
rm -rf "$tmp"
print -- "\n${pass} passed, ${fail} failed"
(( fail == 0 ))
