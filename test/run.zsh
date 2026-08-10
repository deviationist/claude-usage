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
# Toggle off AND $0 spent → dormant cap, dollar segment must disappear
COMBO_OFF='{"spend":{"enabled":false,"used":{"amount_minor":0,"exponent":2},
  "limit":{"amount_minor":4000,"exponent":2},"percent":0},
 "limits":[
  {"kind":"weekly_all","percent":20,"severity":"normal"},
  {"kind":"session","percent":49,"severity":"normal"}]}'
# Toggle off BUT real spend accrued ($27.36 against a $40 cap) → still surfaced:
# a disabled cap with usage is worth showing, unlike a dormant $0 one.
COMBO_OFF_USED='{"spend":{"enabled":false,"used":{"amount_minor":2736,"exponent":2},
  "limit":{"amount_minor":4000,"exponent":2},"percent":68},
 "limits":[
  {"kind":"weekly_all","percent":20,"severity":"normal"},
  {"kind":"session","percent":49,"severity":"normal"}]}'

rl=$(seed ratelimit "$RL")
usd=$(seed usd "$USD")
combo=$(seed combo "$COMBO")
combooff=$(seed combooff "$COMBO_OFF")
combooffused=$(seed combooffused "$COMBO_OFF_USED")

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
eq 'text combined, dormant cap ($0, toggle off) hidden' \
  "$(claude-usage --dir $combooff --text-only --show-reset=false)" \
  "7d 20% | 5h 49%"
# Toggle off but real spend accrued → the dollar segment IS surfaced.
eq "text disabled cap with usage still shows" \
  "$(claude-usage --dir $combooffused --text-only --show-reset=false --show-spend-reset=false)" \
  "\$27.36 / \$40 (68%) || 7d 20% | 5h 49%"
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

# ---- labelled theme (full-config preset: labels via theme) ----------------
eq "labelled theme, text" \
  "$(claude-usage --dir $combo --text-only --show-reset=false --show-balance=false \
       --show-spend-reset=false --theme labelled)" \
  "Credit: \$0 / \$40 (0%) || Plan: 7d 20% | Opus 27% | 5h 49%"
lt=$(claude-usage --dir $rlt --theme labelled)
has "labelled theme, pretty labels"     "$lt" "Plan: "
has "labelled theme, pretty reset word" "$lt" "Reset 4h5m"
# explicit value beats the theme, from a flag and from env
eq "flag beats theme" \
  "$(claude-usage --dir $rl --text-only --show-reset=false --theme labelled --limits-prefix 'X: ')" \
  "X: 7d 20% | Opus 27% | 5h 49%"
eq "env beats theme" \
  "$(CLAUDE_USAGE_LIMITS_PREFIX='' claude-usage --dir $rl --text-only --show-reset=false --theme labelled)" \
  "7d 20% | Opus 27% | 5h 49%"

# ---- catppuccin theme (truecolor) -----------------------------------------
has "catppuccin truecolor" \
  "$(claude-usage --dir $rl --show-reset=false --theme catppuccin)" "${esc}[38;2;166;227;161m"

# ---- glyph themes ----------------------------------------------------------
rt=$(claude-usage --dir $rl --show-reset=false --theme retro)
has    "retro arcade bar"  "$rt" "[==........]"     # 20% of 10 = 2 full
hasnot "retro no blocks"   "$rt" "█"
has "retro phosphor colour" "$rt" "${esc}[38;5;40m"
sh=$(claude-usage --dir $rl --show-reset=false --theme shade)
has "shade blocks"      "$sh" "▓▓"
has "shade ice colour"  "$sh" "${esc}[38;5;81m"
dt=$(claude-usage --dir $rl --show-reset=false --theme dots)
has "dots meter"        "$dt" "●○○○"
has "dots candy colour" "$dt" "${esc}[38;5;114m"
has "spark ramp"    "$(claude-usage --dir $rl --show-reset=false --theme spark)" "██▁"
has "line gauge"    "$(claude-usage --dir $rl --show-reset=false --theme line)"  "━━"
has "dracula truecolor" \
  "$(claude-usage --dir $rl --show-reset=false --theme dracula)" "${esc}[38;2;80;250;123m"

# ---- --themes preview (one line per theme + blank spacer between) ----------
tp=$(claude-usage --dir $rl --show-reset=false --themes 2>/dev/null)
themecount=$(claude-usage --list-themes | wc -w | tr -d ' ')
# N rendered lines + N-1 blank spacers ($(...) strips the trailing newline)
eq "themes preview line count" "${#${(@f)tp}}" "$(( themecount * 2 - 1 ))"
has "themes preview labels"    "$tp" "catppuccin"
has "themes preview renders"   "$tp" "[=="

