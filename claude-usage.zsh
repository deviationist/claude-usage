# ============================================================================
# claude-usage — Claude seat spend/limits, from Anthropic's own counter
# ============================================================================
# Reads the same server-side numbers that claude.ai → Settings → Usage shows
# ("$300.04 of $300.00 spent"), via the OAuth usage endpoint that Claude Code's
# own token can query. Covers ALL usage billed to the account (Claude Code on
# any machine + claude.ai), unlike local transcript-based tools like ccusage.
#
# Install:  source this file from ~/.zshrc
#
# Usage:    claude-usage                      # default account (~/.claude), colour bars
#           claude-usage --text-only          # plain one-liner, no bars/colour
#           claude-usage --theme bright       # pick a preset (default/mono/ascii/bright/neon)
#           claude-usage --no-color           # keep the bars, drop all colour
#           claude-usage --list-themes        # print the built-in preset names
#           claude-usage --show-reset=false   # drop the trailing reset countdown
#           claude-usage --show-spend=false   # hide the monthly $-cap segment
#                                             # (combined view only — a $-cap-only
#                                             # seat always shows it)
#           claude-usage --show-balance=false # hide the credit-balance segment
#           claude-usage --show-spend-reset=false  # drop the monthly-cap reset
#                                             # date (shown by default; derived
#                                             # locally — 1st of next month — the
#                                             # API doesn't report it)
#           claude-usage --show-limit-resets=false # drop the per-window reset
#                                             # countdowns on the 7d/model limits
#           claude-usage --reset-prefix 'Reset '   # label every reset — window
#                                             # countdowns AND the monthly-cap
#                                             # date (default '' — bare
#                                             # "14m"/"3d21h"/"Aug 1")
#           claude-usage --spend-prefix 'Spend: '  # label before the $-group
#           claude-usage --limits-prefix 'Limits: ' # label before the plan
#                                             # limits (both default '', dimmed
#                                             # in pretty; bring your own
#                                             # trailing space)
#           claude-usage --group-sep ' ┃ '    # separator between the $-group and
#                                             # the plan limits (default " || "
#                                             # text, " | " pretty)
#           claude-usage --sep ' / '          # custom metric delimiter (both modes)
#           claude-usage --dir PATH           # another account's Claude config dir
#           claude-usage --json               # machine-readable summary
#           claude-usage --raw                # full untouched endpoint response
#           claude-usage --fresh              # blocking refresh, guaranteed current
#           claude-usage --no-block           # statusline mode: never blocks,
#                                             # prints nothing on cold/broken state
#           claude-usage --version            # print the version and exit
#           (respects the NO_COLOR env var — https://no-color.org)
#           (the claude-statusline companion project renders this in a
#            Claude Code status line, with per-segment toggles)
#
# Env:      CLAUDE_USAGE_CONFIG    config-file path (default:
#                                  ~/.config/claude-usage/config). Any
#                                  CLAUDE_USAGE_* key below can live there as
#                                  plain NAME=value lines — read by the
#                                  function itself in any process, so it works
#                                  where shell exports don't reach (statusline
#                                  repaints). Precedence: flags > config > env.
#           CLAUDE_USAGE_DIR       default config dir (default: ~/.claude)
#           CLAUDE_USAGE_SHOW_SPEND    default for --show-spend (true)
#           CLAUDE_USAGE_SHOW_BALANCE  default for --show-balance (true)
#           CLAUDE_USAGE_SHOW_SPEND_RESET  default for --show-spend-reset (true)
#           CLAUDE_USAGE_SHOW_LIMIT_RESETS default for --show-limit-resets (true)
#           CLAUDE_USAGE_GROUP_SEP         dollar-group / plan-limit separator
#           CLAUDE_USAGE_RESET_PREFIX      default for --reset-prefix ('')
#           CLAUDE_USAGE_SPEND_PREFIX      default for --spend-prefix ('')
#           CLAUDE_USAGE_LIMITS_PREFIX     default for --limits-prefix ('')
#           CLAUDE_USAGE_DIVISOR   credits→dollars divisor (default: 100 = cents)
#           CLAUDE_USAGE_BAR_WIDTH cells per bar in --pretty (default: 10)
#           CLAUDE_USAGE_SEP       metric delimiter, both modes (default: per-mode)
#           CLAUDE_USAGE_TTL       cache max age in seconds before a background
#                                  refresh is triggered (default: 120)
#
# Theming:  --pretty output is themed. Pick a preset with --theme NAME (or
#           CLAUDE_USAGE_THEME): default, mono (no colour), ascii (ASCII glyphs
#           + colour, for fonts without block chars), bright (bright ANSI), neon
#           (256-colour). --no-color drops colour from any theme but keeps bars.
#           Fine-grained overrides layer on top of the chosen theme:
#           CLAUDE_USAGE_COLORS      low:mid:high SGR params  (e.g. 32:33:31,
#                                    92:93:91, or 38;5;46:38;5;226:38;5;196; ""=none)
#           CLAUDE_USAGE_THRESHOLDS  amber:red fill breakpoints (e.g. 70:90)
#           CLAUDE_USAGE_BAR_CHARS   full:partial:empty glyphs (partial is a
#                                    low→high ramp, may be empty: e.g. '#::.')
#           CLAUDE_USAGE_BRACKETS    left:right bar frame (e.g. '[:]'; ':' = none)
#           CLAUDE_USAGE_DIM         SGR for separators/reset (default 2; ""=none)
#
# Output:   Default (--pretty), USD cap:  "$300.04/$300 ▕████▏100%"
#           Default (--pretty), Max/Pro:  "7d▕██░░▏40% 3d21h · opus▕███░▏63% 3d21h · 5h▕█░░░░▏12% 4h45m"
#           Max/Pro + usage credits:      "$0/$40 ▕░░░░▏0% Aug 1 | 7d▕██░░▏40% 3d21h · … 4h45m"
#           (both the plan windows and the credits budget exist → both render;
#            the dollar group leads — separated from the plan limits by the
#            group separator (--group-sep; default " || " text, " | " pretty)
#            since they are different mechanisms — and is dropped while
#            credits are toggled off. A "bal $100" purchased-credit segment
#            follows the $-cap whenever the API reports spend.balance — null
#            server-side so far. Non-session limits carry their own reset
#            countdown ("3d21h") from resets_at. Toggles: --show-spend,
#            --show-balance, --show-spend-reset, --show-limit-resets.)
#           --text-only, Max/Pro:         "7d 40% 3d21h | opus 63% 3d21h | 5h 12% 4h45m"
#           Both order 5h last (next to its countdown). --show-reset (default
#           true) appends the 5h-session countdown; every countdown takes the
#           same --reset-prefix label (default none); --sep / CLAUDE_USAGE_SEP
#           overrides the delimiter for both modes.
#
# Caching:  stale-while-revalidate, PER ACCOUNT (cache file is derived from the
#           config dir, so multiple accounts never clobber each other). Bare
#           invocations always return immediately from cache; if older than
#           $ttl (default 120s, override via CLAUDE_USAGE_TTL), a detached
#           background refresh runs and the NEXT call sees the new value.
#           Failed refreshes never destroy the last known
#           value, and back off for 60s so a broken state doesn't hammer
#           the endpoint from a constantly-repainting statusline.
#
# Caveats:  - Endpoint (api.anthropic.com/api/oauth/usage) is undocumented and
#             reverse-engineered from Claude Code; it may change without notice.
#           - Token lookup per account: $dir/.credentials.json first, then the
#             macOS Keychain entry "Claude Code-credentials-<hash>", where
#             <hash> = first 8 hex chars of sha256 of the absolute config dir
#             path (this is how Claude Code namespaces multi-account creds).
#             The legacy un-suffixed entry is only used for ~/.claude.
#           - Keep the TTL sane; hammering the endpoint gets rate-limited.
# ============================================================================

