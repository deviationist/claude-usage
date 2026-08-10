# claude-usage

Your Claude account's spend / rate-limit usage in the terminal — **straight from
Anthropic's own server-side counter**, not from parsing local transcripts.

<p align="center">
  <img src="assets/demo-v0.4.0-1e1e27.svg" alt="claude-usage — coloured usage bars for every plan shape, straight from Anthropic's server-side counter">
</p>

(The image is genuine renderer output — `tools/generate-readme-svg.zsh` seeds
demo caches, runs `claude-usage`, and converts the ANSI colours to SVG.)

`claude-usage` reads the same OAuth usage endpoint that
claude.ai → Settings → Usage shows, so it reports **all** usage billed to the
account — Claude Code on any machine *plus* claude.ai — unlike transcript-based
tools (e.g. ccusage) that only see the box they run on. It works for all three
plan shapes:

- **USD-budget seats** render `$300.04/$300 ▕████▏100%`
- **Max / Pro seats** render their 7d / per-model / 5h rate-limit windows, each
  with its reset countdown (`7d▕██░░▏20% 3d21h`; the 5h window's countdown
  trails the line). All countdowns share one style — bare by default, or
  labelled via `--reset-prefix 'Reset '`.
- **Max / Pro + usage credits** (the overflow budget that kicks in when you hit
  a plan limit) render both: the dollar group leads, then the plan windows —
  `$0/$40 ▕░░░░▏0% Aug 1 | 7d▕██░░▏20% 3d21h · 5h▕████▉▏49% 1h8m`. The
  two groups are different mechanisms, so a distinct group separator sits
  between them (`" || "` text, dimmed `" | "` pretty — override with
  `--group-sep`). Toggling credits off on the usage page drops the dollar
  group again.

Each piece is individually configurable: `--show-spend=false` hides the
monthly cap (`$0/$40`), `--show-spend-reset=false` drops the monthly cap's
reset date (`Aug 1` — derived locally as the 1st of next month, since the API
doesn't report it), and `--show-limit-resets=false` drops the per-window
countdowns on the 7d/model limits.

> **Your total credit balance can't be shown.** The usage API reports the
> *monthly* credit spend (`$12.50/$40`) but not the purchased-credit total —
> `spend.balance` is null server-side, and even claude.ai's own usage page
> fetches the balance from a separate session-authenticated billing endpoint
> that an OAuth token can't reach. The rendering is already wired (a dimmed
> `bal $100` segment, `--show-balance` to toggle): it appears automatically
> the day Anthropic populates the field.

