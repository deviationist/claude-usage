# AGENTS.md — orientation for coding agents

Context for automated contributors working on this repo. Humans: see
[README.md](README.md).

## What this is

`claude-usage` is a **single zsh function** that prints a Claude account's
server-side spend / rate-limit usage in the terminal, read from the undocumented
OAuth usage endpoint (`api.anthropic.com/api/oauth/usage`). It is *sourced*, not
executed — there is no binary on `PATH`.

## Layout

| Path | Role |
|---|---|
| `claude-usage.zsh` | The entire implementation. Everything lives here. |
| `test/run.zsh` | Hermetic test harness (no network). |
| `tools/generate-readme-svg.zsh` | Regenerates the README demo + themes SVGs from real renderer output. |
| `assets/{demo,themes}-v*.svg` | The README terminal screenshots — **generated, never hand-edit**. |
| `.github/workflows/ci.yml` | Runs `zsh -n` + `test/run.zsh` on push/PR. |
| `README.md` | Human docs. |
| `AGENTS.md` | This file. |

`claude-usage.zsh` has two functions:
- `_claude_usage_refresh` — fetches the endpoint and atomically replaces the
  per-account cache. Handles token resolution, locking, and failure backoff.
- `claude-usage` — arg parsing, theme resolution, cache freshness, and the four
  output renderers (`pretty` / `text` / `json` / `raw`), each a jq program.

## Key models to preserve

- **Stale-while-revalidate cache**, one file per account under `$TMPDIR`
  (path derived from the config dir's basename). Bare calls return instantly
  from cache; a stale cache triggers a *detached* background refresh whose result
  the *next* call sees. `--no-block` (statusline mode) must never block.
- **Never clobber a good cache on failure**: fetch to `$cache.tmp`, validate
  (`jq -e '.error == null'`), then `mv`. A `.fail` marker enforces 60s backoff.
- **Token resolution** picks the freshest non-expired token across
  `$dir/.credentials.json` + the per-account macOS Keychain entry
  (`Claude Code-credentials-<8 hex of sha256(abs dir)>`) + the legacy un-suffixed
  entry (only for `~/.claude`). Read-only — never write these stores.
- **Four schema fallbacks** in each renderer: modern `.spend` → legacy
  `.extra_usage` → `.limits[]` array → oldest flat `five_hour`/`seven_day`.
  Endpoint shapes vary by plan; keep all four paths working. The dollar cap and
  `.limits[]` are **not mutually exclusive**: Max/Pro seats with usage credits
  enabled return both, and the renderers show both (dollar segment first, 5h
  last next to Reset) — the dollar segment is suppressed in that combined case
  while the credits toggle is off (`spend.enabled` / `extra_usage.is_enabled`).
  A dollar-cap-only seat (no `.limits[]`) renders the dollar segment regardless
  of the toggle, as before. In the combined view the dollar group and the plan
  limits are joined by a **group separator** (`--group-sep`; default `" || "`
  text, dimmed `" | "` pretty) — they're different mechanisms, keep them
  visually distinct. Related knobs, all defaulting to true:
  `--show-spend` / `--show-balance` (balance renders only when `spend.balance`
  is non-null — null server-side so far), `--show-spend-reset` (the date is
  **derived locally** as the 1st of next month because the API has no monthly
  reset field — don't present it as server data), and `--show-limit-resets`
  (per-window countdowns on non-session limits from their `resets_at`; the 5h
  window keeps the trailing countdown instead). Every reset — the window
  countdowns, the trailing 5h one, and the monthly spend-cap date — takes the
  same `--reset-prefix` label (default `""`, bare `14m`/`3d21h`/`Aug 1`), so
  all resets render in one style. `--spend-prefix` /
  `--limits-prefix` (default `""`) insert optional section labels before the
  dollar group and the plan limits (dimmed in pretty; user supplies any
  trailing space).
- **Config file**: `claude-usage` sources
  `${CLAUDE_USAGE_CONFIG:-~/.config/claude-usage/config}` at the top of every
  call — plain `CLAUDE_USAGE_*=value` lines, each key declared `local` before
  assignment so nothing leaks into the calling shell. Precedence: flags >
  config file > process env. This exists because statusline repaints run in
  subprocesses that don't inherit un-exported shell vars; don't "simplify" it
  away in favour of env-only. The parser needs `extended_glob` (set locally).
- **Theming**: a theme is a full-config preset — colours / thresholds / glyphs /
  brackets / dim (pretty only) plus optional layout defaults (`tsep` / `tgsep` /
  `trpfx` / `tsppfx` / `tlimpfx` / `twidth`) that apply to both modes. Layout
  presets only fill fields with no explicit value — the `*_set` flags record
  flag/env/config choices and gate the application; preserve that precedence
  (flags > config > env > theme > built-in default). Per-field `CLAUDE_USAGE_*`
  overrides layer on top, then `--no-color` / `NO_COLOR` blank all SGR.
  Colours/glyphs are passed into jq as args — do not re-hardcode them in the
  jq programs. The canonical theme-name list is the `all_themes` array (feeds
  `--list-themes`, the `--themes` preview — which recursively renders once per
  theme — and the unknown-theme error); keep it in sync with the `case` table.

## Testing

```sh
zsh -n claude-usage.zsh   # syntax
zsh test/run.zsh          # full suite (hermetic — seeds a fresh cache, no network)
```

The harness seeds a cache file newer than the TTL for a throwaway account dir, so
the warm path serves it and the OAuth/curl code is never reached. **Add a test
for any renderer or flag change**, and keep the suite network-free.

## Gotchas

- The jq programs contain **raw ESC (`0x1b`) bytes** for ANSI. Don't "fix" them
  to `` literals — and be aware that literal string-matching edits over
  those lines are fragile (match with tooling that handles the bytes).
- `claude-usage` runs under `emulate -L zsh`; keep it POSIX-ish zsh, no external
  deps beyond `zsh` / `jq` / `curl`.
- Bump `CLAUDE_USAGE_VERSION` (top of `claude-usage.zsh`) on a release and tag it.
- After changing any theme or the pretty renderer, regenerate the README demo +
  themes SVGs (`zsh tools/generate-readme-svg.zsh`) — it renders real output,
  embeds version+hash in the filenames (busts GitHub's image cache), and
  rewrites the README `<img>` references; commit the new SVGs and the README
  together.
- Default `--pretty` output is a public contract (the claude-statusline project
  parses/renders it) — changing default colours/glyphs is a breaking change.
