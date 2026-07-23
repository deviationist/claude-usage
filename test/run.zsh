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
      CLAUDE_USAGE_THEME CLAUDE_USAGE_SEP CLAUDE_USAGE_GROUP_SEP \
      CLAUDE_USAGE_SHOW_SPEND CLAUDE_USAGE_SHOW_BALANCE \
      CLAUDE_USAGE_SHOW_SPEND_RESET CLAUDE_USAGE_SHOW_LIMIT_RESETS \
      CLAUDE_USAGE_RESET_PREFIX CLAUDE_USAGE_SPEND_PREFIX \
      CLAUDE_USAGE_LIMITS_PREFIX 2>/dev/null
# Hermetic: never read a real ~/.config/claude-usage/config
export CLAUDE_USAGE_CONFIG="$tmp/no-such-config"

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
# Max + usage credits: plan limits AND a dollar cap coexist (combined view)
COMBO='{"spend":{"enabled":true,"used":{"amount_minor":0,"exponent":2},
  "limit":{"amount_minor":4000,"exponent":2},"percent":0,
  "balance":{"amount_minor":10000,"exponent":2}},
 "limits":[
  {"kind":"weekly_all","percent":20,"severity":"normal"},
  {"kind":"weekly_scoped","percent":27,"severity":"normal","scope":{"model":{"display_name":"Opus"}}},
  {"kind":"session","percent":49,"severity":"normal"}]}'
# Same, but the credits toggle is off → dollar segment must disappear
COMBO_OFF='{"spend":{"enabled":false,"used":{"amount_minor":0,"exponent":2},
  "limit":{"amount_minor":4000,"exponent":2},"percent":0},
 "limits":[
  {"kind":"weekly_all","percent":20,"severity":"normal"},
  {"kind":"session","percent":49,"severity":"normal"}]}'

rl=$(seed ratelimit "$RL")
usd=$(seed usd "$USD")
combo=$(seed combo "$COMBO")
combooff=$(seed combooff "$COMBO_OFF")

# ---- text mode (deterministic with --show-reset=false) --------------------
eq "text rate-limit" \
  "$(claude-usage --dir $rl --text-only --show-reset=false)" \
  "7d 20% | Opus 27% | 5h 49%"
eq "text custom sep" \
  "$(claude-usage --dir $rl --text-only --show-reset=false --sep ' / ')" \
  "7d 20% / Opus 27% / 5h 49%"
# Monthly spend-cap reset date (default on; derived: 1st of next month)
mnames=(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
nextmonth="${mnames[$(( 10#$(date +%m) % 12 + 1 ))]} 1"
eq "text USD cap" \
  "$(claude-usage --dir $usd --text-only --show-reset=false)" \
  "\$142.5 / \$300 (48%, $nextmonth)"
eq "text USD cap, spend-reset off" \
  "$(claude-usage --dir $usd --text-only --show-reset=false --show-spend-reset=false)" \
  "\$142.5 / \$300 (48%)"
eq "text combined (Max + credits)" \
  "$(claude-usage --dir $combo --text-only --show-reset=false)" \
  "\$0 / \$40 (0%, $nextmonth) | bal \$100 || 7d 20% | Opus 27% | 5h 49%"
eq "text combined, credits toggled off" \
  "$(claude-usage --dir $combooff --text-only --show-reset=false)" \
  "7d 20% | 5h 49%"
eq "text --show-spend=false" \
  "$(claude-usage --dir $combo --text-only --show-reset=false --show-spend=false)" \
  "bal \$100 || 7d 20% | Opus 27% | 5h 49%"
eq "text --show-balance=false" \
  "$(claude-usage --dir $combo --text-only --show-reset=false --show-balance=false)" \
  "\$0 / \$40 (0%, $nextmonth) || 7d 20% | Opus 27% | 5h 49%"
eq "text --show-spend-reset=false" \
  "$(claude-usage --dir $combo --text-only --show-reset=false --show-spend-reset=false --show-balance=false)" \
  "\$0 / \$40 (0%) || 7d 20% | Opus 27% | 5h 49%"
eq "text env toggles" \
  "$(CLAUDE_USAGE_SHOW_SPEND=false CLAUDE_USAGE_SHOW_BALANCE=false \
     claude-usage --dir $combo --text-only --show-reset=false)" \
  "7d 20% | Opus 27% | 5h 49%"
# A dollar-cap-only seat ignores --show-spend (the cap is the whole display)
eq "text USD seat ignores --show-spend" \
  "$(claude-usage --dir $usd --text-only --show-reset=false --show-spend=false)" \
  "\$142.5 / \$300 (48%, $nextmonth)"
eq "text custom group-sep" \
  "$(claude-usage --dir $combo --text-only --show-reset=false --group-sep ' >> ' --show-balance=false --show-spend-reset=false)" \
  "\$0 / \$40 (0%) >> 7d 20% | Opus 27% | 5h 49%"

# ---- per-window reset countdowns (7d/model from resets_at) ----------------
# Offsets carry ≥30s of margin so a slow runner can't flip the rendered value.
epoch_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null \
              || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S+00:00 }
