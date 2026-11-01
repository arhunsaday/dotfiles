# Sourced by Git for Windows' /etc/profile.d/git-prompt.sh instead of its own
# prompt, which runs `git --exec-path` (~150ms, twice) for a PS1 that starship
# replaces anyway. Keeps the git completion it would have loaded.
TITLEPREFIX=$MSYSTEM
PS1='\$ '
f="${MINGW_PREFIX:-/mingw64}/share/git/completion/git-completion.bash"
[ -f "$f" ] && . "$f"
unset f
