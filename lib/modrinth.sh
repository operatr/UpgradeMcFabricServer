#!/usr/bin/env bash
# Modrinth-specific helpers

query_modrinth_versions() {
    # query_modrinth_versions <slug>
    local slug="$1"
    curl -fsS "https://api.modrinth.com/v2/project/$slug/version"
}

download_modrinth_mod() {
    local slug="$1" display="$2" mc_version="$3"
    local dest_dir="$MODS_DIR"

    echo "\nUpdating $display (slug: $slug) for Minecraft $mc_version"
    mkdir -p "$dest_dir"
    cd "$dest_dir"

    echo "Querying Modrinth for project '$slug'..."
    local versions_json
    versions_json=$(query_modrinth_versions "$slug") || {
        echo "Failed to query Modrinth for project '$slug'. Skipping." >&2
        return 1
    }

    local version_json
    version_json=$(printf '%s' "$versions_json" | jq -c --arg mc "$mc_version" '.[] | select((.game_versions[]? == $mc) and (.loaders[]? == "fabric"))' | head -n1)
    if [ -z "$version_json" ]; then
        echo "No matching version found for $display on Modrinth for Minecraft $mc_version + fabric. Skipping." >&2
        return 1
    fi

    local file_url filename targetfile tmpfile hash_algo hash_value
    file_url=$(printf '%s' "$version_json" | jq -r '.files[0].url')
    filename=$(basename "$file_url")
    targetfile="$dest_dir/$filename"

    if printf '%s' "$version_json" | jq -e '.files[0].hashes.sha512' >/dev/null 2>&1; then
        hash_algo=sha512
        hash_value=$(printf '%s' "$version_json" | jq -r '.files[0].hashes.sha512')
    elif printf '%s' "$version_json" | jq -e '.files[0].hashes.sha256' >/dev/null 2>&1; then
        hash_algo=sha256
        hash_value=$(printf '%s' "$version_json" | jq -r '.files[0].hashes.sha256')
    elif printf '%s' "$version_json" | jq -e '.files[0].hashes.sha1' >/dev/null 2>&1; then
        hash_algo=sha1
        hash_value=$(printf '%s' "$version_json" | jq -r '.files[0].hashes.sha1')
    else
        hash_algo=""
        hash_value=""
    fi

    # If file exists and we have a hash, compare and skip if identical
    if [ -n "$hash_value" ] && [ -f "$targetfile" ]; then
        local localhash
        localhash=$(compute_hash "$targetfile" "$hash_algo" || true)
        if [ -n "$localhash" ] && [ "$localhash" = "$hash_value" ]; then
            echo "$display is already up-to-date (hash matches). Skipping download."
            return 0
        fi
    fi

    echo "Downloading $display from: $file_url"
    tmpfile="$dest_dir/.${filename}.part.$$"
    download_to_temp "$file_url" "$tmpfile"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Dry-run: not installing downloaded file. Temp file: $tmpfile"
        rm -f "$tmpfile" 2>/dev/null || true
        return 0
    fi

    if [ ! -f "$tmpfile" ]; then
        echo "Download failed for $display ($file_url)." >&2
        rm -f "$tmpfile"
        return 1
    fi

    if [ -n "$hash_value" ] && [ -n "$hash_algo" ]; then
        dlhash=$(compute_hash "$tmpfile" "$hash_algo" || true)
        if [ -z "$dlhash" ] || [ "$dlhash" != "$hash_value" ]; then
            echo "Hash mismatch for $display after download. Expected $hash_value but got ${dlhash:-none}." >&2
            rm -f "$tmpfile"
            return 1
        fi
        mv -f "$tmpfile" "$targetfile"
        echo "Downloaded and wrote: $targetfile"
        return 0
    fi

    if [ -f "$targetfile" ]; then
        existing_size=$(stat -c%s "$targetfile" 2>/dev/null || stat -f%z "$targetfile" 2>/dev/null || echo 0)
        dl_size=$(stat -c%s "$tmpfile" 2>/dev/null || stat -f%z "$tmpfile" 2>/dev/null || echo 0)
        if [ "$existing_size" = "$dl_size" ] && [ "$existing_size" != "0" ]; then
            echo "$display already exists and has the same size as the downloaded file. Skipping replace."
            rm -f "$tmpfile"
            return 0
        fi

        if confirm "Replace existing $filename for $display?"; then
            mv -f "$tmpfile" "$targetfile"
            echo "Replaced $targetfile"
            return 0
        else
            echo "Keeping existing $targetfile. Download removed."
            rm -f "$tmpfile"
            return 0
        fi
    else
        mv -f "$tmpfile" "$targetfile"
        echo "Downloaded and wrote: $targetfile"
        return 0
    fi
}
