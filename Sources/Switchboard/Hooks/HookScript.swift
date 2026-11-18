import Foundation

/// The POSIX sh helper that agents' hooks run. It needs only sh, nc and
/// plutil, all part of macOS.
///
/// Wire format sent to the app's Unix socket, one message per connection:
///
///     SWB1 \t <agent> \t <event> \t <row id> \t <payload byte count> \n
///     <payload JSON> <optional trailing text, e.g. rendered status line>
///
/// Hook events are sent in the foreground so they reach the app in the order
/// the agent fired them; the app reads the socket off the main thread, so this
/// takes milliseconds. The status line is sent in the background because its
/// order does not matter and the agent waits on its output.
enum HookScript {
    static let contents = #"""
    #!/bin/sh
    # Switchboard hook helper. Installed by Switchboard; changes are overwritten.
    #   switchboard-hook <agent> <event>          hook JSON on stdin
    #   switchboard-hook <agent> notify <json>    payload as an argument (Codex notify)
    #   switchboard-hook claude statusline        wraps the user's own status line
    # Never fails and never prints anything except the user's status line.

    agent=${1:-unknown}
    event=${2:-unknown}
    row=${SWITCHBOARD_ROW_ID:-}
    sock=${SWITCHBOARD_SOCKET:-}

    deliverable() {
      [ -n "$row" ] && [ -n "$sock" ] && [ -S "$sock" ]
    }

    # $1 = payload JSON, $2 = optional trailing text.
    message() {
      len=$(printf '%s' "$1" | wc -c | tr -d ' ')
      printf 'SWB1\t%s\t%s\t%s\t%s\n' "$agent" "$event" "$row" "$len"
      printf '%s' "$1"
      printf '%s' "$2"
    }

    send() {
      deliverable || return 0
      message "$1" "$2" | nc -U -w 1 "$sock" >/dev/null 2>&1
      return 0
    }

    send_in_background() {
      deliverable || return 0
      ( message "$1" "$2" | nc -U -w 1 "$sock" ) >/dev/null 2>&1 </dev/null &
      return 0
    }

    json_value() { # $1 = JSON, $2 = key path
      printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw -o - - 2>/dev/null
    }

    # The user-level status line command only. Project-level settings come from
    # a directory named in the payload, and running commands from them would
    # bypass Claude Code's own workspace-trust check, so they are not consulted.
    user_statusline_command() {
      config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
      f="$config/settings.json"
      [ -f "$f" ] || return 1
      cmd=$(/usr/bin/plutil -extract statusLine.command raw -o - "$f" 2>/dev/null) || return 1
      case "$cmd" in ""|*switchboard-hook*) return 1 ;; esac
      printf '%s' "$cmd"
    }

    case "$event" in
      statusline)
        payload=$(cat)
        out=
        if cmd=$(user_statusline_command "$payload"); then
          # The trailing x keeps the command's own trailing newlines intact.
          out=$(printf '%s' "$payload" | /bin/bash -c "$cmd" 2>/dev/null; printf x)
          out=${out%x}
          printf '%s' "$out"
        fi
        send_in_background "$payload" "$out"
        ;;
      notify)
        send "${3:-}"
        ;;
      *)
        payload=$(cat)
        send "$payload"
        ;;
    esac
    exit 0
    """#
}
