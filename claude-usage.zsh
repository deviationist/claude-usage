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
#           claude-usage --theme labelled     # pick a preset (--list-themes for names)
#           claude-usage --no-color           # keep the bars, drop all colour
#           claude-usage --list-themes        # print the built-in preset names
#           claude-usage --themes             # preview: render your current
#                                             # usage once per theme
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
#           claude-usage --show-profile       # prefix the seat label, e.g.
#                                             # "Personal (Max 5x)" — opt-in,
#                                             # asks claude-profile once and
#                                             # caches (see --show-profile below)
#           claude-usage --all                # one labelled line per account,
#                                             # across every claude-profile
#                                             # profile/serial account (opt-in
#                                             # bridge; needs the companion
#                                             # claude-profile tool installed —
#                                             # it fetches each account's usage,
#                                             # refreshing parked credentials;
#                                             # honours every render flag, and
#                                             # emits a {account,usage}[] array
#                                             # under --json/--raw)
#           claude-usage --table              # render as a bordered grid with
#                                             # named columns (ACCOUNT/SPEND/7D/
#                                             # <model>/5H), each cell a themed
#                                             # bar + percent + its own reset. A
#                                             # FORMAT, not an account selector:
#                                             # bare = just this account; combine
#                                             # with --all for every account. The
#                                             # $-cap column shows if some account
#                                             # has a cap that's live (credits
#                                             # enabled) OR has real spend — same
#                                             # spend_on gate as pretty mode — so
#                                             # uneven setups still align
#           claude-usage --all --table        # every account, one row each
#           claude-usage --table --no-borders # drop the box-drawing borders
#           claude-usage --table --no-bars    # bare numeric cells, no bars
#                                             # (CLAUDE_USAGE_TABLE_BARS=false)
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
#           CLAUDE_USAGE_BAR_WIDTH cells per bar in --pretty and --table (10)
#           CLAUDE_USAGE_TABLE_BARS default for --bars/--no-bars in --table (true)
#           CLAUDE_USAGE_SEP       metric delimiter, both modes (default: per-mode)
#           CLAUDE_USAGE_TTL       cache max age in seconds before a background
#                                  refresh is triggered (default: 120)
#
# Theming:  a theme is a FULL-CONFIG PRESET — colours/glyphs for the bars
#           (pretty mode) plus optional layout defaults (separators, section/
#           reset prefixes, bar width) that apply to both output modes. Pick
#           one with --theme NAME (or CLAUDE_USAGE_THEME). Bar styles:
#           default / mono / ascii / bright / neon / retro ("[====>....]") /
#           shade ("▓▓▒░░") / dots ("●●◑○○") / spark ("██▅▁▁") / line
#           ("━━╸──"). Truecolor palettes: catppuccin / dracula / nord /
#           gruvbox. Layouts: labelled ("Credit:"/"Plan:"/"Reset" labels) /
#           compact (5-cell bars, no brackets, tight separators). `--themes`
#           previews every one against your live usage. --no-color drops
#           colour from any theme but keeps bars.
#           Explicit values always beat the theme, whatever their source
#           (flag, env var, or config file). Fine-grained overrides layer on
#           top of the chosen theme:
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
# Caching:  stale-while-revalidate, PER ACCOUNT (cache file is keyed by the
#           config dir AND the account's accountUuid from .claude.json, so a
#           serial subscription swap in the same dir — or distinct dirs — never
#           clobber each other, and a swap doesn't serve the old account). Bare
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
typeset -g CLAUDE_USAGE_VERSION="0.5.0"

# Where this file lives, captured at SOURCE time ($0 inside a function is the
# function name, not the script). Used to find a sibling claude-profile clone
# for the opt-in --show-profile bridge.
typeset -g CLAUDE_USAGE_SELF_DIR="${${(%):-%x}:A:h}"

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
  # Key by the account identity, not just the dir: a serial subscription swap
  # (e.g. claude-profile) changes .claude.json's oauthAccount.accountUuid while
  # keeping the SAME dir, so a dir-only cache would serve the previous account's
  # numbers until its TTL lapsed. accountUuid changes on every swap; reading it
  # is ~one small jq. Absent (no login yet) → falls back to the dir-only name,
  # so behavior is unchanged for the single-account case.
  local ddir="${dir/#\~/$HOME}" cj acct suffix=""
  # Claude Code keeps the DEFAULT dir's main config at $HOME/.claude.json; a
  # custom config dir keeps it at <dir>/.claude.json.
  if [[ "$ddir" == "$HOME/.claude" ]]; then
    cj="$HOME/.claude.json"
  else
    cj="$ddir/.claude.json"
  fi
  acct=$(jq -r '.oauthAccount.accountUuid // empty' "$cj" 2>/dev/null)
  [[ -n "$acct" ]] && suffix=".${acct:0:8}"
  print -r -- "${TMPDIR:-/tmp}/claude-oauth-usage.${dir:t}${suffix}.json"
}

# ----------------------------------------------------------------------------
# Internal: resolve this seat's display label ("Personal (Max 5x)") — the
# OPT-IN --show-profile bridge to the companion `claude-profile` juggler.
#   $1 = config dir
# Prints the label (possibly empty) and returns 0; never errors, never writes
# to stderr. "No label" is an ordinary outcome, not a failure: no juggler
# installed, no config file, or a dir no profile claims.
#
# claude-profile owns the STRING — we ask by config dir (not cwd: the
# statusline knows which dir a session belongs to but has no meaningful cwd)
# and render what comes back verbatim. One call, JSON, no parsing of its
# internals.
# ----------------------------------------------------------------------------
_claude_usage_label_resolve() {
  local dir="${1%/}" out
  # rc distinguishes the two empty outcomes: 0 = claude-profile ANSWERED (the
  # label may legitimately be "" — one profile holding one account has nothing
  # to disambiguate, and an unclaimed dir is a stable fact); 1 = we couldn't
  # reach it at all. Only the latter deserves a fast retry.
  out=$(_claude_usage_profile_cmd resolve --json --dir "$dir" 2>/dev/null) || return 1
  [[ -n $out ]] || return 1
  jq -r 'if (.active // false) then (.label // "") else "" end' <<< "$out" 2>/dev/null
  return 0
}

