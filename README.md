# claude-usage

Your Claude account's spend / rate-limit usage in the terminal — **straight from
Anthropic's own server-side counter**, not from parsing local transcripts.

```
╭─ zsh ────────────────────────────────────────────────────── claude-usage ─╮

   ❯ claude-usage
   7d▕██░░░░░░░░▏20% · Opus▕██▊░░░░░░░▏27% · 5h▕████▉░░░░░▏49%  Reset 1h8m

   ❯ claude-usage --text-only
   7d 20% │ Opus 27% │ 5h 49% Reset 1h8m

   ❯ claude-usage --dir ~/.claude-work      # a USD-budget seat
   $142.50/$300 ▕████▊░░░░░▏48%

╰───────────────────────────────────────────────────────────────────────────╯
```

(Bars are green / amber / red by fill in a real terminal — the colour doesn't
survive a README code block.)

`claude-usage` reads the same OAuth usage endpoint that
claude.ai → Settings → Usage shows, so it reports **all** usage billed to the
account — Claude Code on any machine *plus* claude.ai — unlike transcript-based
tools (e.g. ccusage) that only see the box they run on. It works for both plan
shapes:

- **USD-budget seats** render `$300.04/$300 ▕████▏100%`
- **Max / Pro seats** render their 7d / per-model / 5h rate-limit windows with a
  reset countdown.

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
claude-usage --theme bright           # pick a preset (default/mono/ascii/bright/neon)
claude-usage --no-color               # keep the bars, drop all colour
claude-usage --list-themes            # print the built-in preset names
claude-usage --json                   # machine-readable summary for scripts
claude-usage --raw                    # full untouched endpoint response
claude-usage --fresh                  # blocking refresh, guaranteed current
claude-usage --no-block               # statusline mode: never blocks, silent on cold/broken state
claude-usage --dir PATH               # another account's Claude config dir
claude-usage --sep ' / '              # custom metric delimiter (both modes)
claude-usage --show-reset=false       # drop the 5h reset countdown
claude-usage --version                # print version and exit
```

`--pretty` respects the [`NO_COLOR`](https://no-color.org) convention: set
`NO_COLOR` to any non-empty value and colour is suppressed (bars kept), same as
`--no-color`.

Both `--pretty` and `--text-only` order the metrics with the 5h window last
(next to the reset countdown).

## Theming

The `--pretty` bars are themed. Pick a preset with `--theme NAME` (or
`CLAUDE_USAGE_THEME`); `--list-themes` prints the names.

| Theme | Look |
|---|---|
| `default` | green / amber / red, unicode eighth-block bars (`▕██▊░░▏`) |
| `mono` | no colour, same unicode bars (separators stay faint) |
| `ascii` | colour + ASCII glyphs (`[##....]`) — for fonts without block chars |
| `bright` | bright ANSI colours, unicode bars |
| `neon` | vivid 256-colour, unicode bars |

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

## Caching

Per account, under `$TMPDIR` (the cache file is derived from the config dir, so
multiple accounts never clobber each other). Bare invocations return
immediately from cache; if the cache is older than the TTL, a detached
background refresh runs and the **next** call sees the new value. Failed
refreshes never destroy the last known value and back off for 60s, so a
constantly-repainting statusline can't hammer the endpoint.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_USAGE_DIR` | `~/.claude` | Default account config dir (overridden by `--dir`). |
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
- Keep the TTL sane — hammering the endpoint gets rate-limited. The defaults are
  tuned for a statusline that repaints often.

## Development

```sh
zsh -n claude-usage.zsh   # syntax check
zsh test/run.zsh          # test suite (hermetic — no network)
```

The tests seed a fresh cache for a throwaway account dir and assert against the
rendered output, so they never touch the network or your real credentials. CI
runs the same on every push/PR. See [AGENTS.md](AGENTS.md) for the internals.

## License

MIT — see [LICENSE](LICENSE).
