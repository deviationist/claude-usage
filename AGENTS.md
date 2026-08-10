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

The single-account core is **profile-agnostic** — it knows nothing about the
companion `claude-profile` tool; callers wanting another seat pass `--dir`. The
one deliberate bridge is the **opt-in `--all`** mode (see below), which engages
only when the user asks for it and `claude-profile` is installed.

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

- **`--all` (opt-in multi-account bridge)**: renders one labelled line per
  `claude-profile` account. Gated on `command -v claude-profile`; errors cleanly
  if absent. It shells to `claude-profile usage-json --all`, which emits
  `<account>\t<compact-raw-json>` per line (empty json field = unavailable —
  e.g. a live account whose token is idle-expired, which only Claude Code can
  refresh). Each account's JSON is fed back through **this same renderer** via
  the internal **`--cache-file PATH`** flag (render a file directly, skip
  fetch/cache), so every theme/flag applies per account — recursion mirrors the
  `--themes` preview. `--json`/`--raw` emit a valid `[{account, usage}]` array
  (gaps → `usage:null`) instead of prefixed lines. Division of labour: the
  credential + parked-token-refresh lives in `claude-profile` (it owns the
  secrets); `claude-usage` only ever renders. The NDJSON contract requires
  **one physical line per account** — `usage-json`'s compact `json.dumps`
  guarantees it; don't emit pretty-printed JSON there.
- **`--table` (aligned named-column grid)**: a **format**, orthogonal to account
  selection — bare it renders the single resolved account (one row, labelled by
  the config-dir basename); `--all --table` renders every account. Fixes the
  raggedness of the free-form lines (a `$`-cap segment on one account shifts
  everything). Columns = the *union* across accounts (`ACCOUNT`, optional
  `SPEND` — only for accounts whose cap is **live** (`spend.enabled==true`) OR
  **carries real spend** (`spend.spent>0`) in the `--json` summary, the same
  `spend_on` gate pretty mode applies (a disabled-but-used cap still shows; only
  a dormant $0 one is hidden), so both renderers agree — `7D`, one per scoped
  model, `5H`); a metric an account lacks is a dim `·`. Each cell is a **themed progress bar + percent + its own reset countdown**
  (dimmed, `--reset-prefix` label), the bar reusing the resolved theme glyphs /
  brackets / colour and `CLAUDE_USAGE_BAR_WIDTH` via a `mkbar` copied from the
  pretty renderer (each glyph is one display column, so the bar length feeds the
  plain-width padding unchanged). Gated by the same `--show-limit-resets` /
  `--show-reset` / `--show-spend-reset` toggles. **Bars on by default;
  `--no-bars` (or `CLAUDE_USAGE_TABLE_BARS=false`) falls back to the bare numeric
  grid.** **Box borders by default; `--no-borders` drops them.** Both `--table` and
  `--all --table` share `_claude_usage_render_table` (a jq program reading
  {account, usage-summary} NDJSON on stdin; it reads the caller's resolved theme
  + toggle locals via zsh **dynamic scope**, so nothing is threaded as args).
  Built from each account's `--json` summary (structured data, not the rendered
  line). Implementation notes:
  - Alignment is on the **visible** width — padding computed from the uncoloured
    cell text so ANSI never skews columns; each cell carries a `{plain, rich}`
    pair for exactly this.
  - `spend_reset` is computed **before** the `--all` block (which runs before the
    cache section) so the all-accounts table can label the `$` column.
  - jq truthiness: `0` is **truthy** in jq (only `false`/`null` are falsy) — the
    `$borders` flag is passed as `1`/`0` and tested `== 1`, not bare.
  - zsh gotcha: don't re-`local` a name already declared in theme resolution
    (`_a`/`_b`) — a redeclare echoes `name=''` to stdout.

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

## Ideas / not yet built

Recorded so they don't get lost. None of these are started — don't implement
without asking; the design questions below are unsettled.

- **Interval limits** (raised 2026-08-10). User-configurable spend limits over
  intervals *shorter* than the reset windows the API reports. Today every window
  rendered is one Anthropic itself reports (monthly `$`-cap, 7d, per-model, 5h),
  and there's no notion of a self-imposed budget — so you can burn most of a
  monthly cap in week one and the bar still looks comfortable right up until it
  isn't. The point is pacing inside a window (e.g. a daily or per-session ceiling
  carved out of the monthly cap).

  Treat this as a new **derived limit type**, not another render toggle on the
  existing windows. Open questions:
  - Derived or absolute? `cap ÷ intervals elapsed` (a pace line that tracks the
    real cap) vs. a flat number the user sets.
  - Where does per-interval spend come from? The API reports **cumulative window
    totals, not per-interval deltas**, so this likely needs local state
    alongside the usage cache (which is keyed by `accountUuid` — see *Caching*
    in the README and the cache section in `claude-usage.zsh`).
  - How it renders in **both** pretty and `--table` modes, and whether it
    participates in the `spend_on` gate that decides if the `$` group shows at
    all.
