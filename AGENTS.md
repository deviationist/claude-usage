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
  Endpoint shapes vary by plan; keep all four paths working.
- **Theming** (pretty only): a theme sets colours / thresholds / glyphs /
  brackets / dim, then per-field `CLAUDE_USAGE_*` env vars override on top, then
  `--no-color` / `NO_COLOR` blank all SGR. Colours/glyphs are passed into jq as
  args — do not re-hardcode them in the jq programs.

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
- Default `--pretty` output is a public contract (the claude-statusline project
  parses/renders it) — changing default colours/glyphs is a breaking change.
