# 🐧🔧 Personal dotfiles

My personal dotfiles managed using [GNU Stow](https://www.gnu.org/software/stow/).

(mainly for MacOS but also Linux & Windows to some degree)

## Usage

```sh
./dotfiles.sh install work    # or: perso
./dotfiles.sh install         # reuses the environment saved in ~/.dotfiles-env
./dotfiles.sh uninstall
```

Packages named `~macos` / `~linux` / `~windows` are stowed only on the matching
platform, and `~work` / `~perso` only for the selected environment. Put anything
that differs between the work and personal machine (git identity, ...) in those.

## Secrets

Every API key and token lives in **one file outside this repo**, so nothing
secret can be committed:

```
~/.config/secrets.env      # mode 0600, never tracked
secrets.env.example        # the tracked template
```

`./dotfiles.sh install` creates it from the template when it is missing, tightens
its permissions if they drifted, and reports either way. `./dotfiles.sh uninstall`
never deletes it.

It is sourced from `~/.zshenv` and `~/.bashrc` — so scripts, cron jobs and editor
plugins get the keys too, not just interactive shells. Keep it to plain
`export NAME=value` lines, since both shells read it.

```sh
secrets edit     # open in $EDITOR, then reload this shell
secrets list     # variable names only, never values
secrets reload   # re-source after an external edit
secrets path     # print the file path
```

## AI shell assistant

`zsh/.config/zsh/ai-shell.zsh` turns plain English into shell commands.

| | |
|---|---|
| `Ctrl-G` | rewrite the current command line in place |
| `ai <request>` | put a suggested command on the next prompt |
| `fix [cmd]` | correct the last (or given) command |
| `wtf` | explain why the last command failed, and offer a fix |
| `ai --status` | show the backend, model and keys in use |

It talks to OpenAI, Anthropic, or the `claude` CLI. With `AI_PROVIDER=auto` (the
default) the first usable one wins: `OPENAI_API_KEY`, then `ANTHROPIC_API_KEY`
(both need `curl` + `jq`), then the CLI — which needs no key but has a ~3s
cold-start floor. Put the keys in `~/.config/secrets.env`; the models and the
other knobs are documented at the top of the file.

```sh
export OPENAI_API_KEY=sk-proj-...
export AI_OPENAI_MODEL=gpt-6-luna    # default; gpt-6-sol for harder work
```

`OPENAI_BASE_URL` points anywhere OpenAI-compatible — OpenRouter, Ollama, a
local server, a gateway.
