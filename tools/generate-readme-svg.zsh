#!/usr/bin/env zsh
# ---------------------------------------------------------------------------
# tools/generate-readme-svg.zsh — regenerate the README demo SVG.
#
# Renders REAL `claude-usage --pretty` output into an SVG terminal window:
# seeds fake per-account caches (same hermetic trick as test/run.zsh — no
# network, no credentials), captures the ANSI output, and converts the SGR
# colour codes into <tspan fill="…"> runs. The image in the README is
# therefore genuine renderer output, not hand-drawn art.
#
# Usage:  zsh tools/generate-readme-svg.zsh            # → assets/demo-v<ver>-<hash>.svg
#         zsh tools/generate-readme-svg.zsh OUT.svg    # fixed path, README untouched
#
# The default run deletes older assets/demo-v*.svg, embeds the version + a
# random hash in the filename (busts GitHub's camo image cache), and rewrites
# the README's <img> reference to match — commit both files. Regenerate
# whenever the default theme or the renderers change. Countdowns ("3d20h")
# are stable; the derived monthly date ("Aug 1") tracks the month you run it
# in — fine for a demo. (Pattern borrowed from grove's generate-screenshot.)
# ---------------------------------------------------------------------------
emulate -L zsh
setopt extended_glob

here=${0:a:h}
root=${here:h}
source "$root/claude-usage.zsh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp/"
# Hermetic: ignore the operator's real config + env (mirrors test/run.zsh)
export CLAUDE_USAGE_CONFIG="$tmp/no-such-config"
unset NO_COLOR CLAUDE_USAGE_COLORS CLAUDE_USAGE_THRESHOLDS \
      CLAUDE_USAGE_BAR_CHARS CLAUDE_USAGE_BRACKETS CLAUDE_USAGE_DIM \
      CLAUDE_USAGE_THEME CLAUDE_USAGE_SEP CLAUDE_USAGE_GROUP_SEP \
      CLAUDE_USAGE_SHOW_SPEND CLAUDE_USAGE_SHOW_BALANCE \
      CLAUDE_USAGE_SHOW_SPEND_RESET CLAUDE_USAGE_SHOW_LIMIT_RESETS \
      CLAUDE_USAGE_RESET_PREFIX CLAUDE_USAGE_SPEND_PREFIX \
      CLAUDE_USAGE_LIMITS_PREFIX CLAUDE_USAGE_BAR_WIDTH 2>/dev/null

# ---- seed demo accounts ----------------------------------------------------
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null \
        || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S+00:00 }
now=$(date +%s)
wk=$(iso $(( now + 3*86400 + 20*3600 + 30*60 )))   # → "3d20h"
ss=$(iso $(( now + 4*3600 + 5*60 + 30 )))          # → "4h5m"

seed() { mkdir -p "$tmp/$1"; print -r -- "$2" > "$TMPDIR/claude-oauth-usage.$1.json"; }

# Percentages picked to show all three fill colours (green <70, amber <90, red)
seed max '{"limits":[
  {"kind":"weekly_all","percent":34,"severity":"normal","resets_at":"'$wk'"},
  {"kind":"weekly_scoped","percent":76,"severity":"normal","resets_at":"'$wk'","scope":{"model":{"display_name":"Opus"}}},
  {"kind":"session","percent":93,"severity":"normal","resets_at":"'$ss'"}]}'
seed combo '{"spend":{"enabled":true,"used":{"amount_minor":1250,"exponent":2},
  "limit":{"amount_minor":4000,"exponent":2},"percent":31,
  "balance":{"amount_minor":10000,"exponent":2}},
 "limits":[
  {"kind":"weekly_all","percent":53,"severity":"normal","resets_at":"'$wk'"},
  {"kind":"weekly_scoped","percent":72,"severity":"normal","resets_at":"'$wk'","scope":{"model":{"display_name":"Fable"}}},
  {"kind":"session","percent":18,"severity":"normal","resets_at":"'$ss'"}]}'
seed work '{"spend":{"enabled":true,"used":{"amount_minor":14250,"exponent":2},
  "limit":{"amount_minor":30000,"exponent":2},"percent":47.5}}'

out_max=$(claude-usage --dir "$tmp/max")
out_combo=$(claude-usage --dir "$tmp/combo")
out_work=$(claude-usage --dir "$tmp/work")
out_text=$(claude-usage --dir "$tmp/max" --text-only)

# ---- ANSI → SVG ------------------------------------------------------------
# Catppuccin Mocha (matches grove's README screenshot palette)
BG='#1e1e2e'  BAR='#181825'  FG='#cdd6f4'  DIMC='#9399b2'
DOT1='#f38ba8' DOT2='#f9e2af' DOT3='#a6e3a1'
typeset -A SGR_FILL=(
  2 "$DIMC"
  31 '#f38ba8'  32 '#a6e3a1'  33 '#f9e2af'
  91 '#f38ba8'  92 '#a6e3a1'  93 '#f9e2af'
  '38;5;46' '#a6e3a1'  '38;5;226' '#f9e2af'  '38;5;196' '#f38ba8'
)

