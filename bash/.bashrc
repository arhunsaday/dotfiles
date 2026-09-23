PROMPT_COMMAND='export PS1="\n\[\033[1;94m\]\w\[\033[0m\] \[\033[1;32m\] $(__git_ps1 "%s")\[\033[0m\]\n❱ "'
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
HHISTCONTROL=ignoreboth
HISTSIZE=1000000000
SAVEHIST=1000000000
parse_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

# PROMPT_COMMAND='export PS1="\n\[\033[1;94m\]\w\[\033[0m\] \[\033[1;32m\] $(__git_ps1 "%s")\[\033[0m\]\n❱ "'
export PS1="\u@\h \[\033[32m\]\w\[\033[33m\]\$(parse_git_branch)\[\033[00m\] \n ❯ "
. "$HOME/.cargo/env"

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="/Users/goblingarry/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# Same single secrets file as zsh (see zsh/.config/zsh/exports.zsh, secrets.env.example)
export SECRETS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"
if [ -r "$SECRETS_FILE" ]; then
  . "$SECRETS_FILE"
fi