It's built to be embedded in an always-on statusline: bare calls **never block**
— they return instantly from a cache and revalidate in a detached background
process with stale-while-revalidate semantics, lock-guarded fetches, and failure
backoff. (The companion [claude-statusline](https://github.com/deviationist/claude-statusline)
project renders this inside a Claude Code status line.)

## Install

Requirements: `zsh`, `jq`, `curl`.

```sh
git clone https://github.com/deviationist/claude-usage.git ~/code/claude-usage
```

Source it from `~/.zshrc`:

```sh
source ~/code/claude-usage/claude-usage.zsh
```

That defines the `claude-usage` shell function. (It's a zsh function, so it must
be *sourced* — it isn't an executable on `PATH`.)

## Usage

```
claude-usage                          # colour progress bars (default, --pretty)
claude-usage --text-only              # plain one-liner, no bars/colour
claude-usage --theme labelled         # pick a preset (--list-themes for names)
claude-usage --no-color               # keep the bars, drop all colour
claude-usage --list-themes            # print the built-in preset names
claude-usage --themes                 # preview: render your usage once per theme
claude-usage --json                   # machine-readable summary for scripts
claude-usage --raw                    # full untouched endpoint response
claude-usage --fresh                  # blocking refresh, guaranteed current
claude-usage --no-block               # statusline mode: never blocks, silent on cold/broken state
claude-usage --dir PATH               # another account's Claude config dir
claude-usage --sep ' / '              # custom metric delimiter (both modes)
claude-usage --show-profile           # prefix the seat label, e.g. "Personal (Max 5x)"
                                      # (opt-in; needs claude-profile — see below)
claude-usage --label 'Work'           # set that label yourself, no claude-profile
claude-usage --show-reset=false       # drop the 5h reset countdown
claude-usage --show-spend=false       # hide the monthly $-cap segment (combined view)
claude-usage --show-balance=false     # hide the credit-balance segment
claude-usage --show-spend-reset=false # drop the monthly-cap reset date
claude-usage --show-limit-resets=false # drop the 7d/model reset countdowns
claude-usage --reset-prefix 'Reset '  # label every reset — countdowns and the
                                      # monthly-cap date (default: bare)
claude-usage --spend-prefix 'Credit: '     # label before the dollar group
claude-usage --limits-prefix 'Plan usage: ' # label before the plan limits
claude-usage --group-sep ' >> '       # $-group / plan-limit separator
claude-usage --version                # print version and exit
```

`--pretty` respects the [`NO_COLOR`](https://no-color.org) convention: set
`NO_COLOR` to any non-empty value and colour is suppressed (bars kept), same as
`--no-color`.

Both `--pretty` and `--text-only` order the metrics with the 5h window last
(next to the reset countdown).

## Theming

A theme is a **full-config preset**: colours and glyphs for the `--pretty`
bars, plus optional layout defaults — separators, section/reset prefixes, bar
width — that apply to both output modes. Pick one with `--theme NAME` (or
`CLAUDE_USAGE_THEME`, including in the config file); `--list-themes` prints
the names.

Preview them all against your own live usage with `claude-usage --themes`:

<p align="center">
  <img src="assets/themes-v0.4.0-1e1e27.svg" alt="all claude-usage themes rendered against the same usage">
</p>

| Theme | Look |
|---|---|
| `default` | green / amber / red, unicode eighth-block bars (`▕██▊░░▏`) |
| `mono` | no colour, same unicode bars (separators stay faint) |
| `ascii` | colour + ASCII glyphs (`[##....]`) — for fonts without block chars |
| `bright` | bright ANSI colours, unicode bars |
| `neon` | vivid 256-colour, unicode bars |
| `retro` | arcade loading bar `[====>.....]` in CRT phosphor (green tube → amber → alarm red) |
| `shade` | DOS shade blocks `▕▓▓▓▒░░░░░░▏` on ice (cyan → gold → salmon) |
| `dots` | dot meter, 5 wide, candy pastels: `●●◑○○` (mint → peach → hot pink) |
| `spark` | sparkline ramp rising from a baseline, electric: `██▅▁▁▁▁▁▁▁` (cyan → orange → hot red) |
| `line` | slim gauge, understated: `━━━╸───────` (periwinkle → gold → rose) |
| `labelled` | default look + section/reset labels: `Credit: $0/$40 ▕░░▏0% Reset Aug 1 \| Plan: 7d▕██▏53% Reset 3d20h …` |
| `catppuccin` | truecolor [Catppuccin Mocha](https://catppuccin.com) — the palette from the screenshot above |
| `dracula` | truecolor [Dracula](https://draculatheme.com) palette |
| `nord` | truecolor [Nord](https://nordtheme.com) palette |
| `gruvbox` | truecolor [Gruvbox](https://github.com/morhetz/gruvbox) palette |
| `compact` | tightest statusline fit: 5-cell bars, no brackets, single-space separators |

A theme only fills settings you haven't chosen yourself — any explicit value
(flag, env var, or config file) beats the theme. So `--theme labelled
--limits-prefix 'Usage: '` keeps the theme's `Credit:` label but swaps `Plan:`
for `Usage: `.

`--no-color` drops colour from *any* theme while keeping the bars (unlike
`--text-only`, which drops the bars too).

For finer control, these env vars override individual fields **on top of** the
chosen theme:

| Variable | Format | Example |
|---|---|---|
| `CLAUDE_USAGE_COLORS` | `low:mid:high` SGR params (`""` = no colour) | `92:93:91` or `38;5;46:38;5;226:38;5;196` |
| `CLAUDE_USAGE_THRESHOLDS` | `amber:red` fill breakpoints | `70:90` |
| `CLAUDE_USAGE_BAR_CHARS` | `full:partial:empty` glyphs (partial is a low→high ramp, may be empty) | `#::.` |
| `CLAUDE_USAGE_BRACKETS` | `left:right` bar frame (`:` = none) | `[:]` |
| `CLAUDE_USAGE_DIM` | SGR for separators/reset (`""` = none) | `2` |

Example — a monochrome, ASCII-framed bar for a limited terminal:

```sh
CLAUDE_USAGE_BAR_CHARS='#::.' CLAUDE_USAGE_BRACKETS='[:]' claude-usage --no-color
```

## Accounts & tokens

Account resolution: `--dir` > `$CLAUDE_USAGE_DIR` > `$CLAUDE_CONFIG_DIR` >
`~/.claude`.

The OAuth token is read from `<dir>/.credentials.json` or, on macOS, the
Keychain entry Claude Code itself maintains. Multi-account setups are handled:
the Keychain service is namespaced per config dir
(`Claude Code-credentials-<first 8 hex of sha256(absolute dir path)>`), and the
freshest non-expired token across all sources wins. Nothing is ever written to
those stores — `claude-usage` only reads the token Claude Code already keeps
locally, and talks only to the standard Anthropic API host.

## Which seat is this? (`--show-profile`)

The bars tell you how much is left; they don't tell you *whose*. With
`--show-profile` the line is prefixed with a seat label — useful the moment a
machine has more than one subscription, and the reason this exists at all:

```console
$ claude-usage --show-profile
Personal (Max 5x) 7d▕░░░░░░░░░░▏0% 4d20h · Fable▕░░░░░░░░░░▏0% · 5h▕▌░░░░░░░░░▏5% 1h15m
```

In a statusline it lands next to the bars it qualifies:

```
~/.zsh/claude-usage [main] | Opus 5 | ctx:12% | Personal (Max 5x) 7d▕░░░░░░░░░░▏0% · 5h▕▌░░░░░░░░░▏5% 1h15m
```

**The label is claude-profile's to compose, not ours.** `claude-usage` asks
one question — `claude-profile resolve --json --dir <config dir>` — and renders
the `label` it gets back verbatim. Casing and spacing come from that config
(`display` per profile, `account_display` per account), never from a
title-casing heuristic here, and the account only appears in parentheses when
the profile actually holds more than one.

Note it asks **by config dir**, not by cwd: a statusline knows which account a
session belongs to but has no meaningful working directory, so cwd-based
resolution would name the wrong profile.

**Opt-in, and silent when there's nothing to say.** Default off; with it off,
claude-profile is never invoked and the output is byte-identical. With it on,
every "no label" case — no claude-profile installed, no config file, a dir no
profile claims, an older claude-profile without the `--json` porcelain —
renders the usage exactly as before and says nothing on stderr. Four setups,
four sane outcomes:

| Setup | Renders |
|---|---|
| No `claude-profile` | Unchanged output (flag is a no-op) |
| One profile, one subscription | `Personal` — no parentheses |
| Profiles chosen by folder path | Follows the session's config dir |
| Several serial accounts | `Personal (Max 20x)`, flipping on swap |

**It costs a repainting statusline nothing.** The lookup shells out to python
(~100 ms), so the answer is cached in a `<cache>.label` sidecar next to the
usage cache. That filename already embeds the account's uuid, so a serial swap
invalidates it for free; `CLAUDE_USAGE_LABEL_TTL` (default 900 s) covers
changes that move neither dir nor account, such as a `claude-profile use`
toggle. A cached *empty* label expires far sooner
(`CLAUDE_USAGE_LABEL_TTL_MISS`, 60 s), so a transient failure can't hide the
label for a quarter of an hour. Under `--no-block` the sidecar is never filled
synchronously — a cold cache renders one repaint without the label and
refreshes in the background.

`--label STR` sets the string yourself and skips the lookup entirely, for
anyone who wants the prefix without the juggler.

`--table` puts the label in the `ACCOUNT` cell, where it beats the config
dir's basename (`Personal (Max 5x)` vs `claude-personal`), and `--all` names
every row the same way — see below.

## Multiple accounts (`--all`)

`claude-usage` on its own shows **one** seat. If you also run the companion
[`claude-profile`](../claude-profile) subscription juggler — several profiles
and/or serial accounts on one machine — `--all` renders **every** account, one
labelled line each:

```console
$ claude-usage --all
max20x  $99.66/$100 ▕██████████▏100% Aug 1 | 7d▕████████░░▏80% 1d17h · Fable▕██████████▏100% 1d17h · 5h▕░░░░░░░░░░▏0%
max5x   7d▕▌░░░░░░░░░▏5% 6d13h · Fable▕░░░░░░░░░░▏0% · 5h▕██░░░░░░░░▏21% 3h46m
```

It's an **opt-in bridge**, not a coupling: with no `claude-profile` installed
the flag just errors, and the single-account paths are untouched. Every render
flag threads through per account (`--all --theme nord`, `--all --text-only`,
`--all --no-color`), and `--all --json` / `--all --raw` emit a machine-readable
`[{account, usage}]` array instead of prefixed lines.

When accounts differ in shape — one has a `$`-cap, another doesn't — the free
lines go ragged. **`--table`** lays them out in an aligned, bordered grid with
named columns instead:

```console
$ claude-usage --all --table
┌─────────┬───────────────────────────────┬────────────────────────┬─────────────────────────┬────────────────────────┐
│ ACCOUNT │ SPEND                         │ 7D                     │ FABLE                   │ 5H                     │
├─────────┼───────────────────────────────┼────────────────────────┼─────────────────────────┼────────────────────────┤
│ max20x  │ ▕██████████▏ $99.66/$100 Aug 1│ ▕████████░░▏ 80% 1d16h  │ ▕██████████▏ 100% 1d16h │ ▕░░░░░░░░░░▏ 2% 4h48m   │
│ max5x   │ ·                             │ ▕█░░░░░░░░░▏ 11% 6d12h  │ ▕░░░░░░░░░░▏ 5% 6d12h    │ ▕████████▋░▏ 87% 2h28m  │
└─────────┴───────────────────────────────┴────────────────────────┴─────────────────────────┴────────────────────────┘
```

`--table` is a **format**, not an account selector: on its own it renders just
the current account (one row); combine it with `--all` for every account.
Columns are the **union** across accounts (`ACCOUNT`, then `SPEND` only if some
account has a cap that's **live** (usage credits enabled) **or carries real
spend** — the same `spend_on` gate as pretty mode, so a disabled *but used* cap
still shows while a dormant $0 one is hidden — `7D`, one per scoped model, `5H`);
a metric an account lacks shows a dim `·`. Each cell carries a **themed progress bar** (same glyphs,
brackets, colours and `CLAUDE_USAGE_BAR_WIDTH` as the statusline bars) followed
by the percent **plus its own reset countdown**, honouring the same reset
toggles (`--show-limit-resets`, `--show-reset`, `--reset-prefix`, `--no-color`).
Borders are on by default — drop them with **`--no-borders`**; drop the bars for
a bare numeric grid with **`--no-bars`** (or `CLAUDE_USAGE_TABLE_BARS=false`).

Division of labour: `claude-profile` owns the credentials and hands back each
account's usage (**refreshing a parked account's token** when needed, which a
Keychain-reading consumer couldn't do); `claude-usage` only renders. An account
whose token can't be obtained — e.g. the *live* account when its token is
idle-expired, which only a Claude Code session refreshes — shows
`(usage unavailable)` rather than dropping out.

## Caching

Per account, under `$TMPDIR` (the cache file is derived from the config dir, so
multiple accounts never clobber each other). Bare invocations return
immediately from cache; if the cache is older than the TTL, a detached
background refresh runs and the **next** call sees the new value. Failed
refreshes never destroy the last known value and back off for 60s, so a
constantly-repainting statusline can't hammer the endpoint.

## Config file

Every `CLAUDE_USAGE_*` variable below can also live in
`~/.config/claude-usage/config` (override the path with `CLAUDE_USAGE_CONFIG`)
as plain `NAME=value` lines — quotes around the value optional, `#` comments
allowed:

```sh
CLAUDE_USAGE_RESET_PREFIX="Reset "
CLAUDE_USAGE_SPEND_PREFIX="Credit: "
CLAUDE_USAGE_LIMITS_PREFIX="Plan usage: "
```

The function reads this file itself on every invocation, in **any** process —
which is the reliable way to configure statusline rendering: a statusline
repaint runs in a subprocess that never sees your interactive shell's
un-exported variables, but it always reads this file. Values are scoped to the
function (nothing leaks into your shell). Precedence: flags > config file >
process env.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_USAGE_DIR` | `~/.claude` | Default account config dir (overridden by `--dir`). |
| `CLAUDE_USAGE_SHOW_SPEND` | `true` | Default for `--show-spend` (monthly $-cap segment in the combined view). |
| `CLAUDE_USAGE_SHOW_BALANCE` | `true` | Default for `--show-balance` (credit-balance segment, when the API reports one). |
| `CLAUDE_USAGE_SHOW_SPEND_RESET` | `true` | Default for `--show-spend-reset` (monthly-cap reset date, derived locally). |
| `CLAUDE_USAGE_SHOW_LIMIT_RESETS` | `true` | Default for `--show-limit-resets` (7d/model per-window reset countdowns). |
| `CLAUDE_USAGE_SHOW_PROFILE` | `false` | Default for `--show-profile` (seat label from claude-profile, e.g. `Personal (Max 5x)`). |
| `CLAUDE_USAGE_LABEL_TTL` | `900` | Max age (seconds) of the cached seat label before it's re-resolved. |
| `CLAUDE_USAGE_LABEL_TTL_MISS` | `60` | Same, for a cached *empty* label — short, so a transient failure can't hide the label for the full TTL. |
| `CLAUDE_PROFILE_SCRIPT` | unset | Explicit path to `claude-profile.py` for the `--show-profile` / `--all` bridge. Authoritative: if set and missing, claude-profile counts as not installed. |
| `CLAUDE_USAGE_GROUP_SEP` | per-mode | Separator between the dollar group and the plan limits (`" \|\| "` text, `" \| "` pretty by default). |
| `CLAUDE_USAGE_RESET_PREFIX` | `""` | Default for `--reset-prefix` — label put before every reset: window countdowns and the monthly-cap date (e.g. `"Reset "`). |
| `CLAUDE_USAGE_SPEND_PREFIX` | `""` | Default for `--spend-prefix` — label before the dollar group (e.g. `"Credit: "`; dimmed in pretty). |
| `CLAUDE_USAGE_LIMITS_PREFIX` | `""` | Default for `--limits-prefix` — label before the plan limits (e.g. `"Plan usage: "`; dimmed in pretty). |
| `CLAUDE_USAGE_TTL` | `120` | Cache max age (seconds) before a background refresh is triggered. |
| `CLAUDE_USAGE_BAR_WIDTH` | `10` | Cells per bar in `--pretty`. |
| `CLAUDE_USAGE_SEP` | per-mode | Metric delimiter for both modes (`" \| "` text, `" · "` pretty by default). |
| `CLAUDE_USAGE_DIVISOR` | `100` | Credits→dollars divisor (100 = the API's cents) for legacy USD schemas. |
| `CLAUDE_USAGE_THEME` | `default` | `--pretty` preset: `default` / `mono` / `ascii` / `bright` / `neon` (see [Theming](#theming)). |
| `CLAUDE_USAGE_COLORS` | per-theme | `low:mid:high` fill-colour SGR params (`""` = no colour). |
| `CLAUDE_USAGE_THRESHOLDS` | `70:90` | `amber:red` fill breakpoints. |
| `CLAUDE_USAGE_BAR_CHARS` | per-theme | `full:partial:empty` bar glyphs (partial ramp may be empty). |
| `CLAUDE_USAGE_BRACKETS` | per-theme | `left:right` bar frame (`:` = none). |
| `CLAUDE_USAGE_DIM` | `2` | SGR for separators / reset countdown (`""` = none). |

## Caveats

- The usage endpoint (`api.anthropic.com/api/oauth/usage`) is **undocumented**
  and was reverse-engineered from Claude Code's own traffic. It may change or
  disappear without notice.
- **No total credit balance**: the endpoint reports monthly credit spend but
  returns `spend.balance: null`, so the purchased-credit total shown on
  claude.ai's usage page is not available here (see the note under the plan
  shapes above).
- Keep the TTL sane — hammering the endpoint gets rate-limited. The defaults are
  tuned for a statusline that repaints often.

## Development

```sh
zsh -n claude-usage.zsh              # syntax check
zsh test/run.zsh                     # test suite (hermetic — no network)
zsh tools/generate-readme-svg.zsh    # regenerate the README demo + themes SVGs
```

The SVGs are genuine renderer output (seeded caches, ANSI → SVG, truecolor
passthrough + xterm-256 cube math). The generator embeds the version + a
random hash in the filenames and rewrites the README's `<img>` references —
commit all three. Regenerate whenever the themes or the renderers change.

The tests seed a fresh cache for a throwaway account dir and assert against the
rendered output, so they never touch the network or your real credentials. CI
runs the same on every push/PR. See [AGENTS.md](AGENTS.md) for the internals.

## License

MIT — see [LICENSE](LICENSE).