# ---- compact theme (bar width + separators via theme) ---------------------
cp=$(claude-usage --dir $rl --show-reset=false --theme compact)
hasnot "compact no brackets" "$cp" "▕"
has    "compact 5-cell bar"  "$cp" "█░░░░"   # 20% of 5 cells = 1 full
eq "compact text sep" \
  "$(claude-usage --dir $rl --text-only --show-reset=false --theme compact)" \
  "7d 20% Opus 27% 5h 49%"
# explicit bar width beats the theme
has "env width beats theme" \
  "$(CLAUDE_USAGE_BAR_WIDTH=10 claude-usage --dir $rl --show-reset=false --theme compact)" "██░░░░░░░░"

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

# ---- --cache-file: render a specific JSON file, no fetch/cache ------------
cf="$tmp/cachefile.json"; print -r -- "$RL" > "$cf"
has "cache-file pretty renders 7d"  "$(claude-usage --cache-file "$cf" --no-color)" "7d"
has "cache-file pretty renders 5h"  "$(claude-usage --cache-file "$cf" --no-color)" "5h"
eq  "cache-file text" "$(claude-usage --cache-file "$cf" --text-only)" \
    "7d 20% | Opus 27% | 5h 49%"
claude-usage --cache-file "$tmp/does-not-exist.json" >/dev/null 2>&1
(( $? == 1 )) && ok "cache-file missing → rc 1" || bad "cache-file missing → rc 1" "rc=$?"

# ---- --all: opt-in bridge to claude-profile -------------------------------
# With no claude-profile anywhere — not a function, not on PATH, and no
# sibling clone — --all must fail cleanly. An explicit CLAUDE_PROFILE_SCRIPT
# pointing at nothing is the authoritative "not installed" signal, so this
# holds on a dev machine that DOES have a sibling clone checked out.
CLAUDE_PROFILE_SCRIPT=/nonexistent/claude-profile.py claude-usage --all >/dev/null 2>&1
(( $? == 1 )) && ok "all without claude-profile → rc 1" || bad "all without claude-profile → rc 1" "rc=$?"

# Stub the companion tool: emit "<account>\t<json>" NDJSON — one healthy
# account, one unavailable (empty json field). The real porcelain emits
# COMPACT single-line JSON (json.dumps separators); mirror that (the contract
# is one physical line per account), so compact $RL through jq first.
RLC=$(print -r -- "$RL" | jq -c .)
claude-profile() {
  [[ "$1" == "usage-json" ]] || return 0
  printf '%s\t%s\n' "acctA" "$RLC"
  printf '%s\t\n'   "acctB"          # unavailable
}
allout=$(claude-usage --all --no-color)
has "all labels acctA"        "$allout" "acctA"
has "all renders acctA bar"   "$allout" "7d"
has "all acctB unavailable"   "$allout" "acctB  (usage unavailable)"
has "all text threads flags"  "$(claude-usage --all --text-only)" \
    "acctA  7d 20% | Opus 27% | 5h 49%"
# json mode → a valid array of {account, usage}; gaps become null
alljson=$(claude-usage --all --json)
print -r -- "$alljson" | jq -e '
  type=="array" and length==2
  and .[0].account=="acctA" and (.[0].usage.limits|length)==3
  and .[1].account=="acctB" and .[1].usage==null' >/dev/null \
  && ok "all json array shape" || bad "all json array shape" "$alljson"
unfunction claude-profile

# ---- --all --table: aligned, named columns across uneven accounts ---------
# acctA has a $-cap AND plan limits; acctB has only limits → the union-of-
# columns table must show a SPEND column with a dim "·" for acctB.
COMBOC=$(print -r -- "$COMBO" | jq -c .)
# RL variant with a (far-future) reset on the 7d window, none on 5h.
RLR='{"limits":[
  {"kind":"weekly_all","percent":20,"severity":"normal","resets_at":"2099-01-01T00:00:00Z"},
  {"kind":"weekly_scoped","percent":27,"severity":"normal","scope":{"model":{"display_name":"Opus"}}},
  {"kind":"session","percent":49,"severity":"normal"}]}'
