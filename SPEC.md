# Switchboard – macOS app spec (V1)

Build a native macOS app called Switchboard: a lightweight, agent-agnostic manager
for AI coding-agent sessions (Claude Code, Codex, Gemini CLI, Cursor's agent CLI).
Switchboard itself has NO coding intelligence. It is a proxy/shell around the
user's chosen agent, and it follows each agent's own conventions rather than
inventing its own. Open source, free, distributed as a signed + notarized
Homebrew cask.

## Tech stack
- Swift + SwiftUI, macOS 14+.
- SwiftTerm for embedded terminals (one real PTY per session, user's login shell).
- Linear via Linear's hosted MCP server with OAuth, so any user signs in with
  their own account. Switchboard acts as an MCP client.
- GitHub via MCP, with the `gh` CLI as fallback, for PR info.
- Session status from each agent's own hooks / status line where available.
  Never scrape terminal output.
- Local persistence (SwiftData or JSON in Application Support).

## Settings
- Default agent: Claude Code | Codex | Gemini CLI | Cursor agent.
- Home folder: root for everything. Contains scratch folders, temp ticket
  folders, and user repos. Repos are discovered by scanning for git repos up to
  2 levels deep below it.
- Temp cleanup: delete kept temp sessions after N days (default 30).
- Session list width: one quarter | one third (default) | one half of the
  window, applied at launch and when changed.
- Linear and GitHub sign-in.

## Layout
Full-screen window, split 1/3 left, 2/3 right by default (see Settings).
- Left: search bar + repo dropdown at the top, then the session list.
- Right: a pure terminal for the selected session. No diffs, editor, or review
  panes. (Diffs in V1 = user runs `git diff` / `gh pr diff` in the terminal.)

## Data model
- Many-to-many: a folder can have many tickets, a ticket can span many folders/repos.
- The SESSION is the link: each session has exactly one folder, at most one
  ticket, one agent, and zero or more PRs.
- Multiple sessions on one ticket get suffixes: XYZ-123-A, XYZ-123-B, XYZ-123-C.
- A row owns its terminal and folder. If the user quits the agent (Ctrl-C) and
  starts it again in that terminal, it is still the same row; the row simply
  points at the new agent conversation.
- Row-to-conversation mapping: set an env var (e.g. SWITCHBOARD_ROW_ID) in each
  terminal. The agent's SessionStart-style hook reports the row ID plus the
  agent's conversation ID, so the app maps them exactly. No timestamp guessing.

## Creating sessions
- "+" button opens a picker: choose a folder or a ticket, plus an agent
  selector preset to the default agent (overridable per session).
- Folder that is a git repo: start the agent in the repo folder itself
  (`claude`, not `claude -w`). Worktrees come only from an explicit move to a
  worktree, using the agent's own convention (`claude -w`).
- Folder that is not a repo: start the agent directly in that folder.
- Scratch session: start in a scratch folder under the home folder, for random
  questions. Lives in a Scratch group.

## Search bar + repo dropdown
- One search box accepting: a Linear ticket ID, a Linear URL, or a GitHub PR URL.
  It detects the type automatically.
- Searches any ticket the user can access, not only assigned ones. By default
  the list shows the user's assigned tickets (polled roughly every minute).
- If local sessions already exist for that ticket, show them first, each with a
  "+" to add another session there.
- If nothing local exists:
  - Repo dropdown = none: fetch the ticket, create a temp folder under the home
    folder (e.g. tickets/XYZ-123), and start a planning session there.
  - Repo dropdown = a repo: start the agent in that repo's folder.
- PR URL: start a session for reviewing that PR (no checkout). Optionally type
  the PR link into the terminal WITHOUT pressing enter, so the user finishes the prompt.
- The search bar is search only, never a prompt to the agent.

## Tickets inside existing sessions
- If the user mentions a ticket in a folder session ("let's work on XYZ-123"),
  detect it via hooks and tag the session with the ticket. Do NOT move it.
- Only move to a worktree when the user explicitly asks. Then: user picks a
  repo, Switchboard starts a fresh agent session in the new worktree, passes the
  ticket plus a summary of the conversation so far, and swaps it into the same row.
- Same flow converts a temp planning folder into a real worktree once ready.

## Session row (left panel)
- Title: the agent's own conversation name (e.g. Claude's session title or
  /rename). Fallback: ticket ID, then folder name.
- Working state: idle, working, sub-agents running, needs input, finished.
- Latest status-line text from the agent.
- Icon: branch icon = worktree session, folder icon = plain folder, distinct
  icon = scratch / temp.
- Agent-dependent: Claude exposes rich status; other agents may show simpler states.

## Session status bar
- Agent and model, folder/worktree path, ticket ID, linked PR(s).
- PR icons per PR; merged PRs show a purple merged icon. Nothing else happens
  automatically on merge (user automates via their own skills/hooks).
- Quick toggle to set the Linear ticket to any status Linear offers for that
  ticket's team. Ticket status is always manual.

## Sorting and grouping
- Sort by ticket number or folder name.
- Group by Linear project, by folder, or by ticket (sessions on one ticket nest
  under a collapsible parent row showing all its PRs).
- Scratch group and Temp group always at the bottom.

## Closing sessions
- Closing a temp session asks whether to delete its folder.
- If no: move it to the Temp section at the bottom. Auto-delete after N days.
- Worktree cleanup is left to the agent (e.g. Claude asks keep/remove itself).

## Restarts
- On relaunch, restore all rows and reopen each with the agent's own resume
  command (e.g. `claude --resume <id>`). No tmux.

## Notifications
- Forward agent "finished" / "needs input" events as macOS notifications plus a
  badge on the row.

## Keyboard shortcuts
- Cmd-1..Cmd-9: focus the session at that position in the current order and
  move focus to its terminal.
- Cmd-Up / Cmd-Down: previous / next session. Intercept before the terminal view.
- Cmd-N: new session (same as "+").

## Offline / signed out
- Folder and scratch sessions keep working. Ticket and PR features grey out.

## Out of scope for V1
- Diff viewer, syntax highlighting, editors, language servers.
- Ticketing systems other than Linear.
- Automatic ticket status changes.

## Build order
1. Split layout, SwiftTerm terminals, folder + scratch sessions, "+" picker with
   repo detection and agent selector.
2. Row/conversation mapping via env var + hooks; live row status; notifications.
3. Keyboard navigation; sorting and grouping; restore on relaunch.
4. Linear sign-in, search bar, repo dropdown, temp ticket folders, worktree handover.
5. GitHub PRs, merged icons, PR URL search, status bar ticket toggle.
6. Temp section and N-day cleanup. Homebrew cask packaging.
