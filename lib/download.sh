#!/usr/bin/env bash
# Downloader wrappers

choose_downloader() {
    if command -v curl >/dev/null 2>&1; then
        echo curl
    elif command -v wget >/dev/null 2>&1; then
        echo wget
    else
        echo "" 
    fi
}

download_to_temp() {
    # download_to_temp <url> <dest_tmp>
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$dest" "$url"
    else
        wget -q -O "$dest" "$url"
    fi
}

safe_move_with_backup() {
    # safe_move_with_backup <src> <dst>
    local src="$1" dst="$2"
    if [ -f "$dst" ]; then
        mv -f "$dst" "${dst}.bak"
    fi
    mv -f "$src" "$dst"
}