RLRC=$(print -r -- "$RLR" | jq -c .)
claude-profile() {
  [[ "$1" == "usage-json" ]] || return 0
  printf '%s\t%s\n' "acctA" "$COMBOC"
  printf '%s\t%s\n' "acctB" "$RLC"
}
tout=$(claude-usage --all --table --no-color)
has "table header ACCOUNT" "$tout" "ACCOUNT"
has "table header SPEND"   "$tout" "SPEND"
has "table header 7D"      "$tout" "7D"
has "table header OPUS"    "$tout" "OPUS"
has "table header 5H"      "$tout" "5H"
has "table acctA spend"    "$tout" '$0/$40'
has "table acctB present"  "$tout" "acctB"
has "table missing → dot"  "$tout" "·"
# Borders are on by default; --no-borders drops the box-drawing chars.
has    "table borders by default" "$tout" "┌"
has    "table vertical rule"      "$tout" "│"
hasnot "table --no-borders"       "$(claude-usage --all --table --no-borders --no-color)" "│"
unfunction claude-profile

# --table is a FORMAT, orthogonal to --all: bare it renders a SINGLE account
# (labelled by its config-dir basename), no claude-profile call.
sdir=$(seed solo "$RL")
sout=$(claude-usage --dir "$sdir" --table --no-borders --no-color)
has "single-account table label" "$sout" "solo"
has "single-account table 7D"    "$sout" "7D"
has "single-account table 5h"    "$sout" "49%"

# Themed progress bars in cells (on by default), theme-aware glyphs, and the
# --no-bars / CLAUDE_USAGE_TABLE_BARS escape hatch back to a bare numeric grid.
has    "table bars by default"    "$sout" "▕"
has    "table bar full glyph"     "$sout" "█"
has    "table ascii theme bar"    "$(claude-usage --dir "$sdir" --table --no-borders --theme ascii)" "["
hasnot "table --no-bars drops bar" "$(claude-usage --dir "$sdir" --table --no-borders --no-bars --no-color)" "▕"
hasnot "table env TABLE_BARS=false" "$(CLAUDE_USAGE_TABLE_BARS=false claude-usage --dir "$sdir" --table --no-borders --no-color)" "▕"
has    "table --no-bars keeps pct" "$(claude-usage --dir "$sdir" --table --no-borders --no-bars --no-color)" "49%"

# Per-cell resets mirror the theme: shown with --reset-prefix, gone when the
# matching toggle is off (7d reset present here, none on 5h).
claude-profile() {
  [[ "$1" == "usage-json" ]] || return 0
  printf '%s\t%s\n' "acctR" "$RLRC"
}
has    "table cell reset shown"  "$(claude-usage --all --table --no-borders --reset-prefix 'R:' --no-color)" "R:"
hasnot "table reset toggle off"  "$(claude-usage --all --table --no-borders --reset-prefix 'R:' --show-limit-resets=false --no-color)" "R:"
unfunction claude-profile

# No account has a $-cap → the SPEND column must not appear at all.
claude-profile() {
  [[ "$1" == "usage-json" ]] || return 0
  printf '%s\t%s\n' "a" "$RLC"
  printf '%s\t%s\n' "b" "$RLC"
}
hasnot "table omits SPEND when none have it" "$(claude-usage --all --table --no-borders --no-color)" "SPEND"
unfunction claude-profile

# The table honours spend_on just like pretty mode: a live cap (enabled=true) or
# a disabled cap that carries real spend shows the SPEND column; only a dormant
# ($0, toggle off) cap suppresses it — so `--table` and the default line agree.
has    "table shows live cap"           "$(claude-usage --dir $combo --table --no-borders --no-color)"        '$0/$40'
has    "table shows disabled+used cap"  "$(claude-usage --dir $combooffused --table --no-borders --no-color)" '$27.36/$40'
hasnot "table hides dormant cap"        "$(claude-usage --dir $combooff --table --no-borders --no-color)"     "SPEND"
# --all table with only a dormant disabled-cap account: no SPEND column at all.
claude-profile() {
  [[ "$1" == "usage-json" ]] || return 0
  printf '%s\t%s\n' "off" "$COMBO_OFF"
}
hasnot "all table hides dormant cap" "$(claude-usage --all --table --no-borders --no-color)" "SPEND"
unfunction claude-profile

# ---- --show-profile: opt-in seat label ------------------------------------
# The label comes from claude-profile's `resolve --json` and is rendered
# verbatim; claude-usage never composes one. Stub answers that contract.
prof=$(seed prof "$RL")
claude-profile() {
  [[ "$1" == "resolve" ]] || return 0
  print -r -- '{"schema":1,"active":true,"profile":"personal","label":"Personal (Max 5x)"}'
}

