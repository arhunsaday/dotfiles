# Default apps
export BROWSER=Arc
export EDITOR=nvim
export VISUAL=nvim

# Fzf config
export FZF_DEFAULT_COMMAND="fd --type f --follow --exclude node_modules"
export FZF_COMPLETION_TRIGGER=''

# Colors
export BAT_THEME="ansi"
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export FZF_DEFAULT_OPTS=$FZF_DEFAULT_OPTS' --color fg:-1,bg:-1,hl:65,fg+:33,bg+:-1,hl+:108 --color info:108,prompt:109,spinner:108,pointer:168,marker:168'

# Colorful man pages
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# Other
# pnpm derives its store dir from this; a wrong value silently moves the store
# and forces a full node_modules rebuild on every repo.
if [[ $OSTYPE == darwin* ]]; then
  export PNPM_HOME="$HOME/Library/pnpm"
else
  export PNPM_HOME="$HOME/.local/share/pnpm"
fi
# Zscaler re-signs TLS, and node's own CA store does not read .npmrc. Without this,
# postinstall scripts that download things fail with UNABLE_TO_GET_ISSUER_CERT_LOCALLY.
_zscaler_ca="$HOME/Documents/zscaler-certificates/ZscalerRootCertificate-2048-SHA256.pem"
[[ -f $_zscaler_ca ]] && export NODE_EXTRA_CA_CERTS="$_zscaler_ca"
unset _zscaler_ca

export GOROOT="/opt/homebrew/opt/go/libexec"
export GOPATH="$HOME/.go"
export GOBIN=$GOPATH/bin
export TEXPATH="/Library/TeX/texbin"
export VSCODE_PROFILES=("Frontend/angular" "Default" "Backend/devops" "Minimal")

# Path
export PATH=/var/lib/flatpak/exports/bin:$HOME/.cargo/bin:$HOME/.deno/bin:$HOME/.local:$HOME/.local/bin:$HOME/.local/scripts:$HOME/.local/share/pop-launcher/scripts:$PNPM_HOME:$GOPATH/bin:$GOROOT/bin:$PATH:$TEXPATH

# ==============================================================================
# Secrets
# ==============================================================================
# Every API key and token lives in one file that is NOT part of this repo, so
# nothing secret can be committed by accident. Template: secrets.env.example.
# Manage it with `secrets` (see functions.zsh); inspect it with `secrets list`.
#
# Loaded from .zshenv rather than .zshrc so scripts and non-interactive shells
# get the keys too — a cron job or an editor plugin has no interactive shell.
export SECRETS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"
if [[ -r $SECRETS_FILE ]]; then
  # a readable-by-anyone key file is worse than no key file
  _secrets_perm=$(stat -f '%OLp' "$SECRETS_FILE" 2>/dev/null || stat -c '%a' "$SECRETS_FILE" 2>/dev/null)
  [[ $_secrets_perm == 600 ]] || print -u2 "secrets: $SECRETS_FILE is mode ${_secrets_perm:-?} — run: chmod 600 \$SECRETS_FILE"
  unset _secrets_perm
  source "$SECRETS_FILE"
fi
