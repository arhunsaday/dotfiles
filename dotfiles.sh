#!/usr/bin/env bash

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
ENV_FILE="$HOME/.dotfiles-env"
ENVIRONMENTS=(work perso)

ACTION=""
ENVIRONMENT=""
DRY_RUN=false
VERBOSE=false

PACKAGES=0
LINKS_ADDED=0
LINKS_REMOVED=0
BACKED_UP=0
FAILED=0
CURRENT_KIND=""

# ---------------------------------------------------------------- output ----

setup_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
        YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
    else
        BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
    fi
}

tilde() {
    echo "${1/#$HOME/~}"
}

plural() {
    [[ "$1" -eq 1 ]] && echo "$1 $2" || echo "$1 ${2}s"
}

say() {
    printf '  %s\n' "$1"
}

section() {
    [[ "$1" == "$CURRENT_KIND" ]] && return
    CURRENT_KIND="$1"
    printf '\n  %s%s%s\n' "$BOLD" "$1" "$RESET"
}

# status icon, package name, then a dim detail column
report() {
    local color="$1" icon="$2" name="$3" detail="$4"
    printf '    %s%s%s %-16s %s%s%s\n' \
        "$color" "$icon" "$RESET" "$name" "$DIM" "$detail" "$RESET"
}

banner() {
    local mode=""
    $DRY_RUN && mode=" ${YELLOW}(dry run)${RESET}"

    printf '\n  %sdotfiles%s  %s%s → %s%s%s\n' \
        "$BOLD" "$RESET" "$DIM" "$(tilde "$DOTFILES_DIR")" "$(tilde "$TARGET_DIR")" "$RESET" "$mode"
    printf '            %s%s · %s · %s%s\n' \
        "$DIM" "${PLATFORM#\~}" "$ENVIRONMENT" "$ACTION" "$RESET"
}

summary() {
    printf '\n  %s%s%s\n' "$DIM" "────────────────────────────────────────────" "$RESET"

    # only the direction that matches the action; the other one is stow
    # re-folding directories, which is churn nobody asked about
    local counts="$(plural "$PACKAGES" package)"
    if [[ "$ACTION" == "install" && $LINKS_ADDED -gt 0 ]]; then
        counts="$counts · $(plural "$LINKS_ADDED" link) added"
    elif [[ "$ACTION" == "uninstall" && $LINKS_REMOVED -gt 0 ]]; then
        counts="$counts · $(plural "$LINKS_REMOVED" link) removed"
    fi

    if [[ $FAILED -gt 0 ]]; then
        report "$RED" "✖" "$FAILED failed" "$counts"
    elif $DRY_RUN; then
        # stow -n cannot descend into directories it did not create, so it
        # under-reports whenever a package brings a new directory along
        [[ $LINKS_ADDED -gt 0 ]] && counts="$counts or more"
        report "$YELLOW" "◌" "nothing written" "$counts — rerun without --dry-run"
    else
        report "$GREEN" "✔" "$ACTION done" "$counts"
    fi

    if [[ $BACKED_UP -gt 0 ]]; then
        if $DRY_RUN; then
            report "$YELLOW" "!" "$BACKED_UP to replace" "would move to $(tilde "$BACKUP_DIR")"
        else
            report "$YELLOW" "!" "$BACKED_UP replaced" "saved to $(tilde "$BACKUP_DIR")"
        fi
    fi
    printf '\n'
}