xesc() { local s=$1; s=${s//\&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; print -rn -- "$s" }

# Visible (SGR-stripped) length of a line
vlen() { local s=${1//$'\e['[0-9;]#m/}; print -rn -- ${#s} }

# One ANSI line → tspan runs (default colour inherits from the <text>)
render_ansi() {
  local s=$1 out="" fill="" pre tail params
  while [[ -n $s ]]; do
    pre=${s%%$'\e'*}                    # text up to the next ESC (or all of it)
    if [[ -n $pre ]]; then
      if [[ -n $fill ]]; then out+="<tspan fill=\"$fill\">$(xesc "$pre")</tspan>"
      else out+="$(xesc "$pre")"; fi
    fi
    s=${s[$(( ${#pre} + 1 )),-1]}       # "" or starts with ESC
    if [[ -n $s ]]; then
      tail=${s#$'\e['}
      params=${tail%%m*}
      s=${tail[$(( ${#params} + 2 )),-1]}
      if [[ -z $params || $params == 0 ]]; then fill=""
      else fill="${SGR_FILL[$params]:-}"; fi
    fi
  done
  print -rn -- "$out"
}

# ---- screen content --------------------------------------------------------
# Each entry: TYPE|content — c=dim comment, p=prompt+command, a=ANSI output, b=blank
lines=(
  'c|# Max / Pro seat — plan windows, each with its reset countdown'
  'p|claude-usage'
  "a|$out_max"
  'b|'
  'c|# Max + usage credits — credit group first, then the plan limits'
  'p|claude-usage'
  "a|$out_combo"
  'b|'
  'c|# USD-budget seat'
  'p|claude-usage --dir ~/.claude-work'
  "a|$out_work"
  'b|'
  'c|# plain one-liner for scripts / statuslines'
  'p|claude-usage --text-only'
  "a|$out_text"
)

# ---- layout ----------------------------------------------------------------
FONT="'Cascadia Code','Fira Code',SFMono-Regular,Consolas,Menlo,monospace"
integer FS=13 LH=20 TH=30 PX=20 PY=14
integer maxcols=0 n
local entry typ body
for entry in "${lines[@]}"; do
  typ=${entry%%\|*}; body=${entry#*\|}
  case $typ in
    p) n=$(( $(vlen "$body") + 2 )) ;;   # "❯ " prompt prefix
    *) n=$(vlen "$body") ;;
  esac
  (( n > maxcols )) && maxcols=$n
done
local -F cw=7.85                         # ~monospace advance at 13px
integer W=$(( PX * 2 + maxcols * cw + 6 ))
integer H=$(( TH + PY + ${#lines} * LH + PY ))

# ---- emit ------------------------------------------------------------------
render_svg() {
  print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$W\" height=\"$H\" viewBox=\"0 0 $W $H\" role=\"img\" aria-label=\"claude-usage example output\">"
  print -r -- "  <!-- terminal window -->"
  print -r -- "  <rect width=\"$W\" height=\"$H\" rx=\"10\" fill=\"$BG\"/>"
  print -r -- "  <rect width=\"$W\" height=\"$TH\" rx=\"10\" fill=\"$BAR\"/>"
  print -r -- "  <rect y=\"$(( TH - 6 ))\" width=\"$W\" height=\"6\" fill=\"$BAR\"/>"
  print -r -- "  <circle cx=\"18\" cy=\"$(( TH / 2 ))\" r=\"5.5\" fill=\"$DOT1\"/><circle cx=\"36\" cy=\"$(( TH / 2 ))\" r=\"5.5\" fill=\"$DOT2\"/><circle cx=\"54\" cy=\"$(( TH / 2 ))\" r=\"5.5\" fill=\"$DOT3\"/>"
  print -r -- "  <text x=\"$(( W / 2 ))\" y=\"$(( TH / 2 + 5 ))\" text-anchor=\"middle\" font-family=\"$FONT\" font-size=\"12\" fill=\"$DIMC\">claude-usage</text>"
  integer i=0 y
  for entry in "${lines[@]}"; do
    typ=${entry%%\|*}; body=${entry#*\|}
    y=$(( TH + PY + i * LH + FS ))
    case $typ in
      b) ;;
      c) print -r -- "  <text x=\"$PX\" y=\"$y\" font-family=\"$FONT\" font-size=\"$FS\" xml:space=\"preserve\" fill=\"$DIMC\">$(xesc "$body")</text>" ;;
      p) print -r -- "  <text x=\"$PX\" y=\"$y\" font-family=\"$FONT\" font-size=\"$FS\" xml:space=\"preserve\" fill=\"$FG\"><tspan fill=\"$DOT3\">❯</tspan> $(xesc "$body")</text>" ;;
      a) print -r -- "  <text x=\"$PX\" y=\"$y\" font-family=\"$FONT\" font-size=\"$FS\" xml:space=\"preserve\" fill=\"$FG\">$(render_ansi "$body")</text>" ;;
    esac
    (( i++ ))
  done
  print -r -- "</svg>"
}

if [[ -n ${1:-} ]]; then
  render_svg > "$1"
  print "wrote $1 (${W}x${H})"
else
  # Versioned, hash-stamped filename → busts GitHub's camo image cache; keep
  # the README's <img> reference in sync (grove's screenshot pattern).
  mkdir -p "$root/assets"
  local old
  for old in "$root"/assets/demo-v*.svg(N); do rm -f "$old"; done
  local hash; hash=$(xxd -l3 -p /dev/urandom)
  local fname="demo-v${CLAUDE_USAGE_VERSION}-${hash}.svg"
  render_svg > "$root/assets/$fname"
  sed -i.bak "s|assets/demo-v[^)\"]*\.svg|assets/$fname|" "$root/README.md" \
    && rm -f "$root/README.md.bak"
  print "wrote assets/$fname (${W}x${H}) and updated README.md"
fi
