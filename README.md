<p align="center">
  <img src="assets/logo.svg" width="104" alt="horae logo">
</p>

# horae

> One TOML recipe + one launchd trigger to unify every "run-a-command-to-update" task on macOS.

**English** · [简体中文](README.zh-CN.md)

`horae` is a tiny update orchestrator for macOS. Package managers each ship their own auto-update story — Homebrew has a tap, npm needs a script, pipx / cargo / gcloud each do their own thing — so you end up with a separate launchd agent, script, and log convention per tool. `horae` replaces all of that with **one `recipes.toml`**: declare each update source once, and a single launchd agent runs them on their own schedules, with unified state, logging, notifications, and a `status` view.

## Why

- **Fragmented today**: each updater = its own agent + script + log path. No single "did it run / what changed / when's next" view.
- **horae**: one config, one trigger, one log, one `status`. Adding a source = adding a `[[step]]`.

## Features

- **Declarative recipe** — every update source is a `[[step]]` in `recipes.toml` (command or shell, cadence, timeout, env).
- **One launchd trigger** — a single LaunchAgent wakes hourly; each source runs on its own `cadence` (anacron-style).
- **Sleep / shutdown catch-up** — due-ness is "time since last success", so overdue sources run on the next wake — no reliance on launchd's own catch-up.
- **Failure backoff** — a source that keeps failing retries on its cadence, not every tick (no notification spam).
- **Safe subprocess execution** — per-step timeout, process-group kill (no hung interactive updaters), bounded output capture.
- **Unified observability** — per-source state via `status`, plus daily structured logs with stderr tails on failure.
- **Native notifications** — macOS notifications via `osascript`, with `always` / `on_change` / `on_failure` / `never` policies.
- **Single static binary** — Go, stdlib + one TOML library, ~zero runtime deps. Install once, runs for years.

## Requirements

- **macOS** (uses launchd; Apple Silicon or Intel).
- Build from source: **Go 1.26+**. For development: `golangci-lint` (optional).

## Install

```bash
git clone https://github.com/yaoguohh/horae.git
cd horae
cp recipes.toml.example ~/.config/horae/recipes.toml   # then edit it
make install   # build binary → ~/.local/bin, generate & load the LaunchAgent
```

`make install` substitutes your `$HOME` into the LaunchAgent plist, so it works for any user.

- Stop scheduling: `launchctl bootout gui/$(id -u)/com.user.horae`
- Remove entirely: `make uninstall`

## Quick start

A minimal `recipes.toml`:

```toml
[defaults]
timeout = "15m"
notify  = "on_change"   # always | never | on_change | on_failure

[[step]]
id      = "brew"
label   = "Homebrew"
cadence = "3h"
shell   = "brew update && brew upgrade && brew cleanup"

[[step]]
id      = "npm-globals"
label   = "npm globals"
cadence = "3h"
shell   = "npx npm-check-updates -g -u && npm update -g"
```

```bash
horae run --dry-run   # show what would run, execute nothing
horae run --force     # run everything now
horae status          # last result + time until next run, per source
```

## Commands

| Command | Description |
|---|---|
| `horae run` | Run every due source (this is what launchd calls) |
| `horae run --force` | Run all enabled sources now, ignoring cadence |
| `horae run --only a,b` | Run only these sources, ignoring cadence |
| `horae run --skip a,b` | Run all due sources except these |
| `horae run --dry-run` | Print what would run; execute nothing |
| `horae status` | Render the per-source status table |
| `horae run --config PATH` | Use an alternate recipe path |

`--only` / `--skip` with an unknown id exits non-zero (catches typos instead of silently doing nothing).

## Configuration

The recipe lives at `~/.config/horae/recipes.toml` (`$XDG_CONFIG_HOME` respected).

| Field | Description |
|---|---|
| `[defaults].timeout` | Default per-step timeout (default `10m`) |
| `[defaults].notify` | `always` / `never` / `on_change` / `on_failure` |
| `[[step]].id` | Unique key; indexes state and logs |
| `[[step]].label` | Display name (defaults to `id`) |
| `[[step]].cadence` | Desired frequency: `s` / `m` / `h` / `d` / `w` (e.g. `3h`, `1d`, `7d`) |
| `[[step]].command` | argv array, no shell (mutually exclusive with `shell`) |
| `[[step]].shell` | Shell snippet, for `&&` / pipes |
| `[[step]].timeout` | Override the default timeout |
| `[[step]].env` | Add / override environment variables (e.g. inject PATH) |
| `[[step]].enabled` | `false` = never run (placeholder); defaults `true` |

**PATH note:** launchd runs with a near-empty PATH. horae prepends `/opt/homebrew/bin` and resolves bare commands against the injected PATH. If a binary lives outside standard dirs (e.g. `~/.local/bin`, `~/.cargo/bin`), use an absolute path or set the step's `env.PATH`.

| Purpose | Path |
|---|---|
| Config | `~/.config/horae/recipes.toml` |
| State (status source) | `~/.local/state/horae/state.toml` |
| Run logs (daily) | `~/Library/Logs/horae/run-YYYYMMDD.log` |
| Binary / agent | `~/.local/bin/horae` / `~/Library/LaunchAgents/com.user.horae.plist` |

## How it works

Trigger frequency and "should this source run" are decoupled:

- A single LaunchAgent wakes `horae run` every hour (`StartInterval`).
- For each step, horae checks `now - last_success >= cadence`. A `cadence = "3h"` source runs roughly every 3h even though the trigger fires hourly.
- Because due-ness is based on *time since last success* (anacron-style, not a fixed wall-clock time), a machine that slept or was powered off simply runs overdue sources on the next wake — catch-up needs no special scheduler support.
- A single-instance file lock prevents overlapping runs; a contended run exits cleanly and is not counted as a failure.

Inspired by [topgrade](https://github.com/topgrade-rs/topgrade) (step + summary model) and `anacron` (cadence + catch-up via a last-run timestamp).

## Migrating from homebrew-autoupdate

```bash
# After horae is installed and verified to take over:
brew autoupdate delete
brew untap homebrew/autoupdate   # `delete` removes the agent but NOT the tap; a leftover tap breaks `brew update`
```

## Development

```bash
make check   # go vet + golangci-lint + go test
make fmt     # gofumpt + goimports
```

Architecture notes: [docs/design.md](docs/design.md).

## License

[MIT](LICENSE).
