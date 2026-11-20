# Switchboard

A native macOS app for running many AI coding-agent sessions side by side.
It works with Claude Code, Codex, Gemini CLI and Cursor's agent CLI.

Switchboard does no coding itself. Each session is a real terminal running your
login shell and the agent you chose, and Switchboard keeps track of them: which
folder, worktree, Linear ticket and pull requests each one belongs to, and
whether the agent is working, waiting for you, or finished.

## Install

```sh
brew install --cask 110digitallabs/tap/switchboard
```

Requires macOS 14 (Sonoma) or later, plus at least one agent CLI on your `PATH`:
`claude`, `codex`, `gemini` or `cursor-agent`.

## What it does

- **Sessions in a list, terminal on the right.** Pick a folder, a ticket or a
  scratch space, and the agent starts there. In a git repo it starts in the
  repo folder itself (`claude`, not `claude -w`); "Move to worktree" hands a
  session over to the agent's own worktree mode.
- **Live status.** Rows show the conversation title, the working state
  (working, sub-agents running, needs input, finished) and the agent's latest
  status-line text. "Finished" and "needs input" also arrive as macOS
  notifications.
- **Linear.** Sign in with your own Linear account through Linear's hosted MCP
  server. Paste a ticket ID or URL to jump to its sessions or start one, and
  set the ticket's status from the status bar.
- **GitHub.** Linked pull requests appear on each session, and merged ones are
  marked. Paste a PR URL to start a review session. Uses GitHub's MCP server,
  or the `gh` CLI as a fallback.
- **Survives relaunch.** Every row reopens with the agent's own resume command,
  such as `claude --resume <id>`. No tmux.
- **Temp and scratch folders.** Ticket planning folders you keep are cleaned up
  after a number of days you choose (30 by default).

### Keyboard

| Keys | Action |
| --- | --- |
| ⌘N | New session |
| ⌘1 – ⌘9 | Jump to the session at that position |
| ⌘↑ / ⌘↓ | Previous / next session |

## How status works

Switchboard never scrapes terminal output. Each terminal gets a
`SWITCHBOARD_ROW_ID` variable, and the agent's own hooks report events back to
the app over a local socket, along with the row ID and the agent's conversation
ID.

Switchboard does not edit your agent configuration. Hook settings live in
`~/Library/Application Support/Switchboard/` and are added on each launch only:

- **Claude Code:** `--settings`, layered over your own settings. Your status
  line still runs.
- **Codex:** `-c` overrides. Codex runs non-managed hooks only after you trust
  them once in `/hooks`. Until then, only "finished" is reported.
- **Gemini CLI:** system defaults passed through the environment.
- **Cursor agent:** there is no per-launch way to add hooks, so its rows show
  less detail.

## Build from source

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Switchboard.xcodeproj -scheme Switchboard \
  -skipPackagePluginValidation build
```

Run the tests the same way with `test -destination 'platform=macOS'`.
`-skipPackagePluginValidation` is needed for SwiftTerm's build-info plugin.

The app icon is drawn in code. Edit `scripts/make-icon.swift`, then run
`scripts/make-icon.sh`.

## Releasing

`scripts/release.sh` builds a Developer ID signed, notarized and stapled
`Switchboard-<version>.zip` and prints its sha256 for `Casks/switchboard.rb`.
The script's header lists the environment variables it needs. It does not bump
the version, tag or upload anything.

## License

MIT. See [LICENSE](LICENSE).