now_epoch=$(date +%s)
wk_iso=$(epoch_iso $((now_epoch + 90090)))   # 1d1h1m30s → "1d1h"
ss_iso=$(epoch_iso $((now_epoch + 14730)))   # 4h5m30s   → "4h5m"
RLT='{"limits":[
  {"kind":"weekly_all","percent":20,"severity":"normal","resets_at":"'$wk_iso'"},
  {"kind":"session","percent":49,"severity":"normal","resets_at":"'$ss_iso'"}]}'
rlt=$(seed ratelimit-resets "$RLT")
eq "text limit resets (default)" \
  "$(claude-usage --dir $rlt --text-only)" \
  "7d 20% 1d1h | 5h 49% 4h5m"
eq "text --show-limit-resets=false" \
  "$(claude-usage --dir $rlt --text-only --show-limit-resets=false)" \
  "7d 20% | 5h 49% 4h5m"
has "pretty limit resets" "$(claude-usage --dir $rlt)" "1d1h"
# --reset-prefix labels every countdown in one style (default is none)
eq "text --reset-prefix" \
  "$(claude-usage --dir $rlt --text-only --reset-prefix 'Reset ')" \
  "7d 20% Reset 1d1h | 5h 49% Reset 4h5m"
eq "text reset-prefix via env" \
  "$(CLAUDE_USAGE_RESET_PREFIX='~' claude-usage --dir $rlt --text-only)" \
  "7d 20% ~1d1h | 5h 49% ~4h5m"
has "pretty --reset-prefix" \
  "$(claude-usage --dir $rlt --reset-prefix 'Reset ')" "Reset 4h5m"
# the prefix also labels the monthly spend-cap date, so all resets align
eq "text reset prefix on spend date" \
  "$(claude-usage --dir $combo --text-only --show-reset=false --show-balance=false \
       --reset-prefix 'Reset ')" \
  "\$0 / \$40 (0%, Reset $nextmonth) || 7d 20% | Opus 27% | 5h 49%"

# ---- section prefixes (--spend-prefix / --limits-prefix) ------------------
eq "text section prefixes" \
  "$(claude-usage --dir $combo --text-only --show-reset=false --show-spend-reset=false \
       --spend-prefix 'Spend: ' --limits-prefix 'Limits: ')" \
  "Spend: \$0 / \$40 (0%) | bal \$100 || Limits: 7d 20% | Opus 27% | 5h 49%"
eq "text limits prefix, Max-only seat" \
  "$(claude-usage --dir $rl --text-only --show-reset=false --limits-prefix 'Limits: ')" \
  "Limits: 7d 20% | Opus 27% | 5h 49%"
eq "text spend prefix, USD-only seat" \
  "$(claude-usage --dir $usd --text-only --show-reset=false --show-spend-reset=false \
       --spend-prefix 'Spend: ')" \
  "Spend: \$142.5 / \$300 (48%)"
eq "text section prefixes via env" \
  "$(CLAUDE_USAGE_SPEND_PREFIX='S ' CLAUDE_USAGE_LIMITS_PREFIX='L ' \
     claude-usage --dir $combo --text-only --show-reset=false --show-spend-reset=false \
       --show-balance=false)" \
  "S \$0 / \$40 (0%) || L 7d 20% | Opus 27% | 5h 49%"
