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
#           claude-usage --sep ' / '          # custom metric delimiter (both modes)
#           claude-usage --dir PATH           # another account's Claude config dir
#           claude-usage --json               # machine-readable summary
#           claude-usage --raw                # full untouched endpoint response
#           claude-usage --fresh              # blocking refresh, guaranteed current
#           claude-usage --no-block           # statusline mode: never blocks,
#                                             # prints nothing on cold/broken state
#           (the claude-statusline companion project renders this in a
#            Claude Code status line, with per-segment toggles)
#
# Env:      CLAUDE_USAGE_DIR       default config dir (default: ~/.claude)
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
#           Default (--pretty), Max/Pro:  "7d▕██░░▏40% · opus▕███░▏63% · 5h▕█░░░░▏12% Reset 4h45m"
#           --text-only, Max/Pro:         "7d 40% | opus 63% | 5h 12% Reset 4h45m"
#           Both order 5h last (next to Reset). --show-reset (default true)
#           appends the 5h-session countdown; --sep / CLAUDE_USAGE_SEP overrides
#           the delimiter for both modes.
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
  local ttl="${CLAUDE_USAGE_TTL:-120}" mode=pretty force=0 noblock=0 show_reset=true
  local divisor="${CLAUDE_USAGE_DIVISOR:-1}"
  local bar_width="${CLAUDE_USAGE_BAR_WIDTH:-10}"
  # Separator between metrics. Empty → per-mode default (" | " text, " · " pretty).
  local sep_override="${CLAUDE_USAGE_SEP-}" sep_set=0
  [[ -n ${CLAUDE_USAGE_SEP+x} ]] && sep_set=1
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
      --sep)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --sep requires a value"; return 1 }
        sep_override="$2"; sep_set=1; shift ;;
      --sep=*)    sep_override="${1#--sep=}"; sep_set=1 ;;
      --theme)
        [[ -n "${2+x}" ]] || { print -u2 "claude-usage: --theme requires a name"; return 1 }
        theme_override="$2"; shift ;;
      --theme=*)  theme_override="${1#--theme=}" ;;
      --no-color|--no-colour) nocolor=1 ;;
      --list-themes) print "default mono ascii bright neon"; return 0 ;;
      --fresh)      force=1 ;;
      --no-block)   noblock=1 ;;
      --dir)
        [[ -n "$2" ]] || { print -u2 "claude-usage: --dir requires a path"; return 1 }
        dir="$2"; shift ;;
      --dir=*)    dir="${1#--dir=}" ;;
      -h|--help)
        print "usage: claude-usage [--dir PATH] [--pretty|--text-only|--json|--raw] [--theme NAME|--no-color] [--show-reset=true|false] [--sep STR] [--fresh|--no-block]"
        print "themes: default mono ascii bright neon  (also --list-themes)"
        return 0 ;;
      *)
        print -u2 "usage: claude-usage [--dir PATH] [--pretty|--text-only|--json|--raw] [--theme NAME|--no-color] [--show-reset=true|false] [--sep STR] [--fresh|--no-block]"
        return 1 ;;
    esac
    shift
  done
  dir="${dir%/}"

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
  (( nocolor )) && { clo='' cmid='' chi='' dim=''; }

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

  # Metric separator: an explicit --sep / CLAUDE_USAGE_SEP wins for both modes;
  # otherwise each mode keeps its own default (" | " plain, " · " dimmed).
  local text_sep pretty_sep
  if (( sep_set )); then text_sep="$sep_override"; pretty_sep="$sep_override"
  else text_sep=" | "; pretty_sep=" · "; fi

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
             percent: .spend.percent,
             enabled: (.spend.enabled // false),
             source: "spend" }
         elif ((.extra_usage.monthly_limit // 0) > 0 or (.extra_usage.is_enabled // false)) then
           (if .extra_usage.decimal_places != null
            then pow(10; .extra_usage.decimal_places) else $d end) as $div |
           { spent: ((.extra_usage.used_credits  // 0) / $div),
             limit: ((.extra_usage.monthly_limit // 0) / $div),
             percent: .extra_usage.utilization,
             enabled: (.extra_usage.is_enabled // false),
             source: "extra_usage" }
         else
           { spent: null, limit: null, percent: null, enabled: false, source: null }
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
      jq -r --argjson d "$divisor" --argjson showreset "$show_reset" --arg sep "$text_sep" '
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
        # "!" marks non-normal severity (warning/exceeded)
        def limit_line: "\(limit_label) \(.percent // 0 | round)%\(if (.severity // "normal") != "normal" then "!" else "" end)";
        # Time left on the 5h session window as "4h45m" / "45m"; "" when absent.
        def reset_left:
          ([ .limits[]? | select(.kind == "session") | .resets_at ] | first) as $r
          | if ($r == null) then ""
            else (try (($r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) - now | floor) catch -1) as $rem
              | if $rem <= 0 then ""
                else (($rem / 3600) | floor) as $h | ((($rem % 3600) / 60) | floor) as $m
                  | if $h > 0 then "\($h)h\($m)m" else "\($m)m" end
                end
            end;

        (
          # 1) Modern spend object with a cap
          if (.spend.limit // null) != null then
            (.spend.used | money) as $s | (.spend.limit | money) as $l |
            "$\($s | fmt2) / $\($l | fmt2) (\(.spend.percent // (if $l > 0 then $s / $l * 100 else 0 end) | round)%)"
          # 2) Legacy extra_usage cap (work seats on older schema)
          elif (.extra_usage.monthly_limit // 0) > 0 then
            (if .extra_usage.decimal_places != null
             then pow(10; .extra_usage.decimal_places) else $d end) as $div |
            ((.extra_usage.used_credits  // 0) / $div) as $s |
            ((.extra_usage.monthly_limit // 0) / $div) as $l |
            "$\($s | fmt2) / $\($l | fmt2) (\($s / $l * 100 | round)%)"
          # 3) No USD cap: rate limits — prefer the modern limits[] array.
          #    Non-session windows first, 5h session held last (next to Reset).
          elif ((.limits // []) | length) > 0 then
            ([ .limits[] | select(.kind != "session") | limit_line ]) as $others |
            ([ .limits[] | select(.kind == "session") | limit_line ]) as $sess |
            (($others + $sess) | join($sep))
          # 4) Oldest fallback: flat five_hour / seven_day fields (5h last)
          else
            [ "7d \(.seven_day.utilization // 0 | round)%",
              (if (.seven_day_opus.utilization) != null
               then "opus \(.seven_day_opus.utilization | round)%" else empty end),
              (if (.seven_day_sonnet.utilization) != null
               then "sonnet \(.seven_day_sonnet.utilization | round)%" else empty end),
              "5h \(.five_hour.utilization // 0 | round)%"
            ] | join($sep)
          end
        ) + (if $showreset then (reset_left | if . == "" then "" else " Reset \(.)" end) else "" end)
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
        def reset_left:
          ([ .limits[]? | select(.kind == "session") | .resets_at ] | first) as $r
          | if ($r == null) then ""
            else (try (($r | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) - now | floor) catch -1) as $rem
              | if $rem <= 0 then ""
                else (($rem / 3600) | floor) as $h | ((($rem % 3600) / 60) | floor) as $m
                  | if $h > 0 then "\($h)h\($m)m" else "\($m)m" end
                end
            end;
        (paint($dim; $sep)) as $sep |                            # dimmed separator

        (
          if (.spend.limit // null) != null then
            (.spend.used | money) as $s | (.spend.limit | money) as $l |
            (.spend.percent // (if $l > 0 then $s / $l * 100 else 0 end)) as $p |
            paint(col($p); "$\($s | fmt2)/$\($l | fmt2) \($lbr)\(mkbar($p))\($rbr)\($p | round)%")
          elif (.extra_usage.monthly_limit // 0) > 0 then
            (if .extra_usage.decimal_places != null
             then pow(10; .extra_usage.decimal_places) else $d end) as $div |
            ((.extra_usage.used_credits  // 0) / $div) as $s |
            ((.extra_usage.monthly_limit // 0) / $div) as $l |
            (if $l > 0 then $s / $l * 100 else 0 end) as $p |
            paint(col($p); "$\($s | fmt2)/$\($l | fmt2) \($lbr)\(mkbar($p))\($rbr)\($p | round)%")
          elif ((.limits // []) | length) > 0 then
            # non-session bars first, session held to the end (next to its reset)
            ([ .limits[] | select(.kind != "session") | bar(limit_label; (.percent // 0)) ]) as $others |
            ([ .limits[] | select(.kind == "session") ] | first) as $sess |
            (if $sess != null then [ $sess | bar("5h"; (.percent // 0)) ] else [] end) as $ssegs |
            (($others + $ssegs) | join($sep))
          else
            ([ bar("7d"; (.seven_day.utilization // 0)),
               bar("5h"; (.five_hour.utilization // 0)) ] | join($sep))
          end
        ) + (if $showreset then (reset_left | if . == "" then "" else " " + paint($dim; "Reset \(.)") end) else "" end)

      ' "$cache"
      ;;
  esac
}