usage() {
    cat <<EOF

  ${BOLD}dotfiles${RESET} — GNU Stow wrapper

  ${BOLD}Usage${RESET}
    $(basename "$0") install [work|perso] [--dry-run] [--verbose]
    $(basename "$0") uninstall [--dry-run] [--verbose]

  ${BOLD}Environments${RESET}
    Packages named ~macos / ~linux / ~windows are stowed only on the matching
    platform, and ~work / ~perso only for the chosen environment. The choice is
    remembered in $(tilde "$ENV_FILE"), so later runs can omit it.

  ${BOLD}Secrets${RESET}
    Every API key and token lives in one file outside this repo,
    $(tilde "${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"), created from
    secrets.env.example on install if it is missing. Edit it with \`secrets edit\`.
    Uninstall never deletes it.

  ${BOLD}Options${RESET}
    --dry-run, -n   show what would change, write nothing
    --verbose, -v   print every link stow makes
    --help,    -h   this message

EOF
}

# ----------------------------------------------------------------- stow -----

detect_platform() {
    case "$(uname -s)" in
        Linux*)     echo "~linux" ;;
        Darwin*)    echo "~macos" ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*) echo "~windows" ;;
        *)          echo "unknown" ;;
    esac
}

# Resolve the environment from the argument, falling back to the saved one
resolve_environment() {
    case "$1" in
        work)             echo "work" ;;
        perso|personal)   echo "perso" ;;
        "")               cat "$ENV_FILE" 2>/dev/null ;;
        *)                echo "" ;;
    esac
}

# Decide whether a package directory applies here, and how to label it
package_kind() {
    case "$1" in
        '~macos'|'~linux'|'~windows')
            [[ "$1" == "$PLATFORM" ]] && echo "platform" ;;
        '~work'|'~perso')
            [[ "$1" == "~$ENVIRONMENT" ]] && echo "environment" ;;
        *)
            echo "common" ;;
    esac
}

# Move aside anything stow would refuse to overwrite. Echoes the file count.
backup_conflicts() {
    local package="$1" conflicts count=0

    conflicts=$(stow -d "$DOTFILES_DIR" -t "$TARGET_DIR" -n "$package" 2>&1 | grep "existing target")
    [[ -z "$conflicts" ]] && return 0

    while IFS= read -r line; do
        [[ "$line" =~ existing\ target\ (.+)\ since\ neither ]] || continue
        local conflict_path="${BASH_REMATCH[1]}"
        local full_path="$TARGET_DIR/$conflict_path"
        [[ -e "$full_path" ]] || continue

        count=$((count + 1))
        $VERBOSE && say "      ${DIM}backup${RESET} $conflict_path"
        $DRY_RUN && continue

        mkdir -p "$BACKUP_DIR/$(dirname "$conflict_path")"
        mv "$full_path" "$BACKUP_DIR/$conflict_path"
    done <<< "$conflicts"

    echo "$count"
}

# Run stow and describe what actually changed, rather than echoing every link
stow_package() {
    local package="$1" kind="$2" mode="$3" backed_up="$4"
    local flags=(-d "$DOTFILES_DIR" -t "$TARGET_DIR" -v "$mode")
    $DRY_RUN && flags+=(-n)

    local output status
    output=$(stow "${flags[@]}" "$package" 2>&1)
    status=$?

    section "$kind"

    if [[ $status -ne 0 ]]; then
        # name the file that is in the way, not stow's header line
        local blockers count reason
        blockers=$(echo "$output" | sed -n 's/.*existing target \(.*\) since neither.*/\1/p')
        count=$(echo "$blockers" | grep -c '[^[:space:]]')
        reason=$(echo "$blockers" | head -1)
        [[ $count -gt 1 ]] && reason="$reason (+$((count - 1)) more)"
        [[ -z "$reason" ]] && reason=$(echo "$output" | sed -n 's/^stow: ERROR: //p' | head -1)

        # a dry run cannot move conflicts aside first, so what stow calls a
        # failure here is just work the real run would do
        if $DRY_RUN && [[ "${backed_up:-0}" != "0" ]]; then
            PACKAGES=$((PACKAGES + 1))
            report "$YELLOW" "!" "$package" "would replace $reason"
            return 0
        fi

        FAILED=$((FAILED + 1))
        report "$RED" "✖" "$package" "$reason"
        $VERBOSE && echo "$output" | sed 's/^/        /'
        return
    fi

    # stow -R re-links everything it already owns; only the difference is news
    local linked unlinked added removed kept
    linked=$(echo "$output" | sed -n 's/^LINK: \(.*\) =>.*/\1/p' | sort -u)
    unlinked=$(echo "$output" | sed -n 's/^UNLINK: //p' | sort -u)
    added=$(comm -23 <(echo "$linked") <(echo "$unlinked") | grep -c '[^[:space:]]')
    removed=$(comm -13 <(echo "$linked") <(echo "$unlinked") | grep -c '[^[:space:]]')
    kept=$(comm -12 <(echo "$linked") <(echo "$unlinked") | grep -c '[^[:space:]]')

    PACKAGES=$((PACKAGES + 1))
    LINKS_ADDED=$((LINKS_ADDED + added))
    LINKS_REMOVED=$((LINKS_REMOVED + removed))

    local detail=""
    [[ $added -gt 0 ]] && detail="$added added"
    [[ $removed -gt 0 ]] && detail="${detail:+$detail, }$removed removed"
    [[ $kept -gt 0 && -n "$detail" ]] && detail="$detail, $kept unchanged"

    if [[ -n "$backed_up" && "$backed_up" != "0" ]]; then
        report "$YELLOW" "✔" "$package" "${detail:-linked} · $backed_up replaced"
    elif [[ -z "$detail" ]]; then
        report "$DIM" "·" "$package" "up to date"
    else
        report "$GREEN" "✔" "$package" "$detail"
    fi

    $VERBOSE && [[ -n "$output" ]] && echo "$output" | sed 's/^/        /'
    return 0
}

# Drop the environment packages that were not selected
unstow_other_environments() {
    local keep="$1" name
    for name in "${ENVIRONMENTS[@]}"; do
        [[ "$name" == "$keep" ]] && continue
        [[ -d "$DOTFILES_DIR/~$name" ]] || continue
        [[ -L "$TARGET_DIR/.gitconfig-local" || -e "$TARGET_DIR/.gitconfig-local" ]] || continue
        $DRY_RUN || stow -d "$DOTFILES_DIR" -Dt "$TARGET_DIR" "~$name" 2>/dev/null
    done
}

# --------------------------------------------------------------- secrets ----

SECRETS_FILE_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/secrets.env"

# The one file holding every API key. It lives outside this repo on purpose, so
# stow cannot create it — do that here, and always say where it stands.
setup_secrets() {
    local file="$SECRETS_FILE_PATH"
    local template="$DOTFILES_DIR/secrets.env.example"
    local vars perm

    section "secrets"

    if [[ -f "$file" ]]; then
        vars=$(grep -cE '^[[:space:]]*export[[:space:]]+[A-Za-z_]' "$file" 2>/dev/null)
        perm=$(stat -f '%OLp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)
        if [[ "$perm" != "600" ]]; then
            $DRY_RUN || chmod 600 "$file"
            report "$YELLOW" "!" "secrets.env" "$(plural "${vars:-0}" var) · mode $perm → 600"
        else
            report "$DIM" "·" "secrets.env" "$(plural "${vars:-0}" var) · $(tilde "$file")"
        fi
        return 0
    fi

    if [[ ! -f "$template" ]]; then
        FAILED=$((FAILED + 1))
        report "$RED" "✖" "secrets.env" "missing, and no secrets.env.example to copy from"
        return 1
    fi

    if $DRY_RUN; then
        report "$YELLOW" "◌" "secrets.env" "would create $(tilde "$file") from the template"
        return 0
    fi

    mkdir -p "$(dirname "$file")"
    (umask 077; cp "$template" "$file") && chmod 600 "$file" || {
        FAILED=$((FAILED + 1))
        report "$RED" "✖" "secrets.env" "could not write $(tilde "$file")"
        return 1
    }
    report "$GREEN" "✔" "secrets.env" "created at $(tilde "$file") — empty, fill it with 'secrets edit'"
}

# ------------------------------------------------------------------ main ----

setup_colors

while [[ $# -gt 0 ]]; do
    case "$1" in
        install|uninstall)  ACTION="$1" ;;
        -n|--dry-run)       DRY_RUN=true ;;
        -v|--verbose)       VERBOSE=true ;;
        -h|--help)          usage; exit 0 ;;
        -*)                 printf '\n  %s✖%s unknown option: %s\n' "$RED" "$RESET" "$1"; usage; exit 1 ;;
        *)                  ENV_ARG="$1" ;;
    esac
    shift
done

if [[ -z "$ACTION" ]]; then
    usage
    exit 1
fi

PLATFORM=$(detect_platform)
ENVIRONMENT=$(resolve_environment "${ENV_ARG:-}")

if [[ "$ACTION" == "install" && -z "$ENVIRONMENT" ]]; then
    if [[ -n "${ENV_ARG:-}" ]]; then
        printf '\n  %s✖%s unknown environment: %s — expected %swork%s or %sperso%s\n' \
            "$RED" "$RESET" "$ENV_ARG" "$CYAN" "$RESET" "$CYAN" "$RESET"
    else
        printf '\n  %s✖%s no environment selected — pass %swork%s or %sperso%s the first time\n' \
            "$RED" "$RESET" "$CYAN" "$RESET" "$CYAN" "$RESET"
    fi
    usage
    exit 1
fi

cd "$DOTFILES_DIR" || exit 1
banner

if [[ "$ACTION" == "install" ]]; then
    unstow_other_environments "$ENVIRONMENT"

    for dir in */; do
        package="${dir%/}"
        kind=$(package_kind "$package")
        [[ -z "$kind" ]] && continue

        conflicts=$(backup_conflicts "$package")
        BACKED_UP=$((BACKED_UP + ${conflicts:-0}))
        stow_package "$package" "$kind" "-R" "$conflicts"
    done

    setup_secrets

    $DRY_RUN || echo "$ENVIRONMENT" > "$ENV_FILE"
else
    for dir in */; do
        package="${dir%/}"
        kind=$(package_kind "$package")
        [[ -z "$kind" ]] && continue

        stow_package "$package" "$kind" "-D" ""
    done

    unstow_other_environments "$ENVIRONMENT"

    # never delete real credentials on the way out, but do not leave them unmentioned
    if [[ -f "$SECRETS_FILE_PATH" ]]; then
        section "secrets"
        report "$DIM" "·" "secrets.env" "kept — $(tilde "$SECRETS_FILE_PATH")"
    fi

    $DRY_RUN || rm -f "$ENV_FILE"
fi

summary
[[ $FAILED -eq 0 ]]
