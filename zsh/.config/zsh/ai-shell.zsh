# ~/.config/zsh/ai-shell.zsh — natural-language command assistant
# Sourced from ~/.zshrc:   source $HOME/.config/zsh/ai-shell.zsh
#
# Provides:
#   Ctrl-G           widget: turn the current line (natural language OR a broken
#                    command) into a shell command, in place. Enter to run,
#                    edit/Ctrl-C to reject.
#   ai <request>     print a suggested command onto the next prompt (accept/edit/reject)
#   ai --status      show which backend, model and keys are in use
#   fix [cmd]        fix/improve your last command (or the given one; reads piped
#                    error output as extra context if present)
#   wtf              explain why the last command failed and offer a fix. Re-runs
#                    the command to capture its output, unless it looks like it
#                    changes something — see `wtf --help`.
#
# Backends. With AI_PROVIDER=auto (the default) the first usable one wins:
#   openai       OPENAI_API_KEY    + curl + jq    sub-second
#   anthropic    ANTHROPIC_API_KEY + curl + jq    sub-second
#   claude-cli   the `claude` CLI, no key needed  ~3s floor (Node boot + auth)
# Pin one with AI_PROVIDER=openai|anthropic|claude-cli.
#
# Config. Keys belong in ~/.config/secrets.env (`secrets edit`); the rest can go
# anywhere sourced before this file.
#   AI_PROVIDER          auto | openai | anthropic | claude-cli  (default: auto)
#   AI_OPENAI_MODEL      OpenAI model id      (default: gpt-6-luna)
#   AI_ANTHROPIC_MODEL   Anthropic model id   (default: claude-haiku-4-5-20251001)
#   AI_CLI_MODEL         claude CLI alias     (default: haiku)
#   AI_REASONING_EFFORT  OpenAI reasoning effort: none|low|medium|high|xhigh|max,
#                        or '' to omit the field entirely for endpoints that
#                        reject it (default: none — these are one-liners, not
#                        puzzles. `wtf` diagnoses better at low.)
#   AI_MAX_TOKENS        output cap           (default: 1024)
#   AI_TIMEOUT           seconds per request  (default: 45)
#   OPENAI_BASE_URL      (default: https://api.openai.com/v1) — any OpenAI-compatible
#                        endpoint works here: OpenRouter, Ollama, vLLM, a gateway...
#   ANTHROPIC_BASE_URL   (default: https://api.anthropic.com)
#   NO_COLOR             set to disable all styling

: ${AI_PROVIDER:=auto}
: ${AI_OPENAI_MODEL:=gpt-6-luna}
: ${AI_ANTHROPIC_MODEL:=claude-haiku-4-5-20251001}
: ${AI_CLI_MODEL:=haiku}
: ${AI_REASONING_EFFORT:=none}
: ${AI_MAX_TOKENS:=1024}
: ${AI_TIMEOUT:=45}

# ---------------------------------------------------------------- styling ----

_ai_style() {
  if [[ -t 2 && -z $NO_COLOR ]]; then
    _AI_BOLD=$'\e[1m'; _AI_DIM=$'\e[2m';    _AI_RED=$'\e[31m'
    _AI_GRN=$'\e[32m'; _AI_YEL=$'\e[33m';   _AI_CYA=$'\e[36m'
    _AI_OFF=$'\e[0m'
  else
    _AI_BOLD=''; _AI_DIM=''; _AI_RED=''
    _AI_GRN='';  _AI_YEL=''; _AI_CYA=''
    _AI_OFF=''
  fi
}
_ai_style

_AI_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
_AI_THINKING='thinking'
_AI_MSG_NONE='no suggestion'
_AI_SPIN_MS=0.08

# A labelled, wrapped field:  "  why   some long explanation that folds nicely"
_ai_field() {
  local label=$1 color=$2 text=$3
  # COLUMNS is unset or nonsense when there is no terminal attached
  local cols=${COLUMNS:-0}
  (( cols < 40 )) && cols=80
  local width=$(( cols - 9 ))

  print -r -- "$text" | fold -s -w $width | {
    local first=1 line
    while IFS= read -r line; do
      if (( first )); then
        printf '  %s%-5s%s %s\n' "$color" "$label" "$_AI_OFF" "$line"
        first=0
      else
        printf '        %s\n' "$line"
      fi
    done
  }
}