# ----------------------------------------------------------------------------
# Internal: invoke claude-profile, wherever it lives. Mirrors how
# claude-statusline locates THIS script — because the same problem bites here:
# `claude-profile` is a zsh FUNCTION in an interactive shell, and the
# statusline renders in a bare `zsh -c` that sources no zshrc, so the function
# doesn't exist on the very path that needs it most. Order:
#   $CLAUDE_PROFILE_SCRIPT override → function/binary on PATH → sibling clone.
# Prints nothing and returns 1 when claude-profile isn't installed at all.
# ----------------------------------------------------------------------------
_claude_usage_profile_cmd() {
  if [[ -n ${CLAUDE_PROFILE_SCRIPT:-} ]]; then
    [[ -f $CLAUDE_PROFILE_SCRIPT ]] || return 1
    command python3 "$CLAUDE_PROFILE_SCRIPT" "$@"
    return $?
  fi
  if command -v claude-profile >/dev/null 2>&1; then
    claude-profile "$@"
    return $?
  fi
  local sibling="$CLAUDE_USAGE_SELF_DIR/../claude-profile/claude-profile.py"
  [[ -f $sibling ]] || return 1
  command python3 "$sibling" "$@"
}

# Is claude-profile reachable at all? Same three candidates, in the same
# order, so the --all gate and the label lookup can never disagree about
# whether the juggler exists. An explicit $CLAUDE_PROFILE_SCRIPT is
# authoritative: if the user says where it lives and it isn't there, it isn't
# installed — the other candidates aren't consulted (that's also how a test
# suite proves the not-installed path on a machine that has a sibling clone).
_claude_usage_profile_have() {
  if [[ -n ${CLAUDE_PROFILE_SCRIPT:-} ]]; then
    [[ -f $CLAUDE_PROFILE_SCRIPT ]]
    return $?
  fi
  command -v claude-profile >/dev/null 2>&1 && return 0
  [[ -f "$CLAUDE_USAGE_SELF_DIR/../claude-profile/claude-profile.py" ]]
}

# ----------------------------------------------------------------------------
# Internal: cached label lookup. The resolver shells out to python (~100ms) —
# far too slow for a statusline that repaints on every message — so the answer
# is cached in a sidecar next to the usage cache. That filename already embeds
# the config dir AND the first 8 of accountUuid, so a serial account swap
# lands on a different sidecar and invalidates itself for free; the TTL only
# has to cover changes that move neither (a `claude-profile use` toggle, an
# edited path rule).
#   $1 = config dir   $2 = cache path   $3 = 1 when non-blocking (statusline)
# An EMPTY label is cached too — that's what stops a machine without
# claude-profile from paying the probe + fork on every repaint — but on a much
# SHORTER ttl. A miss is the answer we least want to be stuck with: a transient
# one (claude-profile mid-swap, a run with the bridge disabled, a lost race on
# first start) would otherwise hide the label for the full 15 minutes. Cheap
# retries on nothing, long life for a real answer.
# ----------------------------------------------------------------------------
_claude_usage_label_cached() {
  local dir="$1" cache="$2" noblock="${3:-0}"
  local sidecar="$cache.label"
  local ttl="${CLAUDE_USAGE_LABEL_TTL:-900}"
  local ttl_miss="${CLAUDE_USAGE_LABEL_TTL_MISS:-60}"
  local mtime=0 fresh=0
  if [[ -f $sidecar ]]; then
    # Empty file = a failed lookup (short ttl). A file holding the SENTINEL is
    # an answer of "no label" and lives as long as any other answer.
    [[ -s $sidecar ]] || ttl=$ttl_miss
    mtime=$(zstat +mtime "$sidecar" 2>/dev/null) || mtime=0
    (( $(date +%s) - mtime <= ttl )) && fresh=1
    # …but a config edit beats the clock. Renaming a profile or adding a
    # `display` changes neither the dir nor the account, so it moves nothing in
    # the sidecar's cache key and would otherwise sit unnoticed for the full
    # ttl — a baffling 15 minutes of "I changed it, why is it the same?".
    # One zstat, no fork. $CLAUDE_PROFILE_CONFIG is the same knob
    # claude-profile itself honours, so the two can't disagree on the path.
    if (( fresh )); then
      local pcfg="${CLAUDE_PROFILE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-profile/config.json}"
      if [[ -f $pcfg ]]; then
        local cmtime
        cmtime=$(zstat +mtime "$pcfg" 2>/dev/null) || cmtime=0
        (( cmtime > mtime )) && fresh=0
      fi
    fi
  fi
  if (( fresh )); then
    _claude_usage_label_read "$sidecar"
    return 0
  fi
  if (( noblock )); then
    # Statusline: never block on python. Serve the stale label if we have one
    # (a seat's name is stable — a stale name beats a flickering gap), and
    # refresh detached so the next repaint is current.
    ( _claude_usage_label_write "$dir" "$sidecar" & ) >/dev/null 2>&1
    [[ -f $sidecar ]] && _claude_usage_label_read "$sidecar"
    return 0
  fi
  _claude_usage_label_write "$dir" "$sidecar"
}

# The sidecar's "answered, but there is nothing to show" sentinel: a single
# space. Distinguishable from a failed lookup (empty file) by `test -s`, and
# safe because a composed label never carries leading/trailing whitespace.
_claude_usage_label_read() {
  local v="$(<"$1")"
  [[ $v == " " ]] && return 0
  print -r -- "$v"
}