sp=$(claude-usage --dir $combo --show-reset=false --spend-prefix 'Spend: ' --limits-prefix 'Limits: ')
has "pretty spend prefix"  "$sp" "Spend: "
has "pretty limits prefix" "$sp" "Limits: "

# ---- config file (CLAUDE_USAGE_CONFIG) ------------------------------------
cat > "$tmp/cfg" <<'EOF'
# comment line
CLAUDE_USAGE_RESET_PREFIX="Reset "
CLAUDE_USAGE_LIMITS_PREFIX='L: '
CLAUDE_USAGE_SHOW_LIMIT_RESETS=false
not_a_claude_key=ignored
EOF
eq "config file applies" \
  "$(CLAUDE_USAGE_CONFIG=$tmp/cfg claude-usage --dir $rlt --text-only)" \
  "L: 7d 20% | 5h 49% Reset 4h5m"
# config wins over process env; flags win over config
eq "config beats env" \
  "$(CLAUDE_USAGE_CONFIG=$tmp/cfg CLAUDE_USAGE_LIMITS_PREFIX='ENV: ' \
     claude-usage --dir $rlt --text-only)" \
  "L: 7d 20% | 5h 49% Reset 4h5m"
eq "flag beats config" \
  "$(CLAUDE_USAGE_CONFIG=$tmp/cfg claude-usage --dir $rlt --text-only --limits-prefix 'F: ')" \
  "F: 7d 20% | 5h 49% Reset 4h5m"
# config vars stay out of the calling shell (function-local only)
CLAUDE_USAGE_CONFIG=$tmp/cfg claude-usage --dir $rlt --text-only >/dev/null
[[ -z ${CLAUDE_USAGE_LIMITS_PREFIX+x} ]] && ok "config does not leak" \
  || bad "config does not leak" "CLAUDE_USAGE_LIMITS_PREFIX leaked: ${(qqq)CLAUDE_USAGE_LIMITS_PREFIX}"

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

# ---- combined pretty (Max + usage credits) --------------------------------
c=$(claude-usage --dir $combo --show-reset=false)
has    "combined dollar segment"  "$c" "\$0/\$40"
has    "combined balance segment" "$c" "bal \$100"
has    "combined spend-reset"     "$c" "$nextmonth"
has    "combined 7d bar"          "$c" "7d"
has    "combined 5h bar"          "$c" "5h"
hasnot "combined-off no dollars" \
  "$(claude-usage --dir $combooff --show-reset=false)" "\$0"
hasnot "pretty --show-balance=false" \
  "$(claude-usage --dir $combo --show-reset=false --show-balance=false)" "bal"
hasnot "pretty --show-spend-reset=false" \
  "$(claude-usage --dir $combo --show-reset=false --show-spend-reset=false)" "$nextmonth"

# ---- json -----------------------------------------------------------------
claude-usage --dir $usd --json | jq -e '.spend.enabled==true and .spend.limit==300 and (.spend.percent==47.5)' >/dev/null \
  && ok "json spend shape" || bad "json spend shape" "$(claude-usage --dir $usd --json)"
claude-usage --dir $rl --json | jq -e '(.limits|length)==3 and (.limits[0].label=="7d")' >/dev/null \
  && ok "json limits shape" || bad "json limits shape" "$(claude-usage --dir $rl --json)"
claude-usage --dir $combo --json | jq -e '.spend.limit==40 and .spend.balance==100 and .spend.enabled==true and (.limits|length)==3' >/dev/null \
  && ok "json combined shape" || bad "json combined shape" "$(claude-usage --dir $combo --json)"

# ---- README SVG generator (smoke; explicit output path → README untouched) -
svg="$tmp/demo-test.svg"
zsh "$root/tools/generate-readme-svg.zsh" "$svg" >/dev/null 2>&1
if [[ -s $svg ]] && grep -q '</svg>' "$svg" \
   && grep -q '<tspan fill="#a6e3a1">' "$svg" \
   && grep -q '<tspan fill="#f38ba8">' "$svg" \
   && ! grep -q $'\e' "$svg"; then
  ok "svg generator"
else
  bad "svg generator" "$(head -c 200 "$svg" 2>/dev/null)"
fi

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
