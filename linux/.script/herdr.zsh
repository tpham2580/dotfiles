# herdr shell helpers — terminal-side session switching
# sourced from ~/.zshrc
#
# Why these exist: a herdr "named session" is a separate SERVER, not a tmux
# session. There is no in-app switch action, so switching happens from the
# shell via detach -> attach. Inside herdr, use WORKSPACES (ctrl+b s) instead.

# hs — pick a session with fzf and attach (creates it if the name is new)
hs() {
  local sel
  if [ -n "$1" ]; then
    sel="$1"
  else
    sel=$(
      { herdr session list 2>/dev/null | sed 's/^[[:space:]]*//'; echo "default"; } \
        | awk 'NF' | sort -u \
        | fzf --prompt='herdr session> ' --height=40% --reverse \
              --print-query --header='enter an existing or new name' \
        | tail -1
    )
  fi
  [ -z "$sel" ] && return 0
  if [ "$sel" = "default" ]; then
    "$HOME/.script/herdr-attach"
  else
    "$HOME/.script/herdr-attach" --session "$sel"
  fi
}

# hl — list sessions
hl() { herdr session list; }

# ha — attach to the default session
ha() { "$HOME/.script/herdr-attach"; }

# hw — open a directory as a herdr workspace in the running server
#      usage: hw ~/Projects/foo   (defaults to cwd)
hw() {
  local dir="${1:-$PWD}"
  herdr workspace create --cwd "$dir" --label "$(basename "$dir")"
}

# hk — stop a session (fzf picker when no name given)
hk() {
  local sel="${1:-$(herdr session list 2>/dev/null | sed 's/^[[:space:]]*//' | awk 'NF' \
    | fzf --prompt='stop session> ' --height=40% --reverse)}"
  [ -z "$sel" ] && return 0
  herdr session stop "$sel"
}

# --- Alt+s : herdr sessionizer (the ctrl+f tmux-sessionizer replacement) ------
# Outside herdr : fzf over workspaces + projects + named sessions.
#                 enter = open/attach, del = close/delete.
# Inside herdr  : does nothing on purpose — use ctrl+b alt+s there, because a
#                 nested client cannot attach a second session in place.
herdr-sessionizer-widget() {
  if [[ -n "${HERDR_PANE_ID:-}${HERDR_ACTIVE_PANE_ID:-}" ]]; then
    zle -M "inside herdr — use  ctrl+b alt+s  instead"
    return 0
  fi
  BUFFER="$HOME/.script/herdr-sessionizer"
  zle accept-line
}
zle -N herdr-sessionizer-widget
bindkey '\es' herdr-sessionizer-widget

# --- Ctrl+f : open ANY folder as a herdr workspace --------------------------
# The herdr replacement for the old tmux-sessionizer binding.
herdr-sessionize-widget() {
  BUFFER="$HOME/.script/herdr-sessionize"
  zle accept-line
}
zle -N herdr-sessionize-widget
bindkey '^F' herdr-sessionize-widget