# Resolve and atomically install the sidecar, then print the label.
_claude_usage_label_write() {
  local dir="$1" sidecar="$2" label tmp store rc
  label=$(_claude_usage_label_resolve "$dir"); rc=$?
  tmp="$sidecar.$$"
  # Store the sentinel when claude-profile answered with no label, so that
  # answer keeps the full ttl; a failure stores empty and is retried soon.
  store="$label"
  (( rc == 0 )) && [[ -z $label ]] && store=" "
  print -rn -- "$store" > "$tmp" 2>/dev/null && mv -f "$tmp" "$sidecar" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  print -r -- "$label"
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
# Render a JSON array (NDJSON on stdin) of {account, usage-summary} as an
# aligned, named-column table. Shared by `--table` (single account) and
# `--all --table` (every account). Reads the caller's resolved theme locals
# (clo/cmid/chi/dim/tmid/thi) via zsh dynamic scope. Columns are the UNION
# across accounts; a missing metric is a dim "\u00b7"; padding is computed
# from the uncoloured text so ANSI never skews alignment.
_claude_usage_render_table() {
  # Render {account, usage-summary} NDJSON (stdin) as an aligned, named-column
  # table. Shared by `--table` (single account) and `--all --table` (every
  # account). Uses the caller's resolved theme + toggle locals via zsh dynamic
  # scope. Columns = the UNION across accounts; a missing metric is a dim
  # dot; each cell carries its own reset countdown (dimmed, --reset-prefix
  # label) just like the bars, gated by --show-limit-resets / --show-reset /
  # --show-spend-reset. Box borders by default (--no-borders drops them).
  # Padding is computed from the UNCOLOURED text so ANSI never skews alignment.
  jq -s -r \
    --arg clo "$clo" --arg cmid "$cmid" --arg chi "$chi" --arg dim "$dim" \
    --argjson tmid "$tmid" --argjson thi "$thi" \
    --argjson showlr "$show_limit_resets" --argjson showreset "$show_reset" \
    --argjson showspendreset "$show_spend_reset" \
    --arg rpfx "$reset_prefix" --arg spendreset "$spend_reset" \
    --argjson borders "$borders" \
    --arg gfull "$gfull" --arg gpartial "$gpartial" --arg gempty "$gempty" \
    --arg lbr "$lbr" --arg rbr "$rbr" --argjson bw "$bar_width" \
    --argjson bars "$table_bars" '
    def paint($c; $s): if ($c | length) > 0 then "[\($c)m\($s)[0m" else $s end;
    def colf($p): if $p == null then $dim elif $p >= $thi then $chi elif $p >= $tmid then $cmid else $clo end;
    # Theme-glyph progress bar, identical geometry to the pretty/statusline
    # renderer (full + fractional-ramp partial + empty cells over $bw columns),
    # framed by the theme brackets. Every glyph is one display column, so the
    # rendered string length feeds the plain-width padding math unchanged.
    def mkbar($p):
      (if $p < 0 then 0 elif $p > 100 then 100 else $p end) as $pct
      | ($pct / 100 * $bw * 8) as $units
      | (($units / 8) | floor) as $full
      | (($units - ($full * 8)) | floor) as $partial
      | ([$full, $bw] | min) as $fc
      | ($gpartial | length) as $pn
      | (($fc < $bw) and ($partial >= 1) and ($pn > 0)) as $hasp
      | (if $hasp then (($partial * $pn / 8) | floor) else 0 end) as $pidx
      | ($fc + (if $hasp then 1 else 0 end)) as $used
      | (($gfull * $fc) // "")
        + (if $hasp then ($gpartial | .[$pidx:($pidx + 1)]) else "" end)
        + (($gempty * ($bw - $used)) // "");
    def barof($p): if $bars then "\($lbr)\(mkbar($p))\($rbr) " else "" end;
    def d2: (. * 100 | round / 100);
    def dropzeros: tostring | if test("\\.[0-9]+$") then sub("0+$"; "") | sub("\\.$"; "") else . end;
    def pad($n): if $n > 0 then " " * $n else "" end;
    def left($r):
      if ($r == null) then ""
      else (try (($r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) - now | floor) catch -1) as $rem
        | if $rem <= 0 then ""
          else (($rem/86400)|floor) as $dd | ((($rem%86400)/3600)|floor) as $h | ((($rem%3600)/60)|floor) as $m
             | if $dd>0 then "\($dd)d\($h)h" elif $h>0 then "\($h)h\($m)m" else "\($m)m" end
          end
      end;
    def rsuf($show; $cd): if ($show and (($cd // "") != "")) then {p: " \($rpfx)\($cd)", r: (" " + paint($dim; "\($rpfx)\($cd)"))} else {p:"", r:""} end;
    # Matches the pretty spend_on gate: a limit is present AND the cap is either
    # live (credits enabled) OR carries real recorded spend. A dormant, never-used
    # disabled cap ($0, toggle off) is suppressed here just as pretty omits it, so
    # the two renderers agree; a toggled-off cap with accrued spend still shows.
    def spendlive: (.usage != null) and ((.usage.spend.limit // null) != null)
                   and (((.usage.spend.enabled // false) == true) or ((.usage.spend.spent // 0) > 0));
    map({
      account: .account,
      spend: (if spendlive
              then "$\(.usage.spend.spent|d2|dropzeros)/$\(.usage.spend.limit|d2|dropzeros)" else null end),
      spend_pct: (if spendlive then (.usage.spend.percent // 0) else null end),
      m: (if .usage == null then {} else
            reduce ((.usage.limits // [])[]) as $l ({};
              .[ (if $l.kind=="weekly_all" then "7d"
                  elif $l.kind=="session" then "5h"
                  elif $l.kind=="weekly_scoped" then ("m:" + ($l.label // "scoped"))
                  else ($l.label // $l.kind) end) ] = {pct: $l.percent, resets: $l.resets_at})
          end)
    }) as $R
    | (([ $R[] | select(.spend != null) ] | length) > 0) as $hasSpend
    | ([ $R[] | .m | keys[] | select(startswith("m:")) ]
        | reduce .[] as $k ([]; if any(.[]; . == $k) then . else . + [$k] end)) as $models
    | (any($R[]; .m["7d"] != null)) as $has7d
    | (any($R[]; .m["5h"] != null)) as $has5h
    | ([ {k:"account", name:"ACCOUNT"} ]
       + (if $hasSpend then [ {k:"spend", name:"SPEND"} ] else [] end)
       + (if $has7d then [ {k:"7d", name:"7D"} ] else [] end)
       + [ $models[] | {k:., name:(.[2:] | ascii_upcase)} ]
       + (if $has5h then [ {k:"5h", name:"5H"} ] else [] end)) as $cols
    | ($R | map(. as $r | { cells: [ $cols[] | . as $c |
        if $c.k == "account" then {plain:$r.account, rich:$r.account}
        elif $c.k == "spend" then
          (if $r.spend == null then {plain:"·", rich: paint($dim; "·")}
           else (rsuf($showspendreset; $spendreset)) as $rs
                | (barof($r.spend_pct)) as $b
                | {plain: ($b + $r.spend + $rs.p), rich: (paint(colf($r.spend_pct); $b + $r.spend) + $rs.r)} end)
        else ($r.m[$c.k]) as $cell |
          (if $cell == null or $cell.pct == null then {plain:"·", rich: paint($dim; "·")}
           else (left($cell.resets)) as $cd
              | (if $c.k == "5h" then rsuf($showreset; $cd) else rsuf($showlr; $cd) end) as $rs
              | (barof($cell.pct)) as $b
              | ("\($cell.pct|round)%") as $pv
              | {plain: ($b + $pv + $rs.p), rich: (paint(colf($cell.pct); $b + $pv) + $rs.r)} end)
        end ] })) as $M
    | [ range(0; ($cols|length)) as $i | ([ ($cols[$i].name|length) ] + [ $M[] | .cells[$i].plain | length ] | max) ] as $W
    | (($cols | length)) as $nc
    | def cellstr($cells; $i): ($cells[$i]) as $x | ($x.rich + pad($W[$i] - ($x.plain|length)));
      def hbar($l; $m; $rr): paint($dim; $l + ([ $W[] | ("─" * (. + 2)) ] | join($m)) + $rr);
      def rowstr($cells): paint($dim; "│") + ([ range(0; $nc) as $i | " " + cellstr($cells; $i) + " " ] | join(paint($dim; "│"))) + paint($dim; "│");
      ([ $cols[] | {plain: .name, rich: paint($dim; .name)} ]) as $hdr |
      if ($borders == 1) then
        ( hbar("┌"; "┬"; "┐"),
          rowstr($hdr),
          hbar("├"; "┼"; "┤"),
          ( $M[] | rowstr(.cells) ),
          hbar("└"; "┴"; "┘") )
      else
        ( ( [ range(0; $nc) as $i | cellstr($hdr; $i) ] | join("  ") ),
          ( $M[] | [ range(0; $nc) as $i | cellstr(.cells; $i) ] | join("  ") ) )
      end
  '
}
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
  # --all: render every claude-profile account (opt-in bridge, see below).
  # --cache-file: internal — render a specific JSON file, skipping fetch/cache
  # (how --all feeds each account's raw response back through the renderer).
  # --label: render this exact seat label instead of asking claude-profile.
  # How --all hands each child render its account's label (the child sees a
  # --cache-file belonging to a DIFFERENT account, so it must not resolve one
  # itself); doubles as the manual escape hatch for anyone without the juggler.
  local allmode=0 table=0 borders=1 cache_file_override="" label_override=""
  # Theme-glyph progress bars inside --table cells (on by default). --no-bars
  # (or CLAUDE_USAGE_TABLE_BARS=false) falls back to the bare numeric grid.
  local table_bars="${CLAUDE_USAGE_TABLE_BARS:-true}"
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
  # Seat label ("Personal (Max 5x)") in front of the bars — which subscription
  # am I burning? OPT-IN and default FALSE: it's the one feature that shells
  # out to another tool, and with it off claude-profile is never invoked and
  # the output is byte-identical to a build without this code.
  local show_profile="${CLAUDE_USAGE_SHOW_PROFILE:-false}"
  # Prefix put before EVERY window countdown (trailing 5h one included), so
  # all resets render in one style. Default "" (compact: "14m", "3d21h");
  # e.g. --reset-prefix "Reset " labels them all.
  # The *_set flags record an explicit choice (env/config/flag) — themes only
  # fill fields the user hasn't set.
  local reset_prefix="${CLAUDE_USAGE_RESET_PREFIX-}" rpfx_set=0
  [[ -n ${CLAUDE_USAGE_RESET_PREFIX+x} ]] && rpfx_set=1
  # Section prefixes: text inserted before the dollar group and before the
  # plan-limit group (e.g. "Spend: " / "Limits: "). Default "" — no labels.
  # Include your own trailing space; dimmed in pretty mode.
  local spend_prefix="${CLAUDE_USAGE_SPEND_PREFIX-}" sppfx_set=0
  [[ -n ${CLAUDE_USAGE_SPEND_PREFIX+x} ]] && sppfx_set=1
  local limits_prefix="${CLAUDE_USAGE_LIMITS_PREFIX-}" limpfx_set=0
  [[ -n ${CLAUDE_USAGE_LIMITS_PREFIX+x} ]] && limpfx_set=1
  local divisor="${CLAUDE_USAGE_DIVISOR:-1}"
  local bar_width="${CLAUDE_USAGE_BAR_WIDTH:-10}" bw_set=0
  [[ -n ${CLAUDE_USAGE_BAR_WIDTH+x} ]] && bw_set=1
  # Separator between metrics. Empty → per-mode default (" | " text, " · " pretty).
  local sep_override="${CLAUDE_USAGE_SEP-}" sep_set=0
  [[ -n ${CLAUDE_USAGE_SEP+x} ]] && sep_set=1
  # Group separator between the dollar segments (spend cap / balance — the
  # credits system) and the plan-limit bars (a different mechanism). Defaults
  # " || " text, " | " pretty (dimmed).
  local gsep_override="${CLAUDE_USAGE_GROUP_SEP-}" gsep_set=0
  [[ -n ${CLAUDE_USAGE_GROUP_SEP+x} ]] && gsep_set=1
  # Separator between the seat label and the first metric. Defaults to the
  # resolved METRIC separator ("·" pretty, "|" text): a bare space made the
  # label read as part of the first metric rather than as its own thing.
  local lsep_override="${CLAUDE_USAGE_LABEL_SEP-}" lsep_set=0
  [[ -n ${CLAUDE_USAGE_LABEL_SEP+x} ]] && lsep_set=1
  # Theme (pretty mode): --theme > CLAUDE_USAGE_THEME > "default". --no-color
  # forces all colour off regardless of theme (keeps the bars, unlike --text-only).
  local theme_override="" nocolor=0
  # Canonical theme list — used by --list-themes, --themes, and the
  # unknown-theme error. Keep in sync with the case table below.
  local -a all_themes=(default mono ascii bright neon labelled catppuccin \
                       compact retro shade dots spark line dracula nord gruvbox)

  # Account dir: --dir > CLAUDE_USAGE_DIR > CLAUDE_CONFIG_DIR > ~/.claude.
  # The single-account core stays profile-agnostic: no coupling to
  # claude-profile or any cwd-override convention — callers wanting another
  # seat pass --dir. The one bridge is the OPT-IN --all mode below, which only
  # engages when claude-profile is installed and the user asks for it.
  local dir="${CLAUDE_USAGE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"

  # Snapshot the raw argv before the parse loop consumes it, so --all can
  # forward every flag (theme, mode, prefixes, …) to each per-account render.
  local -a _argv=("$@")

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
      --show-profile)     show_profile=true ;;
      --show-profile=*)
        show_profile="${1#--show-profile=}"
        [[ $show_profile == (true|false) ]] || { print -u2 "claude-usage: --show-profile takes true or false"; return 1 } ;;
      --show-limit-resets) show_limit_resets=true ;;
      --show-limit-resets=*)
        show_limit_resets="${1#--show-limit-resets=}"
        [[ $show_limit_resets == (true|false) ]] || { print -u2 "claude-usage: --show-limit-resets takes true or false"; return 1 } ;;
      --reset-prefix)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --reset-prefix requires a value"; return 1 }
        reset_prefix="$2"; rpfx_set=1; shift ;;
      --reset-prefix=*) reset_prefix="${1#--reset-prefix=}"; rpfx_set=1 ;;
      --spend-prefix)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --spend-prefix requires a value"; return 1 }
        spend_prefix="$2"; sppfx_set=1; shift ;;
      --spend-prefix=*) spend_prefix="${1#--spend-prefix=}"; sppfx_set=1 ;;
      --limits-prefix)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --limits-prefix requires a value"; return 1 }
        limits_prefix="$2"; limpfx_set=1; shift ;;
      --limits-prefix=*) limits_prefix="${1#--limits-prefix=}"; limpfx_set=1 ;;
      --sep)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --sep requires a value"; return 1 }
        sep_override="$2"; sep_set=1; shift ;;
      --sep=*)    sep_override="${1#--sep=}"; sep_set=1 ;;
      --group-sep)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --group-sep requires a value"; return 1 }
        gsep_override="$2"; gsep_set=1; shift ;;
      --group-sep=*) gsep_override="${1#--group-sep=}"; gsep_set=1 ;;
      --label-sep)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --label-sep requires a value"; return 1 }
        lsep_override="$2"; lsep_set=1; shift ;;
      --label-sep=*) lsep_override="${1#--label-sep=}"; lsep_set=1 ;;
      --theme)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --theme requires a name"; return 1 }
        theme_override="$2"; shift ;;
      --theme=*)  theme_override="${1#--theme=}" ;;
      --no-color|--no-colour) nocolor=1 ;;
      --list-themes) print "${(j: :)all_themes}"; return 0 ;;
      --themes|--preview-themes) mode=themes ;;
      --all|--all-accounts|--all-profiles) allmode=1 ;;
      --table) table=1 ;;
      --no-borders|--no-border) borders=0 ;;
      --bars|--table-bars) table_bars=true ;;
      --no-bars|--no-table-bars) table_bars=false ;;
      --bars=*|--table-bars=*)
        table_bars="${1#*=}"
        [[ $table_bars == (true|false) ]] || { print -u2 "claude-usage: --bars takes true or false"; return 1 } ;;
      --cache-file)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --cache-file requires a path"; return 1 }
        cache_file_override="$2"; shift ;;
      --cache-file=*) cache_file_override="${1#--cache-file=}" ;;
      --label)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --label requires a value"; return 1 }
        label_override="$2"; shift ;;
      --label=*)  label_override="${1#--label=}" ;;
      --version|-V) print "claude-usage $CLAUDE_USAGE_VERSION"; return 0 ;;
      --fresh)      force=1 ;;
      --no-block)   noblock=1 ;;
      --dir)
        [[ -n "$2" ]] || { print -u2 "claude-usage: --dir requires a path"; return 1 }
        dir="$2"; shift ;;
      --dir=*)    dir="${1#--dir=}" ;;
      -h|--help)
        print "usage: claude-usage [--dir PATH|--all] [--table] [--no-borders] [--no-bars] [--pretty|--text-only|--json|--raw] [--theme NAME|--themes|--no-color] [--show-reset=true|false] [--show-spend=true|false] [--show-balance=true|false] [--show-spend-reset=true|false] [--show-limit-resets=true|false] [--show-profile=true|false] [--reset-prefix STR] [--spend-prefix STR] [--limits-prefix STR] [--sep STR] [--group-sep STR] [--label-sep STR] [--fresh|--no-block] [--version]"
        print "themes: ${(j: :)all_themes}  (--list-themes to script it, --themes to preview)"
        return 0 ;;
      *)
        print -u2 "usage: claude-usage [--dir PATH|--all] [--table] [--no-borders] [--no-bars] [--pretty|--text-only|--json|--raw] [--theme NAME|--themes|--no-color] [--show-reset=true|false] [--show-spend=true|false] [--show-balance=true|false] [--show-spend-reset=true|false] [--show-limit-resets=true|false] [--show-profile=true|false] [--reset-prefix STR] [--spend-prefix STR] [--limits-prefix STR] [--sep STR] [--group-sep STR] [--label-sep STR] [--fresh|--no-block]"
        return 1 ;;
    esac
    shift
  done
  dir="${dir%/}"
  # Env-sourced toggles could hold garbage → they feed jq --argjson, sanitize.
  [[ $show_spend        == (true|false) ]] || show_spend=true
  [[ $show_balance      == (true|false) ]] || show_balance=true
  [[ $show_limit_resets == (true|false) ]] || show_limit_resets=true
  [[ $show_profile      == (true|false) ]] || show_profile=false

  # ---- --themes: preview — render the current usage once per theme ---------
  if [[ $mode == themes ]]; then
    local _t _first=1
    for _t in "${all_themes[@]}"; do
      (( _first )) && _first=0 || print    # blank line between examples
      printf '%-11s ' "$_t"
      claude-usage --dir "$dir" --theme "$_t"
    done
    return 0
  fi

  # ---- Theme resolution (pretty mode) ---------------------------------------
  # A theme is: 3 colours (low/mid/high fill) + 2 thresholds + 3 bar glyphs
  # (full / partial-ramp / empty) + 2 brackets + a dim SGR for separators.
  # Colours/dim are raw SGR params ("32", "92", "38;5;196", or "" = no colour).
  # gpartial is a low→high ramp of fractional-cell glyphs ("" = no partial cell).
  local theme="${theme_override:-${CLAUDE_USAGE_THEME:-default}}"
  local clo cmid chi tmid thi gfull gpartial gempty lbr rbr dim _a _b
  # Themes may also preset LAYOUT config (separators, prefixes, bar width) —
  # a theme is a full-config preset, not just colours. Empty = keep the
  # standard default; an explicit --flag/env/config value always beats the
  # theme (the *_set flags gate the application below).
  local tsep='' tgsep='' trpfx='' tsppfx='' tlimpfx='' twidth=''
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
    labelled)      # default look + section/reset labels ("Credit: … | Plan: …")
      clo=32 cmid=33 chi=31; tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'; dim=2
      trpfx='Reset ' tsppfx='Credit: ' tlimpfx='Plan: ' ;;
    catppuccin)    # truecolor Catppuccin Mocha (the README screenshot palette)
      clo='38;2;166;227;161' cmid='38;2;249;226;175' chi='38;2;243;139;168'
      tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'
      dim='38;2;147;153;178' ;;
    compact)       # tightest statusline fit: 5-cell bars, no brackets,
                   # single-space separators
      clo=32 cmid=33 chi=31; tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='' rbr=''; dim=2
      tsep=' ' tgsep=' | ' twidth=5 ;;
    retro)         # arcade loading bar "[====>....]" in CRT phosphor:
                   # green tube → amber warning → alarm red, greenish dim
      clo='38;5;40' cmid='38;5;214' chi='38;5;196'; tmid=70 thi=90
      gfull='=' gpartial='>' gempty='.'; lbr='[' rbr=']'; dim='38;5;65' ;;
    shade)         # DOS shade blocks "▓▓▓▒░░░" on ice: cyan → gold → salmon,
                   # slate dim
      clo='38;5;81' cmid='38;5;221' chi='38;5;203'; tmid=70 thi=90
      gfull='▓' gpartial='░▒' gempty='░'; lbr='▕' rbr='▏'; dim='38;5;60' ;;
    dots)          # dot meter "●●◑○○" in candy pastels: mint → peach →
                   # hot pink, lavender dim (5 wide — dots read better short)
      clo='38;5;114' cmid='38;5;216' chi='38;5;205'; tmid=70 thi=90
      gfull='●' gpartial='◔◑◕' gempty='○'; lbr=' ' rbr=' '; dim='38;5;103'
      twidth=5 ;;
    spark)         # sparkline ramp "██▅▁▁▁", electric: cyan → orange →
                   # hot red, storm-blue dim
      clo='38;5;45' cmid='38;5;214' chi='38;5;197'; tmid=70 thi=90
      gfull='█' gpartial='▁▂▃▄▅▆▇' gempty='▁'; lbr='' rbr=''; dim='38;5;66' ;;
    line)          # slim gauge "━━━╸────", understated: periwinkle → gold →
                   # rose, grey-violet dim
      clo='38;5;147' cmid='38;5;179' chi='38;5;168'; tmid=70 thi=90
      gfull='━' gpartial='╸' gempty='─'; lbr='' rbr=''; dim='38;5;102' ;;
    dracula)       # truecolor Dracula palette
      clo='38;2;80;250;123' cmid='38;2;241;250;140' chi='38;2;255;85;85'
      tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'
      dim='38;2;98;114;164' ;;
    nord)          # truecolor Nord palette
      clo='38;2;163;190;140' cmid='38;2;235;203;139' chi='38;2;191;97;110'
      tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'
      dim='38;2;76;86;106' ;;
    gruvbox)       # truecolor Gruvbox palette
      clo='38;2;184;187;38' cmid='38;2;250;189;47' chi='38;2;251;73;52'
      tmid=70 thi=90
      gfull='█' gpartial='▏▎▍▌▋▊▉' gempty='░'; lbr='▕' rbr='▏'
      dim='38;2;146;131;116' ;;
    *)
      print -u2 "claude-usage: unknown theme '$theme' (valid: ${(j: :)all_themes})"
      return 1 ;;
  esac

  # Apply the theme's layout presets to anything not explicitly set
  (( sep_set ))    || { [[ -n $tsep  ]] && { sep_override="$tsep";  sep_set=1;  } }
  (( gsep_set ))   || { [[ -n $tgsep ]] && { gsep_override="$tgsep"; gsep_set=1; } }
  (( rpfx_set ))   || reset_prefix="$trpfx"
  (( sppfx_set ))  || spend_prefix="$tsppfx"
  (( limpfx_set )) || limits_prefix="$tlimpfx"
  (( bw_set ))     || { [[ -n $twidth ]] && bar_width="$twidth" }

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

  # Monthly spend-cap reset label ("" = don't show). Derived, not from the API:
  # usage credits reset on the 1st of the next calendar month. Computed here
  # (before the --all/--table block) so the table can label the $-cap column.
  local spend_reset=""
  if [[ $show_spend_reset == true ]]; then
    local -a _mn=(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
    spend_reset="${_mn[$(( 10#$(date +%m) % 12 + 1 ))]} 1"
  fi

  # ---- --all / --table: multi-account views via claude-profile --------------
  # Opt-in bridge to the companion `claude-profile` juggler: it owns the
  # credentials (incl. PARKED serial accounts it can token-refresh) and hands
  # back each account's usage; we own presentation. It emits "<account>\t<json>"
  # per line (empty = unavailable). Placed AFTER theme resolution so --table can
  # colour cells with the resolved palette.
  #   --all   : one line per account, each rendered through THIS renderer via
  #             --cache-file (recursion, so every theme/flag applies). --json/
  #             --raw emit a valid [{account,usage}] array instead.
  #   --table : accounts as rows in aligned, NAMED columns (bar + percent per
  #             window). The $-spend column appears only when some account has a
  #             cap that's live (credits enabled) OR carries real spend — the
  #             pretty spend_on gate — which is exactly the raggedness a table fixes.
  if (( allmode )); then
    _claude_usage_profile_have || {
      print -u2 "claude-usage: --all needs the companion 'claude-profile' tool (not found)"
      return 1
    }
    # Forward every flag EXCEPT the multi-account toggles to each child render.
    local -a _fwd; local _arg
    for _arg in "${_argv[@]}"; do
      [[ $_arg == (--all|--all-accounts|--all-profiles|--table) ]] && continue
      _fwd+=("$_arg")
    done
    local _nd
    _nd="$(_claude_usage_profile_cmd usage-json --all 2>/dev/null)"
    [[ -n $_nd ]] || { print -u2 "claude-usage: claude-profile reported no accounts"; return 1 }
    local -a _lines=("${(@f)_nd}")
    local _l _name _json _tmpf

    # With --show-profile, each row is named by its seat label ("Personal
    # (Max 20x)") rather than the bare account key. ONE extra call buys the
    # whole account→label map — the same `resolve --json` contract, with
    # --accounts. An older claude-profile without it just yields nothing here
    # and every row keeps its account name.
    local -A _labels
    if [[ $show_profile == true ]]; then
      local _map _ml
      _map="$(_claude_usage_profile_cmd resolve --json --accounts 2>/dev/null \
              | jq -r 'if (.active // false) then ((.accounts // [])[] | "\(.name)\t\(.label)") else empty end' 2>/dev/null)"
      for _ml in "${(@f)_map}"; do
        [[ -n $_ml && $_ml == *$'\t'* ]] || continue
        _labels[${_ml%%$'\t'*}]="${_ml#*$'\t'}"
      done
    fi

    if (( table )) || [[ $mode == (json|raw) ]]; then
      # Collect structured {account, usage}. --table needs the --json SUMMARY
      # per account (regardless of the caller's mode); json/raw pass through.
      local _child; local -a _items
      for _l in "${_lines[@]}"; do
        [[ -n $_l ]] || continue
        _name="${_l%%$'\t'*}"; _json="${_l#*$'\t'}"
        _child=null
        if [[ -n $_json ]]; then
          _tmpf="$(mktemp "${TMPDIR:-/tmp}/claude-usage-all.XXXXXX")"
          print -r -- "$_json" > "$_tmpf"
          if (( table )); then
            _child="$(claude-usage --cache-file "$_tmpf" "${_fwd[@]}" --json)"
          else
            _child="$(claude-usage --cache-file "$_tmpf" "${_fwd[@]}")"
          fi
          rm -f "$_tmpf"
        fi
        # --table renders the `account` field, so the label takes its place
        # there; --json keeps the raw account key stable for scripts and adds
        # `label` alongside it (only when the feature is on).
        if (( table )); then
          _items+=("$(jq -n --arg n "${_labels[$_name]:-$_name}" --argjson u "${_child:-null}" \
                        '{account:$n, usage:$u}')")
        else
          _items+=("$(jq -n --arg n "$_name" --arg lbl "${_labels[$_name]:-}" \
                        --argjson u "${_child:-null}" \
                        '{account:$n} + (if $lbl != "" then {label:$lbl} else {} end) + {usage:$u}')")
        fi
      done
      if (( ! table )); then
        printf '%s\n' "${_items[@]}" | jq -s '.'
        return 0
      fi
      # ---- Table renderer: union of columns across accounts, aligned on the
      # VISIBLE width (padding computed from the uncoloured cell text, so ANSI
      # never skews the columns). Cells are per-window percents tinted by the
      # same thresholds as the bars; a missing metric is a dim "·".
      printf '%s\n' "${_items[@]}" | _claude_usage_render_table
      return 0
    fi

    # Default --all: one labelled, fully-rendered line per account. The line's
    # own prefix column IS the label here, so the child render must not add a
    # second one — it can't anyway, since --cache-file suppresses resolution.
    local _w=0 _rowname
    for _l in "${_lines[@]}"; do
      _name="${_l%%$'\t'*}"; _rowname="${_labels[$_name]:-$_name}"
      (( ${#_rowname} > _w )) && _w=${#_rowname}
    done
    for _l in "${_lines[@]}"; do
      [[ -n $_l ]] || continue
      _name="${_l%%$'\t'*}"; _json="${_l#*$'\t'}"
      printf '%-*s  ' "$_w" "${_labels[$_name]:-$_name}"
      if [[ -z $_json ]]; then
        print -r -- "(usage unavailable)"
      else
        _tmpf="$(mktemp "${TMPDIR:-/tmp}/claude-usage-all.XXXXXX")"
        print -r -- "$_json" > "$_tmpf"
        claude-usage --cache-file "$_tmpf" "${_fwd[@]}"
        rm -f "$_tmpf"
      fi
    done
    return 0
  fi

  # --cache-file (from --all): render this exact JSON file, no fetch/cache.
  local cache
  if [[ -n $cache_file_override ]]; then
    cache="$cache_file_override"
    [[ -f $cache ]] || { print -u2 "claude-usage: cache file not found: $cache"; return 1 }
  else
    cache=$(_claude_usage_cache_path "$dir")
  fi

  if [[ -z $cache_file_override ]] && { (( force )) || [[ ! -f $cache ]] }; then
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
  elif [[ -z $cache_file_override ]]; then
    # Warm path: serve cache instantly; revalidate behind the scenes if stale.
    # The ( ... & ) subshell detaches from job control: no [1] 12345 noise.
    local mtime
    mtime=$(zstat +mtime "$cache" 2>/dev/null) || mtime=0
    if (( $(date +%s) - mtime > ttl )); then
      ( _claude_usage_refresh 0 "$dir" & ) >/dev/null 2>&1
    fi
  fi


  # Metric separator: an explicit --sep / CLAUDE_USAGE_SEP wins for both modes;
  # otherwise each mode keeps its own default (" | " plain, " · " dimmed).
  local text_sep pretty_sep
  if (( sep_set )); then text_sep="$sep_override"; pretty_sep="$sep_override"
  else text_sep=" | "; pretty_sep=" · "; fi
  local text_gsep pretty_gsep
  if (( gsep_set )); then text_gsep="$gsep_override"; pretty_gsep="$gsep_override"
  else text_gsep=" || "; pretty_gsep=" | "; fi

  # ---- Seat label (opt-in): "Personal (Max 5x)" ahead of the bars ----------
  # Which subscription am I burning? Resolved from claude-profile, cached in a
  # sidecar so a repainting statusline pays nothing (see _claude_usage_label_*).
  # An explicit --label wins and skips the lookup entirely; a --cache-file
  # render never resolves one, because the JSON it was handed belongs to some
  # OTHER account (that path is --all, which passes --label per child).
  local label=""
  if [[ -n $label_override ]]; then
    label="$label_override"
  elif [[ $show_profile == true && -z $cache_file_override ]]; then
    label=$(_claude_usage_label_cached "$dir" "$cache" "$noblock")
  fi

  # ---- --table (single account): one row, same named-column grid as --all ---
  # `--table` is a FORMAT, orthogonal to account selection: bare it renders just
  # this account (labelled by its config-dir basename); `--all --table` renders
  # every account (handled in the --all block above). Reuses the shared table
  # renderer via the account's own --json summary.
  if (( table )); then
    local _sum _lbl
    _sum="$(claude-usage --cache-file "$cache" --json)"
    [[ -n $_sum ]] || _sum=null
    # The seat label names the account better than the dir basename ever could
    # ("Personal (Max 5x)" vs "claude-personal"), so it wins the ACCOUNT cell.
    _lbl="${dir:t}"; _lbl="${_lbl#.}"                 # "~/.claude" → "claude"
    [[ -n $label ]] && _lbl="$label"
    jq -n --arg n "$_lbl" --argjson u "$_sum" '{account:$n, usage:$u}' \
      | _claude_usage_render_table
    return 0
  fi

  # Rendered form of the label: plain in --text-only, dimmed in --pretty (it
  # identifies the seat, it isn't a metric). The trailing separator defaults to
  # the metric one and is dimmed together with the label, so the two read as a
  # single quiet prefix. Empty label → empty prefix → byte-identical output to
  # a build without it.
  local text_lblpfx="" pretty_lblpfx=""
  if [[ -n $label ]]; then
    local _tls _pls
    if (( lsep_set )); then _tls="$lsep_override"; _pls="$lsep_override"
    else _tls="$text_sep"; _pls="$pretty_sep"; fi
    text_lblpfx="${label}${_tls}"
    if [[ -n $dim ]]; then pretty_lblpfx=$'\e['"${dim}m${label}${_pls}"$'\e[0m'
    else pretty_lblpfx="${label}${_pls}" ; fi
  fi

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
            --arg gsep "$text_gsep" --arg lblpfx "$text_lblpfx" '
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
        # Should the dollar cap show? Live (credits enabled) OR carrying real
        # recorded usage — a toggled-off cap still leaves accrued spend worth
        # surfacing; only a dormant, never-used cap ($0, toggle off) stays hidden.
        def spend_on:
          if .spend != null then ((.spend.enabled // false) or ((.spend.used | money) > 0))
          else ((.extra_usage.is_enabled // false) or ((.extra_usage.used_credits // 0) > 0)) end;
        # Purchased-credit balance segment ("" until the API reports one — the
        # field exists in the schema but is null-so-far server-side)
        def balance_line:
          (.spend.balance // null) as $b
          | if $b == null then "" else "bal $\($b | money | fmt2)" end;

        # Seat label from claude-profile; "" when off (see the pretty renderer).
        $lblpfx + (
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
            --arg lbr "$lbr" --arg rbr "$rbr" --arg dim "$dim" \
            --arg lblpfx "$pretty_lblpfx" '
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
        # Should the dollar cap show? Yes when it is live (credits enabled) OR
        # when it carries real recorded usage — a toggled-off cap still leaves
        # accrued spend worth surfacing (e.g. $127.36 against a $100 cap). Only
        # a dormant, never-used cap ($0 spent, toggle off) stays hidden.
        def spend_on:
          if .spend != null then ((.spend.enabled // false) or ((.spend.used | money) > 0))
          else ((.extra_usage.is_enabled // false) or ((.extra_usage.used_credits // 0) > 0)) end;
        # Purchased-credit balance segment, dimmed — no percent, so no bar
        # ("" until the API reports one; the field is null-so-far server-side)
        def balance_seg:
          (.spend.balance // null) as $b
          | if $b == null then "" else paint($dim; "bal $\($b | money | fmt2)") end;

        # Optional section prefix, dimmed; "" stays "" (no stray SGR bytes)
        def secpfx($p): if $p != "" then paint($dim; $p) else "" end;

        # $lblpfx: the seat label from claude-profile ("Personal (Max 5x) "),
        # already dimmed and space-terminated by the caller; "" when the
        # feature is off — so the rendered line is byte-identical to before.
        $lblpfx + (
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