# Version, printed by `claude-usage --version`. Bump on release + tag.
typeset -g CLAUDE_USAGE_VERSION="0.3.0"

# The API reports credits worth $0.01 — divide by 100 for dollars.
export CLAUDE_USAGE_DIVISOR="${CLAUDE_USAGE_DIVISOR:-100}"

# Builtin zstat for portable mtime (GNU and BSD stat disagree on flags).
# -F loads only the zstat builtin, without shadowing the system `stat`.
zmodload -F zsh/stat b:zstat 2>/dev/null

# ----------------------------------------------------------------------------
# Internal: cache path for a given config dir.
# ~/.claude → claude-oauth-usage..claude.json  (basename keeps it readable)
# ----------------------------------------------------------------------------
_claude_usage_cache_path() {
  local dir="${1%/}"
  print -r -- "${TMPDIR:-/tmp}/claude-oauth-usage.${dir:t}.json"
}

# ----------------------------------------------------------------------------
# Internal: fetch the endpoint and atomically replace the cache on success.
#   $1 = 1 → if another refresh holds the lock, wait for it (up to ~10s);
#            also bypasses failure backoff. 0 = background semantics.
#   $2 = config dir
# Return codes: 0 ok, 2 no token, 3 network/timeout, 4 API rejected
# ----------------------------------------------------------------------------
_claude_usage_refresh() {
  local wait="${1:-0}"
  local dir="${2:-${CLAUDE_USAGE_DIR:-$HOME/.claude}}"
  local cache; cache=$(_claude_usage_cache_path "$dir")
  local lock="$cache.lock"
  local failmark="$cache.fail"
  local backoff=60

  # Failure backoff: if the last attempt failed <$backoff seconds ago, don't
  # keep hammering (a cold-cache statusline repaints constantly and would
  # otherwise spawn a doomed refresh on every tick). --fresh (wait=1) bypasses.
  if (( ! wait )) && [[ -f $failmark ]]; then
    local fmtime
    fmtime=$(zstat +mtime "$failmark" 2>/dev/null) || fmtime=0
    (( $(date +%s) - fmtime < backoff )) && return 0
  fi

  # mkdir is atomic → cheap cross-process lock, no stampedes
  if ! mkdir "$lock" 2>/dev/null; then
    (( wait )) || return 0
    local i
    for i in {1..100}; do          # wait ≤10s for the in-flight refresh
      [[ -d $lock ]] || return 0   # it finished; its result is our result
      sleep 0.1
    done
    return 0                       # stuck lock: give up, serve cache
  fi

  {
    # Collect candidate credential blobs from all sources for this dir, then
    # pick the freshest NON-EXPIRED token. Multiple sources can exist for one
    # account (file + suffixed Keychain + plain Keychain), and a stale entry
    # must not shadow a fresh one.
    local -a blobs
    blobs=( "$(cat "$dir/.credentials.json" 2>/dev/null)" )
    if command -v security >/dev/null 2>&1; then
      # macOS Keychain, namespaced per config dir: the service name is
      # "Claude Code-credentials-<first 8 hex of sha256(absolute dir path)>"
      local suffix
      suffix=$(printf '%s' "${dir:a}" \
                 | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null } \
                 | cut -c1-8)
      [[ -n $suffix ]] && blobs+=( "$(security find-generic-password \
          -s "Claude Code-credentials-$suffix" -a "$USER" -w 2>/dev/null)" )
      # Legacy un-suffixed entry, only for the default dir (created by
      # runs without CLAUDE_CONFIG_DIR; not disambiguated per account)
      [[ "${dir%/}" == "${HOME}/.claude" ]] && blobs+=( "$(security find-generic-password \
          -s "Claude Code-credentials" -a "$USER" -w 2>/dev/null)" )
    fi

    local token="" best_exp=-1 found_expired=0
    local now_ms=$(( $(date +%s) * 1000 ))
    local blob cand cand_exp
    for blob in "${blobs[@]}"; do
      [[ -z $blob ]] && continue
      cand=$(jq -r '.claudeAiOauth.accessToken // empty' <<< "$blob" 2>/dev/null)
      [[ -z $cand ]] && continue
      cand_exp=$(jq -r '.claudeAiOauth.expiresAt // empty' <<< "$blob" 2>/dev/null)
      if [[ -n $cand_exp ]] && (( cand_exp <= now_ms )); then
        found_expired=1
        continue
      fi
      [[ -z $cand_exp ]] && cand_exp=$now_ms   # unknown expiry: usable, lowest priority
      if (( cand_exp > best_exp )); then
        best_exp=$cand_exp
        token=$cand
      fi
    done
    if [[ -z $token ]]; then
      touch "$failmark"
      (( found_expired )) && return 5          # 5 = tokens found, all expired
      return 2                                 # 2 = no token at all
    fi

    # Write to tmp, validate, then mv — a failed fetch never clobbers the cache.
    # --connect-timeout fails fast when offline; --max-time bounds the whole call.
    if ! curl -s --connect-timeout 3 --max-time 6 \
        "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Content-Type: application/json" > "$cache.tmp" 2>/dev/null; then
      rm -f "$cache.tmp"
      touch "$failmark"
      return 3                    # 3 = network failure / timeout
    fi
    if ! jq -e '.error == null' "$cache.tmp" >/dev/null 2>&1; then
      rm -f "$cache.tmp"
      touch "$failmark"
      return 4                    # 4 = API rejected it (expired token, rate limit)
    fi
    mv "$cache.tmp" "$cache"
    rm -f "$failmark"
  } always {
    rmdir "$lock" 2>/dev/null
  }
}

