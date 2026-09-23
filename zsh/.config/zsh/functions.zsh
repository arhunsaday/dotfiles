# ==============================================================================
# Simple functions
# ==============================================================================

# Copy current directory into clipboard
copydir() {
  DIR=$(pwd)
  echo "Copied current directory into clipboard: $DIR"
  pwd | xclip -selection clipboard
}

# Copy file content into clipboard
copyfile() {
  echo "Copied file content into clipboard: $1"
  cat $1 | xclip -selection clipboard
}

# Change directories and view the contents
cl() {
  DIR="$*"
  # if no DIR given, go home
  if [ $# -lt 1 ]; then
    DIR=$HOME
  fi
  builtin cd "${DIR}" &&
    # use your preferred ls command
    ls -F --color=auto
}

# Safer rm
trash() {
  echo "[x] moving files to trash..."
  mv "$@" "$HOME/.local/share/Trash/files/"
}

# Create a new directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Quick notes
function note {
  file=$HOME/Useful/notes.txt

  echo "------------------" >>$file
  echo "date: $(date)" >>$file
  echo "$@" >>$file
  echo "------------------\n" >>$file
}

# ==============================================================================
# Functions using curl
# ==============================================================================

# Upload and share formatted code file
sharecode() {
  file="$1"
  (cat "$1" | curl -F 'f:1=<-' ix.io) | sed "s/$/\/${file##*.}/" | xclip -selection clipboard
}

# Upload and share text file
sharetxt() {
  (cat "$1" | curl -F 'f:1=<-' ix.io) | xclip -selection clipboard
}

cht() {
  if [[ -z "$1" ]]; then
    echo "Usage: cheat <command>"
    return 1
  fi
  curl "https://cheat.sh/$1"
}

# Test internet speed
speedtest() {
  curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -
}

# Expand a shortened url
expand() {
  curl -sIL "$1" | grep -i ^location
}

# Create a qr code
qrcode() {
  curl qrenco.de/"$1"
}

# Get the current weather
weather() {
  curl https://v2.wttr.in/"$1"
}

# Get random numbers
random() {
  curl "https://www.random.org/integers/?num=${1:-1}&min=${2:-1}&max=${3:-100}&col=1&base=10&format=plain&rnd=new"
}

# Extract all links from a page
alllinks() {
  curl -s "https://api.hackertarget.com/pagelinks/?q=$1"
}

###############
###  Other  ###
###############

# Go up [n] directories
up() {
  local cdir="$(pwd)"
  if [[ "${1}" == "" ]]; then
    cdir="$(dirname "${cdir}")"
  elif ! [[ "${1}" =~ ^[0-9]+$ ]]; then
    echo "Error: argument must be a number"
  elif ! [[ "${1}" -gt "0" ]]; then
    echo "Error: argument must be positive"
  else
    for ((i = 0; i < ${1}; i++)); do
      local ncdir="$(dirname "${cdir}")"
      if [[ "${cdir}" == "${ncdir}" ]]; then
        echo "Error: reached root directory"
        break
      else
        cdir="${ncdir}"
      fi
    done
  fi
  cd "${cdir}"
}

# Load completions on demand to avoid slowing down shell startup
copilot() {
  eval "$(github-copilot-cli alias -- "$0")"
}
angular() {
  eval "$(ng completion script)"
}

killport() {
  local port=$1
  local pid=$(lsof -t -i :$port)
  if [ -n "$pid" ]; then
    kill -9 $pid
    echo "Killed process with PID $pid that was using port $port"
  else
    echo "No process found listening on port $port"
  fi
}

batdiff() {
  git diff --name-only --relative --diff-filter=d | xargs batcat --diff
}

function watch_dir() {
    dir_to_watch="$1"
    command_to_run="$2"

    if [ "$#" -ne 2 ]; then
        echo "Usage: watch_dir <directory> <command>"
        return 1
    fi

    if [ ! -d "$dir_to_watch" ]; then
        echo "Error: $dir_to_watch is not a directory."
        return 1
    fi

    fswatch -o "$dir_to_watch" | xargs -n1 -I{} bash -c 'clear; '"$command_to_run"
}
# Manage the single secrets file ($SECRETS_FILE, see exports.zsh)
secrets() {
  local file=${SECRETS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env}
  case ${1:-edit} in
    edit|e)
      [[ -e $file ]] || { mkdir -p "${file:h}" && install -m 600 /dev/null "$file" }
      ${EDITOR:-vi} "$file" && secrets reload
      ;;
    reload|r)
      [[ -r $file ]] || { echo "secrets: no $file" >&2; return 1 }
      source "$file" && echo "secrets: reloaded $(sed -nE 's/^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$file" | wc -l | tr -d ' ') vars from $file"
      ;;
    list|ls|l)
      # names only — printing values into scrollback defeats the point
      [[ -r $file ]] || { echo "secrets: no $file" >&2; return 1 }
      sed -nE 's/^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/  \1/p' "$file"
      ;;
    path|p)  echo "$file" ;;
    *)
      cat >&2 <<USAGE

  secrets — the one file holding every API key and token

    secrets edit     open it in \$EDITOR, then reload this shell
    secrets reload   re-source it after an external edit
    secrets list     variable names only, never values
    secrets path     print the file path

  Lives at $file, mode 0600, outside the dotfiles repo.

USAGE
      return 1 ;;
  esac
}