_ai_note() {
  printf '  %s%s%s\n' "$_AI_DIM" "$1" "$_AI_OFF" >&2
}

_ai_err() {
  printf '  %s✖%s %s\n' "$_AI_RED" "$_AI_OFF" "$1" >&2
}

# --------------------------------------------------------------- prompts -----

_AI_CMD_SYS='You translate a request into a single shell command for macOS zsh.
Your entire response is pasted straight onto the user'"'"'s command line, so it must be
runnable text and nothing else.

Rules:
- Output ONLY the command. No explanation, no commentary, no preamble, no trailing
  notes, no markdown, no code fences, no backticks, no leading $ or #.
- NEVER ask a question. NEVER reply with prose. NEVER say the request is ambiguous,
  unclear, risky, or that you need more information. There is no conversation here:
  the user cannot answer you, and any non-command text just has to be deleted by hand.
- If details are missing, DO NOT ask - commit to the most likely interpretation and
  emit the command anyway. Where a value genuinely cannot be guessed, inline an
  obvious ALL-CAPS placeholder the user can overwrite (<FILE>, <DIR>, <BRANCH>,
  <PORT>, <PATTERN>) rather than refusing or explaining.
- A best guess with placeholders always beats a question or a caveat. Guess.
- Prefer one line; use && or ; to chain when needed.
- If the input is already a shell command that is broken or could be improved, output a corrected/improved version instead.
- Prefer standard macOS/BSD tools and widely-installed CLIs.
- Destructive commands (rm, kill, dd, git reset --hard, ...) are fine to emit when
  asked - the user reviews the line before pressing Enter. Do not warn, do not soften,
  do not add a safety flag that was not requested.
- Only if the request maps to no command at all, output exactly:
  echo "could not determine a command"'

_AI_WTF_SYS='You diagnose a failed shell command on macOS zsh.

Reply in EXACTLY this format and nothing else:
WHY: <1-3 sentences naming the actual cause>
CMD: <one corrected shell command, or the word NONE>

Rules:
- WHY explains the underlying cause. Do not merely restate the error text back.
- Be concrete: name the missing binary, the wrong flag, the bad path, the exit code
  meaning. If the output is truncated or absent, reason from the command itself and
  say what you are assuming.
- CMD must be runnable as-is on macOS zsh. No markdown, no fences, no leading $.
- Use ALL-CAPS placeholders (<FILE>, <BRANCH>) only where a value truly cannot be guessed.
- Use CMD: NONE when no single command would fix it - for example when the user must
  choose between real alternatives, or the fix is to edit a file.
- Never ask a question. Never add keys beyond WHY and CMD.

When OUTPUT is "(unavailable)" you have NOT seen the error. You are working from the
command text alone, which is rarely enough:
- Begin WHY with "Without the error text, most likely: ".
- Give the single most likely cause, phrased as likely, never as fact.
- Never invent specifics you cannot know - no exit-code meanings, no file names, no
  claims about what is or is not staged, installed, running or configured.
- If the command commonly fails for several unrelated reasons, say that instead of
  picking one.'

# --------------------------------------------------------------- backend -----