# OFF by default — with a juggler installed AND answering, output must still
# be byte-identical to a machine that has none. This is the regression that
# matters: the feature may not leak into anyone's existing statusline.
eq "profile off by default (byte-identical)" \
   "$(claude-usage --dir $prof --text-only)" \
   "$(CLAUDE_PROFILE_SCRIPT=/nonexistent/x.py claude-usage --dir $prof --text-only)"
hasnot "profile off → no label" "$(claude-usage --dir $prof --text-only)" "Personal"

has "profile on → label prefix"  "$(claude-usage --dir $prof --text-only --show-profile)" "Personal (Max 5x) 7d"
has "profile pretty → dimmed"    "$(claude-usage --dir $prof --show-profile)" "${esc}[2mPersonal (Max 5x)${esc}[0m "
has "profile via env"            "$(CLAUDE_USAGE_SHOW_PROFILE=true claude-usage --dir $prof --text-only)" "Personal (Max 5x)"
has "profile flag =false wins"   "$(CLAUDE_USAGE_SHOW_PROFILE=true claude-usage --dir $prof --text-only --show-profile=false)" "7d"
hasnot "profile flag =false → no label" \
   "$(CLAUDE_USAGE_SHOW_PROFILE=true claude-usage --dir $prof --text-only --show-profile=false)" "Personal"
has "explicit --label needs no juggler" \
   "$(CLAUDE_PROFILE_SCRIPT=/nonexistent/x.py claude-usage --dir $prof --text-only --label 'Work')" "Work 7d"

# The lookup shells out to python — cached in a sidecar beside the usage cache
# so a repainting statusline pays for it once. Serving from that sidecar must
# not need claude-profile at all.
eq "profile sidecar written" "$(<"$TMPDIR/claude-oauth-usage.prof.json.label")" "Personal (Max 5x)"
unfunction claude-profile
has "profile served from sidecar" \
   "$(CLAUDE_PROFILE_SCRIPT=/nonexistent/x.py claude-usage --dir $prof --text-only --show-profile)" \
   "Personal (Max 5x)"

# A cached MISS must expire fast. A transient failure (claude-profile mid-swap,
# a run with the bridge disabled) would otherwise hide the label for the full
# label TTL — 15 minutes of "why is it gone?" for a one-second blip.
profmiss=$(seed profmiss "$RL")
missfile="$TMPDIR/claude-oauth-usage.profmiss.json.label"
: > $missfile
claude-profile() { print -r -- '{"schema":1,"active":true,"label":"Personal (Max 5x)"}'; }
has "expired empty label re-resolves" \
    "$(CLAUDE_USAGE_LABEL_TTL_MISS=-1 claude-usage --dir $profmiss --text-only --show-profile)" \
    "Personal (Max 5x)"
: > $missfile   # …but a fresh miss is honoured, so repaints don't re-fork
hasnot "fresh empty label is honoured" \
    "$(claude-usage --dir $profmiss --text-only --show-profile)" "Personal"
unfunction claude-profile

# "claude-profile answered, but there is nothing to disambiguate" is an ANSWER,
# not a failure: it must be cached with the full ttl, or a single-profile
# single-account machine re-forks python every minute forever.
profnone2=$(seed profnone2 "$RL")
nonefile="$TMPDIR/claude-oauth-usage.profnone2.json.label"
claude-profile() { print -r -- '{"schema":1,"active":true,"profile":"personal","label":""}'; }
eq "empty answer renders nothing" \
   "$(claude-usage --dir $profnone2 --text-only --show-profile)" \
   "$(claude-usage --dir $profnone2 --text-only)"
eq "empty answer stored as sentinel, not as a miss" "$(wc -c < $nonefile | tr -d ' ')" "1"
unfunction claude-profile
# …and with claude-profile now unreachable, the sentinel still serves (it is a
# real answer on the long ttl, unlike an empty file on the short one).
eq "sentinel survives on the long ttl" \
   "$(CLAUDE_PROFILE_SCRIPT=/nonexistent/x.py CLAUDE_USAGE_LABEL_TTL_MISS=-1 \
      claude-usage --dir $profnone2 --text-only --show-profile)" \
   "$(claude-usage --dir $profnone2 --text-only)"

# Every "no label" outcome is ordinary: render the usage, say nothing on stderr.
profoff=$(seed profoff "$RL")
claude-profile() { print -r -- '{"schema":1,"active":false}'; }
has    "inactive juggler → usage renders" "$(claude-usage --dir $profoff --text-only --show-profile)" "7d"
hasnot "inactive juggler → no label"      "$(claude-usage --dir $profoff --text-only --show-profile)" "("
unfunction claude-profile