# ----------------------------------------------------------------------------
# claude-usage [--dir PATH] [--json|--raw] [--fresh|--no-block]
# ----------------------------------------------------------------------------
claude-usage() {
  emulate -L zsh
  setopt extended_glob   # for the '#'-quantifier patterns in the config parser

  # ---- Optional config file -------------------------------------------------
  # ${CLAUDE_USAGE_CONFIG:-~/.config/claude-usage/config}: plain
  # "CLAUDE_USAGE_*=value" lines (quotes around the value optional; # comments
  # allowed). Each key is declared LOCAL before assignment, so nothing leaks
  # into the interactive shell. Precedence: flags > config file > process env
  # (config-over-env mirrors claude-statusline). This is the reliable way to
  # configure statusline rendering: the repaint subprocess doesn't inherit
  # your interactive shell's un-exported vars, but it always reads this file.
  local _cfg="${CLAUDE_USAGE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-usage/config}"
  if [[ -f $_cfg ]]; then
    local _line _k _v
    while IFS= read -r _line || [[ -n $_line ]]; do
      _line="${_line##[[:space:]]#}"
      [[ -z $_line || $_line == '#'* || $_line != *=* ]] && continue
      _k="${_line%%=*}"; _v="${_line#*=}"
      _k="${_k%%[[:space:]]#}"
      [[ $_k == CLAUDE_USAGE_[A-Z_]## ]] || continue
      # strip one pair of matching surrounding quotes, if present
      if (( ${#_v} >= 2 )) && \
         [[ ( $_v == '"'*'"' ) || ( $_v == "'"*"'" ) ]]; then
        _v="${_v[2,-2]}"
      fi
      eval "local ${_k}=\"\${_v}\""
    done < "$_cfg"
  fi

  local ttl="${CLAUDE_USAGE_TTL:-120}" mode=pretty force=0 noblock=0 show_reset=true
  # Dollar-segment toggles (combined Max+credits view): the monthly spend cap
  # and the purchased-credit balance. Env defaults, flags override below.
  local show_spend="${CLAUDE_USAGE_SHOW_SPEND:-true}"
  local show_balance="${CLAUDE_USAGE_SHOW_BALANCE:-true}"
  # Monthly spend-cap reset date (default true). Note: the API doesn't report
  # it, so it's derived locally (1st of next month, calendar boundary).
  local show_spend_reset="${CLAUDE_USAGE_SHOW_SPEND_RESET:-true}"
  # Per-window reset countdowns on the non-session limits (7d / model), from
  # each limit's resets_at. The 5h window keeps its trailing countdown.
  local show_limit_resets="${CLAUDE_USAGE_SHOW_LIMIT_RESETS:-true}"
  # Prefix put before EVERY window countdown (trailing 5h one included), so
  # all resets render in one style. Default "" (compact: "14m", "3d21h");
  # e.g. --reset-prefix "Reset " labels them all.
  local reset_prefix="${CLAUDE_USAGE_RESET_PREFIX-}"
  # Section prefixes: text inserted before the dollar group and before the
  # plan-limit group (e.g. "Spend: " / "Limits: "). Default "" — no labels.
  # Include your own trailing space; dimmed in pretty mode.
  local spend_prefix="${CLAUDE_USAGE_SPEND_PREFIX-}"
  local limits_prefix="${CLAUDE_USAGE_LIMITS_PREFIX-}"
  local divisor="${CLAUDE_USAGE_DIVISOR:-1}"
  local bar_width="${CLAUDE_USAGE_BAR_WIDTH:-10}"
  # Separator between metrics. Empty → per-mode default (" | " text, " · " pretty).
  local sep_override="${CLAUDE_USAGE_SEP-}" sep_set=0
  [[ -n ${CLAUDE_USAGE_SEP+x} ]] && sep_set=1
  # Group separator between the dollar segments (spend cap / balance — the
  # credits system) and the plan-limit bars (a different mechanism). Defaults
  # " || " text, " | " pretty (dimmed).
  local gsep_override="${CLAUDE_USAGE_GROUP_SEP-}" gsep_set=0
  [[ -n ${CLAUDE_USAGE_GROUP_SEP+x} ]] && gsep_set=1
  # Theme (pretty mode): --theme > CLAUDE_USAGE_THEME > "default". --no-color
  # forces all colour off regardless of theme (keeps the bars, unlike --text-only).
  local theme_override="" nocolor=0

  # Account dir: --dir > CLAUDE_USAGE_DIR > CLAUDE_CONFIG_DIR > ~/.claude.
  # Deliberately profile-agnostic: no coupling to claude-profile.zsh or any
  # cwd-override convention — callers wanting another seat pass --dir.
  local dir="${CLAUDE_USAGE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"

  while (( $# )); do
    case "$1" in
      --json)       mode=json ;;
      --raw)        mode=raw ;;
      --pretty)     mode=pretty ;;
      --text-only|--plain) mode=text ;;
      --show-reset)       show_reset=true ;;
      --show-reset=*)
        show_reset="${1#--show-reset=}"
        [[ $show_reset == (true|false) ]] || { print -u2 "claude-usage: --show-reset takes true or false"; return 1 } ;;
      --show-spend)       show_spend=true ;;
      --show-spend=*)
        show_spend="${1#--show-spend=}"
        [[ $show_spend == (true|false) ]] || { print -u2 "claude-usage: --show-spend takes true or false"; return 1 } ;;
      --show-balance)     show_balance=true ;;
      --show-balance=*)
        show_balance="${1#--show-balance=}"
        [[ $show_balance == (true|false) ]] || { print -u2 "claude-usage: --show-balance takes true or false"; return 1 } ;;
      --show-spend-reset) show_spend_reset=true ;;
      --show-spend-reset=*)
        show_spend_reset="${1#--show-spend-reset=}"
        [[ $show_spend_reset == (true|false) ]] || { print -u2 "claude-usage: --show-spend-reset takes true or false"; return 1 } ;;
      --show-limit-resets) show_limit_resets=true ;;
      --show-limit-resets=*)
        show_limit_resets="${1#--show-limit-resets=}"
        [[ $show_limit_resets == (true|false) ]] || { print -u2 "claude-usage: --show-limit-resets takes true or false"; return 1 } ;;
      --reset-prefix)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --reset-prefix requires a value"; return 1 }
        reset_prefix="$2"; shift ;;
      --reset-prefix=*) reset_prefix="${1#--reset-prefix=}" ;;
      --spend-prefix)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --spend-prefix requires a value"; return 1 }
        spend_prefix="$2"; shift ;;
      --spend-prefix=*) spend_prefix="${1#--spend-prefix=}" ;;
      --limits-prefix)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --limits-prefix requires a value"; return 1 }
        limits_prefix="$2"; shift ;;
      --limits-prefix=*) limits_prefix="${1#--limits-prefix=}" ;;
      --sep)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --sep requires a value"; return 1 }
        sep_override="$2"; sep_set=1; shift ;;
      --sep=*)    sep_override="${1#--sep=}"; sep_set=1 ;;
      --group-sep)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --group-sep requires a value"; return 1 }
        gsep_override="$2"; gsep_set=1; shift ;;
      --group-sep=*) gsep_override="${1#--group-sep=}"; gsep_set=1 ;;
      --theme)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --theme requires a name"; return 1 }
        theme_override="$2"; shift ;;
      --theme=*)  theme_override="${1#--theme=}" ;;
      --no-color|--no-colour) nocolor=1 ;;
      --list-themes) print "default mono ascii bright neon"; return 0 ;;
      --version|-V) print "claude-usage $CLAUDE_USAGE_VERSION"; return 0 ;;
      --fresh)      force=1 ;;
      --no-block)   noblock=1 ;;
      --dir)
        [[ -n "$2" ]] || { print -u2 "claude-usage: --dir requires a path"; return 1 }
        dir="$2"; shift ;;
      --dir=*)    dir="${1#--dir=}" ;;
      -h|--help)
        print "usage: claude-usage [--dir PATH] [--pretty|--text-only|--json|--raw] [--theme NAME|--no-color] [--show-reset=true|false] [--show-spend=true|false] [--show-balance=true|false] [--show-spend-reset=true|false] [--show-limit-resets=true|false] [--reset-prefix STR] [--spend-prefix STR] [--limits-prefix STR] [--sep STR] [--group-sep STR] [--fresh|--no-block] [--version]"
        print "themes: default mono ascii bright neon  (also --list-themes)"
        return 0 ;;
      *)
        print -u2 "usage: claude-usage [--dir PATH] [--pretty|--text-only|--json|--raw] [--theme NAME|--no-color] [--show-reset=true|false] [--show-spend=true|false] [--show-balance=true|false] [--show-spend-reset=true|false] [--show-limit-resets=true|false] [--reset-prefix STR] [--spend-prefix STR] [--limits-prefix STR] [--sep STR] [--group-sep STR] [--fresh|--no-block]"
        return 1 ;;
    esac
    shift
  done
  dir="${dir%/}"
  # Env-sourced toggles could hold garbage → they feed jq --argjson, sanitize.
  [[ $show_spend        == (true|false) ]] || show_spend=true
  [[ $show_balance      == (true|false) ]] || show_balance=true
  [[ $show_limit_resets == (true|false) ]] || show_limit_resets=true

  # ---- Theme resolution (pretty mode) ---------------------------------------
  # A theme is: 3 colours (low/mid/high fill) + 2 thresholds + 3 bar glyphs
  # (full / partial-ramp / empty) + 2 brackets + a dim SGR for separators.
  # Colours/dim are raw SGR params ("32", "92", "38;5;196", or "" = no colour).
  # gpartial is a low→high ramp of fractional-cell glyphs ("" = no partial cell).
  local theme="${theme_override:-${CLAUDE_USAGE_THEME:-default}}"
  local clo cmid chi tmid thi gfull gpartial gempty lbr rbr dim _a _b
  case "$theme" in
    default)
      clo=32 cmid=33 chi=31; tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'; dim=2 ;;
    mono)          # no colour, keep the unicode bars (separators stay faint)
      clo='' cmid='' chi=''; tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'; dim=2 ;;
    ascii)         # colours + ASCII glyphs, for fonts without block chars
      clo=32 cmid=33 chi=31; tmid=70 thi=90
      gfull='#' gpartial='' gempty='.'; lbr='[' rbr=']'; dim=2 ;;
    bright)        # bright ANSI colours, unicode bars
      clo=92 cmid=93 chi=91; tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'; dim=2 ;;
    neon)          # vivid 256-colour, unicode bars
      clo='38;5;46' cmid='38;5;226' chi='38;5;196'; tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'; dim=2 ;;
    *)
      print -u2 "claude-usage: unknown theme '$theme' (valid: default mono ascii bright neon)"
      return 1 ;;
  esac

  # Per-field overrides layered on top of the theme. Manual %%/# splitting
  # (not (s.:.)) so empty fields survive — e.g. BAR_CHARS='#::.' = no partial.
  if [[ -n ${CLAUDE_USAGE_COLORS:-} ]]; then
    clo="${CLAUDE_USAGE_COLORS%%:*}"; _a="${CLAUDE_USAGE_COLORS#*:}"
    cmid="${_a%%:*}"; chi="${_a#*:}"
  fi
  if [[ -n ${CLAUDE_USAGE_THRESHOLDS:-} ]]; then
    tmid="${CLAUDE_USAGE_THRESHOLDS%%:*}"; thi="${CLAUDE_USAGE_THRESHOLDS#*:}"
  fi
  if [[ -n ${CLAUDE_USAGE_BAR_CHARS:-} ]]; then
    gfull="${CLAUDE_USAGE_BAR_CHARS%%:*}"; _b="${CLAUDE_USAGE_BAR_CHARS#*:}"
    gpartial="${_b%%:*}"; gempty="${_b#*:}"
  fi
  [[ -n ${CLAUDE_USAGE_BRACKETS+x} ]] && { lbr="${CLAUDE_USAGE_BRACKETS%%:*}"; rbr="${CLAUDE_USAGE_BRACKETS#*:}"; }
  [[ -n ${CLAUDE_USAGE_DIM+x} ]] && dim="$CLAUDE_USAGE_DIM"
  # --no-color, or the NO_COLOR convention (https://no-color.org: any non-empty
  # value), strips every SGR while keeping the bars — unlike --text-only.
  if (( nocolor )) || [[ -n ${NO_COLOR:-} ]]; then clo='' cmid='' chi='' dim=''; fi

  local cache; cache=$(_claude_usage_cache_path "$dir")

  if (( force )) || [[ ! -f $cache ]]; then
    if (( noblock )); then
      # Statusline mode: NEVER block. No cache yet → kick off a background
      # refresh, print nothing, exit clean; the next repaint picks it up.
      [[ -f $cache ]] || { ( _claude_usage_refresh 0 "$dir" & ) >/dev/null 2>&1; return 0 }
    else
      # Forced refresh or cold start: block on the network.
      # (wait=1 so --fresh also waits out any in-flight background refresh)
      _claude_usage_refresh 1 "$dir"
      local rc=$?
      if [[ ! -f $cache ]]; then
        case $rc in
          2) print -u2 "claude-usage: no OAuth token in $dir — is Claude Code logged in for this account?" ;;
          3) print -u2 "claude-usage: network failure or timeout reaching api.anthropic.com" ;;
          4) print -u2 "claude-usage: API rejected the request (expired token or rate-limited) — run a Claude Code session and retry" ;;
          5) print -u2 "claude-usage: all stored tokens for $dir are expired — start a Claude Code session for this account to refresh them" ;;
          *) print -u2 "claude-usage: refresh failed" ;;
        esac
        return 1
      fi
      # Cache exists but forced refresh failed → warn, then serve stale below
      if (( force && rc != 0 )); then
        print -u2 "claude-usage: refresh failed (code $rc), showing cached value"
      fi
    fi
  else
    # Warm path: serve cache instantly; revalidate behind the scenes if stale.
    # The ( ... & ) subshell detaches from job control: no [1] 12345 noise.
    local mtime
    mtime=$(zstat +mtime "$cache" 2>/dev/null) || mtime=0
    if (( $(date +%s) - mtime > ttl )); then
      ( _claude_usage_refresh 0 "$dir" & ) >/dev/null 2>&1
    fi
  fi

  # Monthly spend-cap reset label ("" = don't show). Derived, not from the
  # API: usage credits reset on the 1st of the next calendar month.
  local spend_reset=""
  if [[ $show_spend_reset == true ]]; then
    local -a _mn=(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
    spend_reset="${_mn[$(( 10#$(date +%m) % 12 + 1 ))]} 1"
  fi

  # Metric separator: an explicit --sep / CLAUDE_USAGE_SEP wins for both modes;
  # otherwise each mode keeps its own default (" | " plain, " · " dimmed).
  local text_sep pretty_sep
  if (( sep_set )); then text_sep="$sep_override"; pretty_sep="$sep_override"
  else text_sep=" | "; pretty_sep=" · "; fi
  local text_gsep pretty_gsep
  if (( gsep_set )); then text_gsep="$gsep_override"; pretty_gsep="$gsep_override"
  else text_gsep=" || "; pretty_gsep=" | "; fi

  case $mode in
    raw)
      jq . "$cache"
      ;;
    json)
      jq --argjson d "$divisor" '
        # Money in minor units: {amount_minor, exponent} → dollars
        def money:
          if type == "object" then (.amount_minor // 0) / pow(10; (.exponent // 2))
          elif type == "number" then .
          else 0 end;
        def limit_label:
          if .kind == "session" then "5h"
          elif .kind == "weekly_all" then "7d"
          elif .kind == "weekly_scoped" then (.scope.model.display_name // .scope.surface // "scoped")
          else .kind end;
        # Unified spend: prefer modern .spend, fall back to legacy .extra_usage
        (if (.spend.enabled // false) or ((.spend.limit // null) != null) then
           { spent: (.spend.used | money),
             limit: (.spend.limit | if . == null then null else money end),
             balance: (.spend.balance | if . == null then null else money end),
             percent: .spend.percent,
             enabled: (.spend.enabled // false),
             source: "spend" }
         elif ((.extra_usage.monthly_limit // 0) > 0 or (.extra_usage.is_enabled // false)) then
           (if .extra_usage.decimal_places != null
            then pow(10; .extra_usage.decimal_places) else $d end) as $div |
           { spent: ((.extra_usage.used_credits  // 0) / $div),
             limit: ((.extra_usage.monthly_limit // 0) / $div),
             balance: null,
             percent: .extra_usage.utilization,
             enabled: (.extra_usage.is_enabled // false),
             source: "extra_usage" }
         else
           { spent: null, limit: null, balance: null, percent: null, enabled: false, source: null }
         end) as $spend |
        {
          spend: $spend,
          limits: [ (.limits // [])[]
                    | { kind, label: limit_label, percent, severity,
                        resets_at, active: (.is_active // false),
                        scope: (.scope.model.display_name // .scope.surface // null) } ],
          # legacy convenience fields
          five_hour_pct:  .five_hour.utilization,
          seven_day_pct:  .seven_day.utilization,
          opus_pct:       .seven_day_opus.utilization,
          sonnet_pct:     .seven_day_sonnet.utilization
        }' "$cache"
      ;;
    text)
      # Plain one-liner (no bars, no colour): "7d 16% | Fable 25% | 5h 4%".
      # Ordered like --pretty (5h last, next to Reset); --show-reset (default)
      # appends "<sep>Reset 4h45m" from the 5h window.
      jq -r --argjson d "$divisor" --argjson showreset "$show_reset" \
            --argjson showspend "$show_spend" --argjson showbal "$show_balance" \
            --argjson showlr "$show_limit_resets" --arg rpfx "$reset_prefix" \
            --arg sppfx "$spend_prefix" --arg limpfx "$limits_prefix" \
            --arg spendreset "$spend_reset" --arg sep "$text_sep" \
            --arg gsep "$text_gsep" '
        def money:
          if type == "object" then (.amount_minor // 0) / pow(10; (.exponent // 2))
          elif type == "number" then .
          else 0 end;
        def fmt2: (. * 100 | round / 100);
        def limit_label:
          if .kind == "session" then "5h"
          elif .kind == "weekly_all" then "7d"
          elif .kind == "weekly_scoped" then (.scope.model.display_name // .scope.surface // "scoped")
          else .kind end;
        # Countdown to an ISO timestamp: "3d20h" / "4h45m" / "45m"; "" past/absent
        def left($r):
          if ($r == null) then ""
          else (try (($r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) - now | floor) catch -1) as $rem
            | if $rem <= 0 then ""
              else (($rem / 86400) | floor) as $dd
                 | ((($rem % 86400) / 3600) | floor) as $h
                 | ((($rem % 3600) / 60) | floor) as $m
                 | if $dd > 0 then "\($dd)d\($h)h" elif $h > 0 then "\($h)h\($m)m" else "\($m)m" end
              end
          end;
        # Per-window reset suffix on the non-session limits (7d / model);
        # the 5h session window keeps the trailing countdown instead. $rpfx
        # (--reset-prefix) labels both in one style.
        def lim_left:
          if $showlr and .kind != "session" then
            left(.resets_at) as $t | (if $t != "" then " \($rpfx)\($t)" else "" end)
          else "" end;
        # "!" marks non-normal severity (warning/exceeded)
        def limit_line: "\(limit_label) \(.percent // 0 | round)%\(if (.severity // "normal") != "normal" then "!" else "" end)\(lim_left)";
        # Time left on the 5h session window (trailing "Reset …" segment)
        def reset_left:
          left([ .limits[]? | select(.kind == "session") | .resets_at ] | first);

        # Monthly-reset suffix folded into the percent paren: "(0%, Aug 1)" —
        # takes the same $rpfx label as the window countdowns
        def rst: if $spendreset != "" then ", \($rpfx)\($spendreset)" else "" end;
        # Dollar segment ("" when the account has no cap): modern .spend
        # preferred, legacy .extra_usage (work seats on older schema) fallback.
        def spend_line:
          if (.spend.limit // null) != null then
            (.spend.used | money) as $s | (.spend.limit | money) as $l |
            "$\($s | fmt2) / $\($l | fmt2) (\(.spend.percent // (if $l > 0 then $s / $l * 100 else 0 end) | round)%\(rst))"
          elif (.extra_usage.monthly_limit // 0) > 0 then
            (if .extra_usage.decimal_places != null
             then pow(10; .extra_usage.decimal_places) else $d end) as $div |
            ((.extra_usage.used_credits  // 0) / $div) as $s |
            ((.extra_usage.monthly_limit // 0) / $div) as $l |
            "$\($s | fmt2) / $\($l | fmt2) (\($s / $l * 100 | round)%\(rst))"
          else "" end;
        # Is the dollar cap live? (usage credits can be toggled off in the GUI)
        def spend_on:
          if .spend != null then (.spend.enabled // false)
          else (.extra_usage.is_enabled // false) end;
        # Purchased-credit balance segment ("" until the API reports one — the
        # field exists in the schema but is null-so-far server-side)
        def balance_line:
          (.spend.balance // null) as $b
          | if $b == null then "" else "bal $\($b | money | fmt2)" end;

        (
          (spend_line) as $sp |
          (balance_line) as $bal |
          ((if ($bal != "" and $showbal) then [$bal] else [] end)) as $balseg |
          # 1) Plan limits present (Max/Pro): non-session windows first, 5h
          #    session held last (next to Reset). A dollar cap alongside them
          #    (Max + usage credits, the overflow budget) leads the line —
          #    shown only while the credits toggle is on; the credit balance
          #    follows it. Both individually togglable (--show-spend/-balance).
          if ((.limits // []) | length) > 0 then
            ([ .limits[] | select(.kind != "session") | limit_line ]) as $others |
            ([ .limits[] | select(.kind == "session") | limit_line ]) as $sess |
            ((if ($sp != "" and spend_on and $showspend) then [$sp] else [] end)
              + $balseg) as $dollars |
            ($limpfx + (($others + $sess) | join($sep))) as $limstr |
            # $gsep between the dollar group and the plan-limit group — they
            # are different mechanisms, not one list of metrics. Each group
            # takes its optional section prefix (--spend-prefix/--limits-prefix).
            (if ($dollars | length) > 0
             then ($sppfx + ($dollars | join($sep)) + $gsep + $limstr)
             else $limstr end)
          # 2) Dollar cap only (Enterprise / USD-budget seat): the cap is the
          #    whole display, so --show-spend=false is ignored here
          elif $sp != "" then ($sppfx + (([$sp] + $balseg) | join($sep)))
          # 3) Oldest fallback: flat five_hour / seven_day fields (5h last)
          else
            $limpfx +
            (
            [ "7d \(.seven_day.utilization // 0 | round)%",
              (if (.seven_day_opus.utilization) != null
               then "opus \(.seven_day_opus.utilization | round)%" else empty end),
              (if (.seven_day_sonnet.utilization) != null
               then "sonnet \(.seven_day_sonnet.utilization | round)%" else empty end),
              "5h \(.five_hour.utilization // 0 | round)%"
            ] | join($sep))
          end
        ) + (if $showreset then (reset_left | if . == "" then "" else " \($rpfx)\(.)" end) else "" end)
      ' "$cache"
      ;;
    pretty)
      # Colour bars, inspired by statusline-command.sh. Each metric is
      # "<label>▕<bar>▏<pct>%" tinted by fill; USD seats render
      # "$s/$l ▕bar▏pct%". Colours, thresholds, glyphs and brackets all come
      # from the resolved theme (--theme / CLAUDE_USAGE_THEME, plus the per-field
      # CLAUDE_USAGE_{COLORS,THRESHOLDS,BAR_CHARS,BRACKETS,DIM} overrides above).
      # With --reset (default) the 5h window shows its countdown last. Bar width
      # via CLAUDE_USAGE_BAR_WIDTH (default 10).
      jq -r --argjson d "$divisor" --argjson w "$bar_width" \
            --argjson showreset "$show_reset" --arg sep "$pretty_sep" \
            --argjson showspend "$show_spend" --argjson showbal "$show_balance" \
            --argjson showlr "$show_limit_resets" --arg rpfx "$reset_prefix" \
            --arg sppfx "$spend_prefix" --arg limpfx "$limits_prefix" \
            --arg spendreset "$spend_reset" --arg gsep "$pretty_gsep" \
            --arg clo "$clo" --arg cmid "$cmid" --arg chi "$chi" \
            --argjson tmid "$tmid" --argjson thi "$thi" \
            --arg gfull "$gfull" --arg gpartial "$gpartial" --arg gempty "$gempty" \
            --arg lbr "$lbr" --arg rbr "$rbr" --arg dim "$dim" '
        def money:
          if type == "object" then (.amount_minor // 0) / pow(10; (.exponent // 2))
          elif type == "number" then .
          else 0 end;
        def fmt2: (. * 100 | round / 100);
        def limit_label:
          if .kind == "session" then "5h"
          elif .kind == "weekly_all" then "7d"
          elif .kind == "weekly_scoped" then (.scope.model.display_name // .scope.surface // "scoped")
          else .kind end;
        def col($p): if $p >= $thi then $chi elif $p >= $tmid then $cmid else $clo end;
        # Wrap $s in SGR $c, but only when $c is non-empty (mono/--no-color: no ANSI).
        def paint($c; $s): if ($c | length) > 0 then "[\($c)m\($s)[0m" else $s end;
        def mkbar($p):
          (if $p < 0 then 0 elif $p > 100 then 100 else $p end) as $pct
          | ($pct / 100 * $w * 8) as $units
          | (($units / 8) | floor) as $full
          | (($units - ($full * 8)) | floor) as $partial
          | ([$full, $w] | min) as $fc
          | ($gpartial | length) as $pn                          # ramp length (0 = none)
          | (($fc < $w) and ($partial >= 1) and ($pn > 0)) as $hasp
          | (if $hasp then (($partial * $pn / 8) | floor) else 0 end) as $pidx
          | ($fc + (if $hasp then 1 else 0 end)) as $used
          | (($gfull * $fc) // "")                               # full cells
            + (if $hasp then ($gpartial | .[$pidx:($pidx + 1)]) else "" end)   # partial cell
            + (($gempty * ($w - $used)) // "");                  # empty cells
        def bar($label; $p):
          paint(col($p); "\($label)\($lbr)\(mkbar($p))\($rbr)\($p | round)%");
        # Countdown to an ISO timestamp: "3d20h" / "4h45m" / "45m"; "" past/absent
        def left($r):
          if ($r == null) then ""
          else (try (($r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) - now | floor) catch -1) as $rem
            | if $rem <= 0 then ""
              else (($rem / 86400) | floor) as $dd
                 | ((($rem % 86400) / 3600) | floor) as $h
                 | ((($rem % 3600) / 60) | floor) as $m
                 | if $dd > 0 then "\($dd)d\($h)h" elif $h > 0 then "\($h)h\($m)m" else "\($m)m" end
              end
          end;
        # Per-window reset suffix (dimmed) on the non-session bars (7d / model);
        # the 5h session bar keeps the trailing countdown instead. $rpfx
        # (--reset-prefix) labels both in one style.
        def lim_left:
          if $showlr then
            left(.resets_at) as $t | (if $t != "" then " " + paint($dim; "\($rpfx)\($t)") else "" end)
          else "" end;
        # Time left on the 5h session window (trailing "Reset …" segment)
        def reset_left:
          left([ .limits[]? | select(.kind == "session") | .resets_at ] | first);
        (paint($dim; $sep)) as $sep |                            # dimmed separator

        # Monthly-reset suffix, dimmed, after the spend bar: " Aug 1" — takes
        # the same $rpfx label as the window countdowns
        def rst: if $spendreset != "" then " " + paint($dim; "\($rpfx)\($spendreset)") else "" end;
        # Dollar bar ("" when the account has no cap): modern .spend preferred,
        # legacy .extra_usage fallback.
        def spend_bar:
          if (.spend.limit // null) != null then
            (.spend.used | money) as $s | (.spend.limit | money) as $l |
            (.spend.percent // (if $l > 0 then $s / $l * 100 else 0 end)) as $p |
            paint(col($p); "$\($s | fmt2)/$\($l | fmt2) \($lbr)\(mkbar($p))\($rbr)\($p | round)%") + rst
          elif (.extra_usage.monthly_limit // 0) > 0 then
            (if .extra_usage.decimal_places != null
             then pow(10; .extra_usage.decimal_places) else $d end) as $div |
            ((.extra_usage.used_credits  // 0) / $div) as $s |
            ((.extra_usage.monthly_limit // 0) / $div) as $l |
            (if $l > 0 then $s / $l * 100 else 0 end) as $p |
            paint(col($p); "$\($s | fmt2)/$\($l | fmt2) \($lbr)\(mkbar($p))\($rbr)\($p | round)%") + rst
          else "" end;
        # Is the dollar cap live? (usage credits can be toggled off in the GUI)
        def spend_on:
          if .spend != null then (.spend.enabled // false)
          else (.extra_usage.is_enabled // false) end;
        # Purchased-credit balance segment, dimmed — no percent, so no bar
        # ("" until the API reports one; the field is null-so-far server-side)
        def balance_seg:
          (.spend.balance // null) as $b
          | if $b == null then "" else paint($dim; "bal $\($b | money | fmt2)") end;

        # Optional section prefix, dimmed; "" stays "" (no stray SGR bytes)
        def secpfx($p): if $p != "" then paint($dim; $p) else "" end;

        (
          (spend_bar) as $sp |
          (balance_seg) as $bal |
          ((if ($bal != "" and $showbal) then [$bal] else [] end)) as $balseg |
          # 1) Plan limits present (Max/Pro): non-session bars first, session
          #    held to the end (next to its reset). A dollar cap alongside them
          #    (Max + usage credits, the overflow budget) leads the line —
          #    shown only while the credits toggle is on; the credit balance
          #    follows it. Both individually togglable (--show-spend/-balance).
          if ((.limits // []) | length) > 0 then
            ([ .limits[] | select(.kind != "session") | bar(limit_label; (.percent // 0)) + lim_left ]) as $others |
            ([ .limits[] | select(.kind == "session") ] | first) as $sess |
            (if $sess != null then [ $sess | bar("5h"; (.percent // 0)) ] else [] end) as $ssegs |
            ((if ($sp != "" and spend_on and $showspend) then [$sp] else [] end)
              + $balseg) as $dollars |
            (secpfx($limpfx) + (($others + $ssegs) | join($sep))) as $limstr |
            # dimmed $gsep between the dollar group and the plan-limit group —
            # they are different mechanisms, not one list of metrics. Each
            # group takes its optional dimmed section prefix.
            (if ($dollars | length) > 0
             then (secpfx($sppfx) + ($dollars | join($sep)) + paint($dim; $gsep) + $limstr)
             else $limstr end)
          # 2) Dollar cap only (Enterprise / USD-budget seat): the cap is the
          #    whole display, so --show-spend=false is ignored here
          elif $sp != "" then (secpfx($sppfx) + (([$sp] + $balseg) | join($sep)))
          # 3) Oldest fallback: flat five_hour / seven_day fields (5h last)
          else
            secpfx($limpfx) +
            ([ bar("7d"; (.seven_day.utilization // 0)),
               bar("5h"; (.five_hour.utilization // 0)) ] | join($sep))
          end
        ) + (if $showreset then (reset_left | if . == "" then "" else " " + paint($dim; "\($rpfx)\(.)") end) else "" end)

      ' "$cache"
      ;;
  esac
}