# Strip code fences / leading blank lines the model might emit.
_ai_strip() {
  awk 'BEGIN{started=0}
       /^[[:space:]]*```/ {next}
       !started && /^[[:space:]]*$/ {next}
       {started=1; print}' \
  | sed -e 's/^[[:space:]]*\$[[:space:]]//'
}

_ai_has_http() { command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 }

# Which backend this invocation will actually use (empty if none can run).
_ai_provider() {
  local p=$AI_PROVIDER
  if [[ $p == auto ]]; then
    if   [[ -n $OPENAI_API_KEY    ]] && _ai_has_http; then p=openai
    elif [[ -n $ANTHROPIC_API_KEY ]] && _ai_has_http; then p=anthropic
    elif command -v claude >/dev/null 2>&1;            then p=claude-cli
    else p=''
    fi
  fi
  print -r -- "$p"
}

# url, json payload, extra curl args -> response body. Reports HTTP and transport
# errors instead of swallowing them: a wrong model id or a dead gateway should say so.
_ai_post() {
  local url=$1 payload=$2; shift 2
  local raw code body msg
  if ! raw=$(curl -sS -m "$AI_TIMEOUT" -w $'\n%{http_code}' \
               -H 'content-type: application/json' "$@" -d "$payload" "$url" 2>&1); then
    _ai_err "${${raw%$'\n'*}:-request failed}"
    return 1
  fi
  code=${raw##*$'\n'}
  body=${raw%$'\n'*}
  if [[ $code != 2* ]]; then
    msg=$(print -r -- "$body" | jq -r '.error.message // .error // empty' 2>/dev/null)
    _ai_err "HTTP $code — ${msg:-${body:0:200}}"
    return 1
  fi
  print -r -- "$body"
}

# body, jq filter for the text, jq filter for the stop reason -> clean text.
_ai_take() {
  local body=$1 text stop
  text=$(print -r -- "$body" | jq -r "$2" 2>/dev/null)
  stop=$(print -r -- "$body" | jq -r "$3" 2>/dev/null)
  if [[ -z ${text//[[:space:]]/} ]]; then
    # a reasoning model can burn the whole budget before emitting a single token
    case $stop in
      length|max_tokens|max_output_tokens)
        _ai_err "hit the token cap before answering — raise AI_MAX_TOKENS (now $AI_MAX_TOKENS) or lower AI_REASONING_EFFORT" ;;
    esac
    return 1
  fi
  print -r -- "$text" | _ai_strip
}

_ai_gen_openai() {
  [[ -n $OPENAI_API_KEY ]] || { _ai_err "OPENAI_API_KEY is not set — try: secrets edit"; return 1 }
  local base=${OPENAI_BASE_URL:-https://api.openai.com/v1} payload body
  payload=$(jq -n --arg m "$AI_OPENAI_MODEL" --arg sys "$2" --arg u "$1" \
                  --argjson mt "$AI_MAX_TOKENS" --arg eff "$AI_REASONING_EFFORT" \
    '{model:$m, max_completion_tokens:$mt,
      messages:[{role:"system",content:$sys},{role:"user",content:$u}]}
     + (if $eff == "" then {} else {reasoning_effort:$eff} end)')
  body=$(_ai_post "${base%/}/chat/completions" "$payload" \
           -H "authorization: Bearer $OPENAI_API_KEY") || return 1
  _ai_take "$body" '.choices[0].message.content // ""' '.choices[0].finish_reason // ""'
}

_ai_gen_anthropic() {
  [[ -n $ANTHROPIC_API_KEY ]] || { _ai_err "ANTHROPIC_API_KEY is not set — try: secrets edit"; return 1 }
  local base=${ANTHROPIC_BASE_URL:-https://api.anthropic.com} payload body
  payload=$(jq -n --arg m "$AI_ANTHROPIC_MODEL" --arg sys "$2" --arg u "$1" \
                  --argjson mt "$AI_MAX_TOKENS" \
    '{model:$m, max_tokens:$mt, system:$sys, messages:[{role:"user",content:$u}]}')
  body=$(_ai_post "${base%/}/v1/messages" "$payload" \
           -H "x-api-key: $ANTHROPIC_API_KEY" -H 'anthropic-version: 2023-06-01') || return 1
  _ai_take "$body" '[.content[]? | select(.type=="text") | .text] | join("")' '.stop_reason // ""'
}

# Tools disabled -> pure text, never executes anything.
_ai_gen_cli() {
  local err out st msg
  err=$(mktemp)
  out=$(command claude -p --no-session-persistence \
          --model "$AI_CLI_MODEL" \
          --disallowedTools Bash Edit Write Read Glob Grep Task WebFetch WebSearch TodoWrite NotebookEdit \
          --append-system-prompt "$2" \
          -- "$1" 2>| "$err")
  st=$?
  # the CLI warns about unrelated things on stderr on a good run, and prints its
  # real failures on stdout - so trust the exit status, not the stream
  if (( st )) || [[ -z ${out//[[:space:]]/} ]]; then
    msg=$(head -3 "$err")
    [[ -z ${msg//[[:space:]]/} ]] && msg=$(print -r -- "$out" | head -3)
    rm -f "$err"
    [[ -n ${msg//[[:space:]]/} ]] && _ai_err "$msg"
    return 1
  fi
  rm -f "$err"
  print -r -- "$out" | _ai_strip
}

# request string [system prompt] -> text on stdout.
_ai_gen() {
  local req=$1 sys=${2:-$_AI_CMD_SYS}
  case $(_ai_provider) in
    openai)     _ai_gen_openai    "$req" "$sys" ;;
    anthropic)  _ai_gen_anthropic "$req" "$sys" ;;
    claude-cli) _ai_gen_cli       "$req" "$sys" ;;
    *)
      if [[ $AI_PROVIDER != auto ]]; then
        _ai_err "unknown AI_PROVIDER: $AI_PROVIDER (auto|openai|anthropic|claude-cli)"
      else
        _ai_err "no backend — set OPENAI_API_KEY or ANTHROPIC_API_KEY (needs curl+jq), or install the 'claude' CLI"
      fi
      return 1 ;;
  esac
}

# Run generation in the background behind a spinner with a running clock.
_ai_gen_spin() {
  local req=$1 sys=$2 caption=${3:-$_AI_THINKING}
  # nothing to animate on: run it inline. (The job below is disowned with &!, so
  # it cannot be wait'ed for — only polled — and polling without a tty is pointless.)
  if [[ ! -t 2 ]]; then
    _ai_gen "$req" "$sys"
    return
  fi

  # stderr goes to a file so an error cannot be overwritten by the next spinner frame
  local tmp err; tmp=$(mktemp); err=$(mktemp)
  ( _ai_gen "$req" "$sys" >| "$tmp" 2>| "$err" ) &!
  local pid=$! i=1 n=0
  while kill -0 $pid 2>/dev/null; do
    printf '\r\e[K  %s%s%s %s%s %.1fs%s' \
      "$_AI_CYA" "${_AI_SPIN[i]}" "$_AI_OFF" \
      "$_AI_DIM" "$caption" "$(( n * _AI_SPIN_MS ))" "$_AI_OFF" >&2
    i=$(( i % ${#_AI_SPIN} + 1 )); n=$(( n + 1 ))
    sleep $_AI_SPIN_MS
  done
  printf '\r\e[K' >&2
  [[ -s $err ]] && cat "$err" >&2
  cat "$tmp"; rm -f "$tmp" "$err"
}

# ------------------------------------------------------------ ZLE widget -----

# Transform the current command line in place (animated).
_ai_line_widget() {
  emulate -L zsh
  local input=$BUFFER
  if [[ -z ${input//[[:space:]]/} ]]; then
    zle -M "  type a request (or a command to fix) first"
    return 0
  fi
  local tmp err; tmp=$(mktemp); err=$(mktemp)
  ( _ai_gen "$input" >| "$tmp" 2>| "$err" ) &!
  local pid=$! i=1 n=0
  while kill -0 $pid 2>/dev/null; do
    zle -M "  ${_AI_SPIN[i]} ${_AI_THINKING} $(printf '%.1f' $(( n * _AI_SPIN_MS )))s"
    zle -R
    i=$(( i % ${#_AI_SPIN} + 1 )); n=$(( n + 1 ))
    sleep $_AI_SPIN_MS
  done
  local out msg
  out="$(<$tmp)"
  # zle -M cannot render the colour escapes _ai_err writes, so flatten the message
  msg="$(sed $'s/\033\\[[0-9;]*m//g' "$err" | tr '\n' ' ')"
  rm -f "$tmp" "$err"
  if [[ -n ${out//[[:space:]]/} ]]; then
    BUFFER="$out"; CURSOR=${#BUFFER}
    zle -M ""
  else
    zle -M "  ${msg:-$_AI_MSG_NONE}"
  fi
  zle reset-prompt
}
zle -N _ai_line_widget
bindkey '^g' _ai_line_widget   # Ctrl-G. Change to taste, e.g. bindkey '^[i' ...

# ------------------------------------------------------------- ai / fix ------

# Put a command on the next prompt, with a hint line above it.
_ai_offer() {
  printf '  %s⏎ to run · edit it · ⌃C to discard%s\n' "$_AI_DIM" "$_AI_OFF" >&2
  print -z -- "$1"
}

_ai_usage() {
  cat >&2 <<EOF

  ${_AI_BOLD}ai${_AI_OFF} — turn a request into a shell command

  ${_AI_BOLD}Usage${_AI_OFF}
    ai <what you want to do>   suggest a command on the next prompt
    ai --status                show the backend, model and keys in use
    <type a line> then ⌃G     rewrite the current command line in place

  ${_AI_BOLD}Friends${_AI_OFF}
    fix [cmd]      correct or improve the last (or given) command
    wtf            explain why the last command failed
    secrets edit   where the API keys live

EOF
}

# Also serves as the documentation for how a backend gets picked.
_ai_status() {
  local p model endpoint keys=()
  p=$(_ai_provider)
  case $p in
    openai)     model=$AI_OPENAI_MODEL;    endpoint=${OPENAI_BASE_URL:-https://api.openai.com/v1} ;;
    anthropic)  model=$AI_ANTHROPIC_MODEL; endpoint=${ANTHROPIC_BASE_URL:-https://api.anthropic.com} ;;
    claude-cli) model=$AI_CLI_MODEL;       endpoint='claude CLI (no key needed)' ;;
    *)          model='—';                 endpoint='—' ;;
  esac

  [[ -n $OPENAI_API_KEY ]]    && keys+=("OPENAI_API_KEY ✔")    || keys+=("OPENAI_API_KEY ✖")
  [[ -n $ANTHROPIC_API_KEY ]] && keys+=("ANTHROPIC_API_KEY ✔") || keys+=("ANTHROPIC_API_KEY ✖")
  command -v claude >/dev/null 2>&1 && keys+=("claude CLI ✔") || keys+=("claude CLI ✖")
  _ai_has_http || keys+=("curl/jq missing")

  printf '\n'
  _ai_field "using" "$_AI_BOLD" "${p:-nothing usable}  ${_AI_DIM}(AI_PROVIDER=$AI_PROVIDER)${_AI_OFF}"
  _ai_field "model" "$_AI_CYA"  "$model"
  _ai_field "url"   "$_AI_DIM"  "$endpoint"
  _ai_field "keys"  "$_AI_DIM"  "${(j: · :)keys}"
  _ai_field "file"  "$_AI_DIM"  "${SECRETS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env}"
  printf '\n'
}

# ---- ai: print a suggestion onto the next prompt line ----
ai() {
  case $1 in
    -h|--help)   _ai_usage;  return 0 ;;
    -s|--status) _ai_status; return 0 ;;
  esac
  if [[ -z "$*" ]]; then
    _ai_err "usage: ai <what you want to do>   (ai --help)"
    return 1
  fi
  local out; out="$(_ai_gen_spin "$*" "$_AI_CMD_SYS")"
  [[ -z ${out//[[:space:]]/} ]] && { _ai_err "$_AI_MSG_NONE"; return 1; }
  _ai_offer "$out"
}

# ---- fix: correct/improve the last (or given) command ----
fix() {
  local target
  # `builtin fc` so the user's `alias fc=fzf...` can't hijack history lookup.
  if (( $# )); then target="$*"; else target="$(builtin fc -ln -1)"; fi
  [[ -z ${target//[[:space:]]/} ]] && { _ai_err "nothing to fix"; return 1; }

  local ctx=""
  [[ ! -t 0 ]] && ctx="$(cat)"

  local req="Correct or improve this shell command. Output only the fixed command.
COMMAND: $target"
  [[ -n $ctx ]] && req+="
ERROR OR OUTPUT:
$ctx"

  local out; out="$(_ai_gen_spin "$req" "$_AI_CMD_SYS")"
  [[ -z ${out//[[:space:]]/} ]] && { _ai_err "$_AI_MSG_NONE"; return 1; }
  _ai_offer "$out"
}

# ----------------------------------------------------------------- wtf -------

# Remember the last real command and how it exited. Registered at the FRONT of
# precmd_functions so it sees the true $? before starship's hook runs, and it
# returns that status untouched so starship still renders the error indicator.
_ai_wtf_preexec() {
  case ${1%% *} in
    wtf|fix|ai) return ;;   # asking about a failure must not overwrite it
  esac
  _AI_PENDING_CMD=$1
}

_ai_wtf_precmd() {
  local st=$?
  if [[ -n $_AI_PENDING_CMD ]]; then
    _AI_LAST_CMD=$_AI_PENDING_CMD
    _AI_LAST_STATUS=$st
    _AI_PENDING_CMD=''
  fi
  return $st
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _ai_wtf_preexec
precmd_functions=(_ai_wtf_precmd ${precmd_functions:#_ai_wtf_precmd})

# True if re-running the command could change something. Deliberately trigger
# happy: a missed diagnosis is cheap, a repeated side effect is not.
_ai_wtf_mutates() {
  local c=$1
  [[ $c == *'>'* || $c == *'sudo '* ]] && return 0
  [[ $c =~ '(^|[|&;][[:space:]]*)(rm|rmdir|mv|cp|dd|mkfs|shred|truncate|ln|chmod|chown|kill|killall|pkill|shutdown|reboot|tee|scp|rsync|systemctl|launchctl|make|mvn|gradle)([[:space:]]|$)' ]] && return 0
  [[ $c =~ 'git[[:space:]]+(push|reset|rebase|commit|merge|clean|checkout|restore|cherry-pick|revert|tag|stash|am|apply|pull)' ]] && return 0
  [[ $c =~ '(npm|yarn|pnpm|bun)[[:space:]]+(i|install|ci|add|remove|rm|uninstall|publish|link|run)' ]] && return 0
  [[ $c =~ '(brew|pip|pip3|gem|cargo|go|asdf)[[:space:]]+(install|uninstall|remove|publish|add|build|get)' ]] && return 0
  [[ $c =~ '(docker|podman)[[:space:]]+(run|rm|rmi|push|build|compose|exec)' ]] && return 0
  [[ $c =~ 'kubectl[[:space:]]+(apply|delete|create|patch|scale|edit|rollout|exec)' ]] && return 0
  [[ $c =~ 'terraform[[:space:]]+(apply|destroy|import|init)' ]] && return 0
  [[ $c =~ '(apt|apt-get|yum|dnf|pacman|defaults[[:space:]]+write|stow)' ]] && return 0
  return 1
}

# The command may change something, so the user decides. Anything but an explicit
# yes means no, and no tty at all means no.
_ai_wtf_confirm() {
  [[ -t 0 && -t 2 ]] || return 1
  printf '  %s?%s %sre-run it to capture the real error? it may change things%s\n' \
    "$_AI_YEL" "$_AI_OFF" "$_AI_DIM" "$_AI_OFF" >&2
  local reply
  printf '    [y/N] ' >&2
  read -k 1 reply
  printf '\n' >&2
  [[ $reply == [yY] ]]
}

_ai_wtf_usage() {
  cat >&2 <<EOF

  ${_AI_BOLD}wtf${_AI_OFF} — explain why the last command failed

  ${_AI_BOLD}Usage${_AI_OFF}
    wtf              diagnose the last command
    wtf -n           never re-run it, reason from the command text alone
    wtf -r           re-run it even though it looks like it changes something
    <cmd> 2>&1 | wtf diagnose output you pipe in, no re-run at all

  To read the real error, wtf re-runs the last command with its output captured.
  Commands that look like they change something (rm, git push, npm install, ...)
  are never re-run — pipe their output in instead, or pass -r if you are sure.

EOF
}

wtf() {
  emulate -L zsh
  local rerun=auto piped=''

  while [[ $1 == -* ]]; do
    case $1 in
      -n|--no-run) rerun=never ;;
      -r|--run)    rerun=always ;;
      -h|--help)   _ai_wtf_usage; return 0 ;;
      *)           _ai_err "unknown option: $1"; _ai_wtf_usage; return 1 ;;
    esac
    shift
  done

  # tail, not head: build logs bury the real error at the bottom
  [[ ! -t 0 ]] && piped="$(cat | tail -c 4000)"

  local cmd=${_AI_LAST_CMD:-$(builtin fc -ln -1)}
  local st=${_AI_LAST_STATUS:-0}
  if [[ -z ${cmd//[[:space:]]/} ]]; then
    _ai_err "no previous command to diagnose"
    return 1
  fi

  printf '\n'
  _ai_field "cmd" "$_AI_BOLD" "$cmd"
  if (( st )); then
    _ai_field "exit" "$_AI_RED" "$st"
  else
    _ai_field "exit" "$_AI_DIM" "$st (it succeeded — diagnosing anyway)"
  fi

  local out="$piped" source_note='' blind=0
  if [[ -n $out ]]; then
    source_note='from piped output'
  elif [[ $rerun == never ]]; then
    source_note='not captured (-n)'; blind=1
  elif [[ $rerun != always ]] && _ai_wtf_mutates "$cmd" && ! _ai_wtf_confirm "$cmd"; then
    source_note='not captured — re-run declined'; blind=1
  else
    local tmp; tmp=$(mktemp)
    printf '  %s↻%s %sre-running to capture output…%s\n' \
      "$_AI_YEL" "$_AI_OFF" "$_AI_DIM" "$_AI_OFF" >&2
    ( eval "$cmd" ) >| "$tmp" 2>&1
    out="$(tail -c 4000 "$tmp")"; rm -f "$tmp"
    source_note='captured by re-running'
  fi
  _ai_note "output: ${source_note}"

  local out_block
  if (( blind )); then
    out_block='OUTPUT: (unavailable)'
  else
    out_block="OUTPUT (${source_note}):
${out:-(the command printed nothing)}"
  fi

  local req="Diagnose this failed shell command.
COMMAND: $cmd
EXIT STATUS: $st
DIRECTORY: $PWD
$out_block"

  local resp; resp="$(_ai_gen_spin "$req" "$_AI_WTF_SYS" 'diagnosing')"
  if [[ -z ${resp//[[:space:]]/} ]]; then
    _ai_err "$_AI_MSG_NONE"
    return 1
  fi

  local why sug
  why=$(print -r -- "$resp" | awk '/^WHY:/{f=1; sub(/^WHY:[[:space:]]*/,""); print; next} /^CMD:/{f=0} f')
  sug=$(print -r -- "$resp" | sed -n 's/^CMD:[[:space:]]*//p' | head -1)

  # A model that ignored the format still said something useful; show it raw.
  [[ -z ${why//[[:space:]]/} && -z ${sug//[[:space:]]/} ]] && why=$resp

  # never dress up a guess as a diagnosis
  local label=why lcolor=$_AI_CYA
  (( blind )) && { label=guess; lcolor=$_AI_YEL }

  printf '\n'
  [[ -n ${why//[[:space:]]/} ]] && _ai_field "$label" "$lcolor" "$why"

  if (( blind )); then
    _ai_note "it never saw the error — for a real answer: !! 2>&1 | wtf"
  fi

  if [[ -n ${sug//[[:space:]]/} && $sug != NONE ]]; then
    _ai_field "fix" "$_AI_GRN" "$sug"
    printf '\n'
    _ai_offer "$sug"
  else
    _ai_field "fix" "$_AI_DIM" "no single command fixes this one"
    printf '\n'
  fi
}