profnone=$(seed profnone "$RL")
has "no juggler → usage renders" \
    "$(CLAUDE_PROFILE_SCRIPT=/nonexistent/x.py claude-usage --dir $profnone --text-only --show-profile)" "7d"
eq  "no juggler → silent on stderr" \
    "$(CLAUDE_PROFILE_SCRIPT=/nonexistent/x.py claude-usage --dir $profnone --text-only --show-profile 2>&1 >/dev/null)" ""

# --table (single account): the label names the seat better than the config
# dir's basename, so it takes the ACCOUNT cell.
has "single table uses seat label" \
    "$(claude-usage --dir $prof --table --no-borders --no-color --show-profile)" "Personal (Max 5x)"
hasnot "single table without it keeps basename" \
    "$(claude-usage --dir $prof --table --no-borders --no-color)" "Personal"

# --all: ONE extra call (`resolve --json --accounts`) labels every row.
claude-profile() {
  case "$1" in
    usage-json) printf '%s\t%s\n' "acctA" "$RLC"; printf '%s\t\n' "acctB" ;;
    resolve)    print -r -- '{"schema":1,"active":true,"accounts":[{"name":"acctA","label":"Personal (Max 20x)"},{"name":"acctB","label":"Work"}]}' ;;
  esac
}
allprof=$(claude-usage --all --show-profile --no-color)
has "all rows use seat labels"  "$allprof" "Personal (Max 20x)"
has "all pads to widest label"  "$allprof" "$(printf '%-18s  (usage unavailable)' 'Work')"
has "all table cell uses label" "$(claude-usage --all --table --no-borders --no-color --show-profile)" "Personal (Max 20x)"
has "all json keeps account key + adds label" \
    "$(claude-usage --all --json --show-profile | jq -r '.[0] | "\(.account)/\(.label)"')" "acctA/Personal (Max 20x)"
# An older claude-profile with no --accounts support: rows keep account names.
claude-profile() {
  [[ "$1" == "usage-json" ]] || return 1
  printf '%s\t%s\n' "acctA" "$RLC"
}
has "all degrades to account names" "$(claude-usage --all --show-profile --no-color)" "acctA  "
unfunction claude-profile

# ---- README SVG generator (smoke; explicit output paths → README untouched) -
svg="$tmp/demo-test.svg"; tsvg="$tmp/themes-test.svg"
zsh "$root/tools/generate-readme-svg.zsh" "$svg" "$tsvg" >/dev/null 2>&1
if [[ -s $svg ]] && grep -q '</svg>' "$svg" \
   && grep -q '<tspan fill="#00c200">' "$svg" \
   && grep -q '<tspan fill="#b43c2a">' "$svg" \
   && ! grep -q $'\e' "$svg"; then
  ok "svg generator (demo)"
else
  bad "svg generator (demo)" "$(head -c 200 "$svg" 2>/dev/null)"
fi
# themes SVG: truecolor passthrough (catppuccin a6e3a1) + 256-cube math
# (retro 38;5;40 → #00d700), every theme name present, no stray ESC
if [[ -s $tsvg ]] && grep -q '</svg>' "$tsvg" \
   && grep -q '<tspan fill="#00d700">' "$tsvg" \
   && grep -q 'gruvbox' "$tsvg" && grep -q 'catppuccin' "$tsvg" \
   && ! grep -q $'\e' "$tsvg"; then
  ok "svg generator (themes)"
else
  bad "svg generator (themes)" "$(head -c 200 "$tsvg" 2>/dev/null)"
fi

# ---- meta flags -----------------------------------------------------------
eq "version" "$(claude-usage --version)" "claude-usage $CLAUDE_USAGE_VERSION"
eq "list-themes" "$(claude-usage --list-themes)" \
  "default mono ascii bright neon labelled catppuccin compact retro shade dots spark line dracula nord gruvbox"

claude-usage --dir $rl --theme bogus >/dev/null 2>&1
(( $? == 1 )) && ok "unknown theme → rc 1" || bad "unknown theme → rc 1" "rc=$?"

claude-usage --bogus-flag >/dev/null 2>&1
(( $? == 1 )) && ok "unknown flag → rc 1" || bad "unknown flag → rc 1" "rc=$?"

# ---------------------------------------------------------------------------
rm -rf "$tmp"
print -- "\n${pass} passed, ${fail} failed"
(( fail == 0 ))
