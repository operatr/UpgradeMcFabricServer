#!/usr/bin/env bash
# UI helpers: parse_args, run_cmd, confirm, prompt

DRY_RUN=0
NONINTERACTIVE=0

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1; shift ;;
            --yes|--non-interactive|-y)
                NONINTERACTIVE=1; shift ;;
            --help|-h)
                echo "Usage: $0 [--dry-run] [--yes|--non-interactive]"; exit 0 ;;
            *)
                break ;;
        esac
    done
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "[DRY-RUN] %s\n" "$*"
    else
        eval "$*"
    fi
}

confirm() {
    if [ "$NONINTERACTIVE" -eq 1 ]; then
        return 0
    fi
    local prompt_msg="$1" default_yes="${2:-Y}"
    read -rp "$prompt_msg [Y/n]: " yn
    yn=${yn:-$default_yes}
    if [[ $yn =~ ^[Yy] ]]; then
        return 0
    fi
    return 1
}

prompt() {
    local msg="$1" default="$2"
    if [ -n "$default" ]; then
        read -rp "$msg [$default]: " val
        echo "${val:-$default}"
    else
        read -rp "$msg: " val
        echo "$val"
    fi
}
