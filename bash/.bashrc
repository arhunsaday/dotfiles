# Bash config — Git Bash on Windows, Linux servers. The mac uses zsh.

# Same single secrets file as zsh (see zsh/.config/zsh/exports.zsh, secrets.env.example)
export SECRETS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"
export SECRETS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/secrets"
if [ -r "$SECRETS_FILE" ]; then
  . "$SECRETS_FILE"
fi

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -d "$HOME/.rd/bin" ] && export PATH="$HOME/.rd/bin:$PATH"
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# Everything below is for interactive shells only
[[ $- == *i* ]] || return

# ==============================================================================
# General configuration
# ==============================================================================

HISTCONTROL=ignoreboth:erasedups
HISTSIZE=1000000
HISTFILESIZE=1000000
shopt -s histappend checkwinsize globstar
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# Window/tab title = current dir (terminals otherwise show the launcher, e.g. cmd.exe)
_set_title() { printf '\e]0;%s\a' "${PWD/#$HOME/\~}"; }
PROMPT_COMMAND="_set_title; $PROMPT_COMMAND"

export EDITOR=vim VISUAL=vim

export BAT_THEME="ansi"
export FZF_DEFAULT_COMMAND="fd --type f --follow --exclude node_modules"
export FZF_DEFAULT_OPTS=$FZF_DEFAULT_OPTS' --color fg:-1,bg:-1,hl:65,fg+:33,bg+:-1,hl+:108 --color info:108,prompt:109,spinner:108,pointer:168,marker:168'

# Colorful man pages
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# Vi mode with some Emacs control keys, block cursor in normal mode (as in main.zsh)
set -o vi
bind 'set show-mode-in-prompt on'
bind 'set vi-ins-mode-string \1\e[5 q\2'
bind 'set vi-cmd-mode-string \1\e[1 q\2'
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'
bind 'set colored-stats on'
bind -m vi-insert '"\C-a": beginning-of-line'
bind -m vi-insert '"\C-e": end-of-line'
bind -m vi-insert '"\C-k": kill-line'
bind -m vi-insert '"\C-l": clear-screen'
bind -m vi-insert '"\C-u": unix-line-discard'
bind -m vi-insert '"\C-w": backward-kill-word'
bind -m vi-insert '"\C-p": history-search-backward'
bind -m vi-insert '"\C-n": history-search-forward'

# ==============================================================================
# Tools
# ==============================================================================

# Init scripts are cached and regenerated when the tool's binary changes:
# spawning a process costs ~200ms on Windows, so this saves about a second
_cached_init() {
  local file="${XDG_CACHE_HOME:-$HOME/.cache}/bash-init/$1.sh" bin
  bin=$(type -P "$1") || return
  if [[ ! -s $file || $bin -nt $file ]]; then
    mkdir -p "${file%/*}"
    "${@:2}" > "$file"
  fi
  . "$file"
}
_cached_init starship starship init bash --print-full-init
_cached_init zoxide zoxide init bash
_cached_init fzf fzf --bash

# mise activate re-runs mise at every prompt, and mise takes ~3s to start on
# this Windows machine: only put its shims on the PATH there
if [[ $OSTYPE == msys || $OSTYPE == cygwin ]]; then
  [ -d "$HOME/AppData/Local/mise/shims" ] && export PATH="$HOME/AppData/Local/mise/shims:$PATH"
else
  _cached_init mise mise activate bash
fi

# ==============================================================================
# Aliases
# ==============================================================================

alias mv='mv -i'
alias rm='rm -rfi'
alias cp='cp -i'
alias ls='ls -F --color=auto'
alias grep='grep --color=auto'

alias dot='git -C "${DOTFILES_DIR:-$HOME/dotfiles}"'
alias g='git'
alias gg='lazygit'
alias lg='lazygit'
alias x="git add . && git commit -m 'x' && git push"
alias y='git add -A && git commit --amend --no-edit && git push --force-with-lease'

if command -v eza >/dev/null; then
  alias l='eza --icons'
  alias la='eza -a --icons'
  alias ll='eza -l --icons'
  alias lla='eza -la --icons'
fi

alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
alias fv="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}' | xargs -I{} $EDITOR {}"

alias v='vim'
alias nv='nvim'
alias c='code -r'
alias k='kubectl'
alias p='pnpm'
alias hs='history | grep'

# ==============================================================================
# Functions
# ==============================================================================

mkcd() {
  mkdir -p "$1" && cd "$1"
}

cl() {
  builtin cd "${1:-$HOME}" && ls -F --color=auto
}

up() {
  local n=${1:-1} dir=$PWD
  while (( n-- > 0 )); do dir=$(dirname "$dir"); done
  cd "$dir"
}

cht() {
  curl "https://cheat.sh/${1:?Usage: cht <command>}"
}

# Manage the single secrets file ($SECRETS_FILE) and key folder ($SECRETS_DIR) — same as secrets() in functions.zsh
secrets() {
  local file=$SECRETS_FILE dir=$SECRETS_DIR
  case ${1:-edit} in
    edit|e)
      [ -e "$file" ] || { mkdir -p "$(dirname "$file")" && install -m 600 /dev/null "$file"; }
      ${EDITOR:-vi} "$file" && secrets reload
      ;;
    reload|r)
      [ -r "$file" ] || { echo "secrets: no $file" >&2; return 1; }
      . "$file" && echo "secrets: reloaded from $file"
      ;;
    list|ls|l)
      [ -r "$file" ] || { echo "secrets: no $file" >&2; return 1; }
      sed -nE 's/^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/  \1/p' "$file"
      [ -d "$dir" ] && find "$dir" -type f | sed "s|^$dir/|  secrets/|"
      ;;
    path|p) echo "$file" ;;
    dir|d) echo "$dir" ;;
    *) echo "usage: secrets [edit|reload|list|path|dir]" >&2; return 1 ;;
  esac
}

# ==============================================================================
# Windows (Git Bash)
# ==============================================================================

if [[ $OSTYPE == msys || $OSTYPE == cygwin ]]; then
  alias open='start ""'
  if command -v win32yank >/dev/null; then
    alias pbcopy='win32yank -i --crlf'
    alias pbpaste='win32yank -o --lf'
  fi

  _dot_scripts="${DOTFILES_DIR:-$HOME/repos/dotfiles}/~windows/scripts"
  theme() { powershell.exe -NoProfile -File "$(cygpath -w "$_dot_scripts/switch-theme.ps1")" "$@"; }
  wallpaper() { powershell.exe -NoProfile -File "$(cygpath -w "$_dot_scripts/set-wallpaper.ps1")" "$(cygpath -w "${1:?Usage: wallpaper <image>}")"; }

  # No standalone install (the proxy blocks the download): use the binary
  # bundled with the VS Code extension, newest version first
  if ! command -v claude >/dev/null; then
    claude() {
      local bin
      bin=$(printf '%s\n' "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude.exe | sort -V | tail -n 1)
      if [[ ! -x $bin ]]; then
        echo 'claude not found: install the VS Code extension' >&2
        return 127
      fi
      "$bin" "$@"
    }
  fi
fi
