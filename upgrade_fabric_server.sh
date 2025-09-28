#!/usr/bin/env bash
set -euo pipefail

# Fail fast if jq is not available. This provides an early, user-friendly error
# before the rest of the script runs.
if ! command -v jq >/dev/null 2>&1; then
	echo "Required dependency 'jq' not found. Please install 'jq' (see README.md) and re-run this script." >&2
	exit 2
fi

## Load libraries
LIB_DIR="$(dirname "$0")/lib"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/files.sh"
source "$LIB_DIR/download.sh"
source "$LIB_DIR/modrinth.sh"

MC_HOME="/home/mine"
MODS_DIR="$MC_HOME/mods"
STARTUP_SH="$MC_HOME/startup.sh"


# check_deps: ensure jq and a downloader are present
check_deps() {
    require_cmd jq
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "Required downloader 'curl' or 'wget' not found. Please install one and re-run." >&2
        exit 1
    fi
}

# Determine available hash commands and provide a function to compute file hashes.
## file/hash helpers are in lib/files.sh

## prompt() is provided by lib/ui.sh

detect_mc_version_from_jar() {
	shopt -s nullglob
	local found=()
	for f in "$MC_HOME"/fabric-server-mc*; do
		found+=("$f")
	done
	if [ ${#found[@]} -eq 0 ]; then
		return 1
	fi
	# Try to extract a minecraft version-looking token like 1.21.8
	for f in "${found[@]}"; do
		if [[ $(basename "$f") =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
			echo "${BASH_REMATCH[1]}"
			return 0
		fi
	done
	return 1
}

find_fabric_server_url_from_webpage() {
	local mc_version="$1"
	# Scrape the Fabric server page for meta.fabricmc.net links that contain the MC version
	local url
	# Fetch the page once into a variable to avoid double downloads and quoting issues
	local page
	page=$(curl -fsSL https://fabricmc.net/use/server/ || true)
	url=$(printf '%s' "$page" | grep -oE 'https://meta.fabricmc.net/v2/versions/loader/[^" ]+' | grep -F -- "$mc_version" | head -n1 || true)
	if [ -z "$url" ]; then
		# fallback: return the first meta.fabricmc.net link
		url=$(printf '%s' "$page" | grep -oE 'https://meta.fabricmc.net/v2/versions/loader/[^" ]+' | head -n1 || true)
	fi
	echo "$url"
}
## download_fabric_server remains in main script to orchestrate using lib/download.sh
download_fabric_server() {
	local mc_version="$1"
	cd "$MC_HOME"

	echo "Searching fabricmc.net for a server jar matching Minecraft $mc_version..."
	local url
	url=$(find_fabric_server_url_from_webpage "$mc_version")
	if [ -z "$url" ]; then
		echo "Couldn't find a Fabric server jar link automatically. Please provide a direct download URL." >&2
		read -rp "Direct Fabric server jar URL: " url
	fi

	echo "Downloading Fabric server jar from: $url"
	tmpfile="${MC_HOME}/.fabric-server.jar.part.$$"
	download_to_temp "$url" "$tmpfile"

	if [ "$DRY_RUN" -eq 1 ]; then
		echo "Dry-run: not installing downloaded jar. Temp file: $tmpfile"
		return 0
	fi

	if [ ! -f "$tmpfile" ]; then
		echo "Download failed or temp file not found: $tmpfile" >&2
		return 1
	fi

	filename=$(basename "$url")
	if [[ "$filename" != fabric-server-mc* ]]; then
		filename="fabric-server-mc-${mc_version}.jar"
	fi
	newpath="$MC_HOME/$filename"

	detect_hash_cmd
	replaced=0
	if [ -f "$newpath" ]; then
		if [ -n "$HASH_CMD" ]; then
			existing_hash=$(compute_hash "$newpath" sha512 || true)
			dl_hash=$(compute_hash "$tmpfile" sha512 || true)
			if [ -n "$existing_hash" ] && [ "$existing_hash" = "$dl_hash" ]; then
				echo "Existing Fabric server jar $newpath is identical to downloaded file. Skipping replacement."
				rm -f "$tmpfile"
				return 0
			fi
		else
			existing_size=$(stat -c%s "$newpath" 2>/dev/null || stat -f%z "$newpath" 2>/dev/null || echo 0)
			dl_size=$(stat -c%s "$tmpfile" 2>/dev/null || stat -f%z "$tmpfile" 2>/dev/null || echo 0)
			if [ "$existing_size" = "$dl_size" ] && [ "$existing_size" != "0" ]; then
				echo "Existing Fabric server jar $newpath has same size as downloaded file. Skipping replacement."
				rm -f "$tmpfile"
				return 0
			fi
		fi
	fi

	shopt -s nullglob
	oldjars=(fabric-server-mc*)
	if [ ${#oldjars[@]} -gt 0 ]; then
		for oj in "${oldjars[@]}"; do
			if [ "$oj" != "$(basename "$newpath")" ]; then
				echo "Backing up old jar $oj -> ${oj}.bak"
				run_cmd "mv -f '$oj' '${oj}.bak'"
				replaced=1
			fi
		done
	fi

	run_cmd "mv -f '$tmpfile' '$newpath'"
	echo "Installed Fabric server jar: $newpath"
	if [ $replaced -eq 1 ]; then
		echo "Previous jars were backed up with .bak suffixes."
	fi
}

update_misc_mods() {
	local mc_version="$1"
	# List of default modrinth slugs to try. User can edit or extend this list.
	declare -A default_slugs=(
		["Fabric API"]="fabric-api"
		["Floodgate-Fabric"]="floodgate"
		["Geyser-Fabric"]="geyser"
		["ViaBackwards"]="viabackwards"
		["ViaFabric"]="viafabric"
		["Vivecraft"]="vivecraft"
		["VoiceChat"]="voicechat"
	)

	for name in "${!default_slugs[@]}"; do
		slug=${default_slugs[$name]}
		read -rp "Update $name (slug: $slug)? [Y/n]: " yn
		yn=${yn:-Y}
		if [[ $yn =~ ^[Yy] ]]; then
			download_modrinth_mod "$slug" "$name" "$mc_version" || echo "Failed to update $name"
		else
			echo "Skipping $name"
		fi
	done
}

edit_startup_sh_replace_jar() {
	local newjar="$1"
	if [ ! -f "$STARTUP_SH" ]; then
		echo "No startup script found at $STARTUP_SH. Skipping edit." >&2
		return 1
	fi

	# Replace the first .jar filename found on line 2 with the new jar basename, keep the rest of the line intact.
	local newbasename
	newbasename=$(basename "$newjar")

	# If line 2 already contains the desired jar basename, do nothing (idempotent).
	local line2
	line2=$(sed -n '2p' "$STARTUP_SH" || true)
	if [ -n "$line2" ] && echo "$line2" | grep -F -- "$newbasename" >/dev/null 2>&1; then
		echo "$STARTUP_SH already references $newbasename on line 2. Skipping edit."
		return 0
	fi

	echo "Creating backup of $STARTUP_SH -> ${STARTUP_SH}.bak"
	cp -a "$STARTUP_SH" "${STARTUP_SH}.bak"

	awk -v nb="$newbasename" 'NR==2 { if ($0 ~ /\.jar/) { sub(/[^ ]+\.jar/ , nb); } print; next } { print }' "${STARTUP_SH}.bak" > "$STARTUP_SH"

	echo "Updated $STARTUP_SH (line 2 jar replaced with $newbasename). Backup at ${STARTUP_SH}.bak"
}

main() {
	parse_args "$@"
	check_deps
	detect_hash_cmd

	echo "Starting Fabric server upgrade helper. Working directory: $MC_HOME"

	# Determine MC version
	mc_version=$(detect_mc_version_from_jar || true)
	if [ -z "$mc_version" ]; then
		mc_version=$(prompt "Couldn't auto-detect Minecraft version. Enter the target Minecraft version (e.g. 1.21.8)" "1.21.8")
	else
		echo "Detected Minecraft version: $mc_version"
		mc_version=$(prompt "Use detected Minecraft version" "$mc_version")
	fi

	# Step: download fabric server jar
	download_fabric_server "$mc_version"

	# Find the downloaded jar - choose the first fabric-server-mc* jar
	shopt -s nullglob
	jars=("$MC_HOME"/fabric-server-mc*)
	if [ ${#jars[@]} -eq 0 ]; then
		echo "No fabric server jar found in $MC_HOME after download. Please download manually and re-run." >&2
		exit 1
	fi
	newjar="${jars[0]}"

	# Step: update mods
	if [ ! -d "$MODS_DIR" ]; then
		echo "Mods directory $MODS_DIR does not exist. Creating it."
		mkdir -p "$MODS_DIR"
	fi

	echo "Changing to mods directory: $MODS_DIR"
	cd "$MODS_DIR"

	update_misc_mods "$mc_version"

	# Edit startup.sh line 2 to point to the new jar
	edit_startup_sh_replace_jar "$newjar" || true

	# Offer to restart server via systemd
	read -rp "Attempt to restart server via systemd? Enter service name (or leave blank to skip): " svc
	if [ -n "$svc" ]; then
		echo "Restarting service '$svc' via sudo systemctl restart $svc"
		sudo systemctl restart "$svc"
		echo "Requested systemctl restart for $svc. Check 'systemctl status $svc' for details." 
	else
		echo "Skipping systemd restart. You can restart manually with: sudo systemctl restart <service>"
	fi

	echo "Done. Please verify your server boots correctly and check mod compatibility manually if needed."
}

main "$@"
