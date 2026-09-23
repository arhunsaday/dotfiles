source $HOME/.config/zsh/main.zsh
source $HOME/.config/zsh/functions.zsh
source $HOME/.config/zsh/aliases.zsh
source $HOME/.config/zsh/ai-shell.zsh

# Asdf
# . /opt/homebrew/opt/asdf/libexec/asdf.sh

# fnm (installed via Homebrew, so it is already on PATH)
eval "$(fnm env --use-on-cd --shell zsh --log-level error)"

# Scaleway CLI autocomplete initialization.
eval "$(scw autocomplete script shell=zsh)"

# Sdkman
export SDKMAN_DIR="$HOMEBREW_PREFIX/opt/sdkman-cli/libexec"
[[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]] && source "${SDKMAN_DIR}/bin/sdkman-init.sh"

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools
# Added by Antigravity
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="/Users/goblingarry/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# ArgoCD, Scaleway, API keys... all live in ~/.config/secrets.env — `secrets edit`
