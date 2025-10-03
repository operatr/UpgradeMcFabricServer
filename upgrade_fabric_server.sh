#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
	echo "Required dependency 'jq' not found. Please install 'jq' (see README.md) and re-run this script." >&2
	exit 2
fi

LIB_DIR="$(dirname "$0")/lib"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/files.sh"
source "$LIB_DIR/modrinth.sh"

MC_HOME="/home/mine"
MODS_DIR="$MC_HOME/mods"
STARTUP_SH="$MC_HOME/startup.sh"

check_deps() {
    require_cmd jq
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "Required downloader 'curl' or 'wget' not found. Please install one and re-run." >&2
        exit 1
    fi
}


detect_mc_version_from_jar() {
	shopt -s nullglob
	local found=()
	for f in "$MC_HOME"/fabric-server-mc*; do
		found+=("$f")
	done
	if [ ${#found[@]} -eq 0 ]; then
		return 1
	fi

	for f in "${found[@]}"; do
		if [[ $(basename "$f") =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
			echo "${BASH_REMATCH[1]}"
			return 0
		fi
	done
	return 1
}


parse_startup_for_installer_version() {
	local target_mc="${1:-}"
	if [ ! -f "$STARTUP_SH" ]; then
		return 1
	fi

	inst=$(grep -oE 'launcher[._-]?[0-9]+\.[0-9]+\.[0-9]+' "$STARTUP_SH" | head -n1 || true)
	if [ -n "$inst" ]; then
		printf '%s\n' "$(printf '%s' "$inst" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
		return 0
	fi

	installer=$(grep -oE 'fabric-installer[-._]?[0-9]+\.[0-9]+\.[0-9]+' "$STARTUP_SH" | head -n1 || true)
	if [ -n "$installer" ]; then
		printf '%s\n' "$(printf '%s' "$installer" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
		return 0
	fi

	if [ -n "$target_mc" ]; then
		ver=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$STARTUP_SH" | sort -u | awk -v m="$target_mc" '$0 != m { print; exit }' || true)
		if [ -n "$ver" ]; then
			printf '%s\n' "$ver"
			return 0
		fi
	fi

	ver=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$STARTUP_SH" | sort -u | head -n1 || true)
	if [ -n "$ver" ]; then
		printf '%s\n' "$ver"
		return 0
	fi

	return 1
}


download_to_temp() {
	local url="$1" dest="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fSL -o "$dest" "$url"
	else
		wget -q -O "$dest" "$url"
	fi
}

download_fabric_server() {
	local mc_version="$1"
	cd "$MC_HOME"

	echo "Preparing to download Fabric server jar for Minecraft $mc_version..."


	page=$(curl -fsSL https://fabricmc.net/use/server/ || true)
	url=$(printf '%s' "$page" | grep -oE "https://meta.fabricmc.net/v2/versions/loader/${mc_version}/[0-9]+(\.[0-9]+){1,2}/[0-9]+(\.[0-9]+){1,2}/server/jar" | head -n1 || true)

	if [ -z "$url" ]; then
		echo "No pre-built server URL found on fabricmc.net page; querying meta.fabricmc.net for MC $mc_version..."
		url=$(curl -fsSL "https://meta.fabricmc.net/v2/versions/loader/${mc_version}" | jq -r '.[] | select(.downloads.server != null) | .downloads.server.url' | head -n1 || true)
	fi

	if [ -z "$url" ]; then
		echo "Could not find direct server URL; attempting to construct one using latest loader + installer info."
		loader=$(curl -fsSL "https://meta.fabricmc.net/v2/versions/loader/${mc_version}" | jq -r '.[0].loader.version // empty' | head -n1 || true)

		installer=""
		if inst=$(parse_startup_for_installer_version "$mc_version" 2>/dev/null || true); then
			installer="$inst"
			echo "Using installer version from $STARTUP_SH: $installer"
		else
			installer=$(curl -fsSL "https://meta.fabricmc.net/v2/versions/loader/${mc_version}" | jq -r '.[0].installer.version // empty' | head -n1 || true)
			if [ -n "$installer" ]; then
				echo "Using installer version from meta API: $installer"
			fi
		fi

		if [ -n "$loader" ] && [ -n "$installer" ]; then
			url="https://meta.fabricmc.net/v2/versions/loader/${mc_version}/${loader}/${installer}/server/jar"
			echo "Constructed server URL: $url"
		else
			echo "Unable to determine loader+installer from meta API or startup.sh."
			read -rp "Enter direct Fabric server jar URL (or leave blank to abort): " url
			if [ -z "$url" ]; then
				echo "No URL provided. Aborting download step." >&2
				return 1
			fi
		fi
	fi

	echo "Downloading Fabric server jar from: $url"
	tmpfile="${MC_HOME}/.fabric-server.jar.part.$$"
	download_to_temp "$url" "$tmpfile"

	if [ "${DRY_RUN:-0}" -eq 1 ]; then
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

	return 0
}

edit_startup_sh_replace_jar() {
	local newjar="$1"
	if [ ! -f "$STARTUP_SH" ]; then
		echo "No startup script found at $STARTUP_SH. Skipping edit." >&2
		return 1
	fi

	local newbasename
	newbasename=$(basename "$newjar")

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

	mc_version=$(detect_mc_version_from_jar || true)
	if [ -z "$mc_version" ]; then
		mc_version=$(prompt "Couldn't auto-detect Minecraft version. Enter the target Minecraft version (e.g. 1.21.8)" "1.21.8")
	else
		echo "Detected Minecraft version: $mc_version"
		mc_version=$(prompt "Use detected Minecraft version" "$mc_version")
	fi

	download_fabric_server "$mc_version"

	shopt -s nullglob
	jars=("$MC_HOME"/fabric-server-mc*)
	if [ ${#jars[@]} -eq 0 ]; then
		echo "No fabric server jar found in $MC_HOME after download. Please download manually and re-run." >&2
		exit 1
	fi
	newjar="${jars[0]}"

	# Step: update mods
	# if [ ! -d "$MODS_DIR" ]; then
	# 	echo "Mods directory $MODS_DIR does not exist. Creating it."
	# 	mkdir -p "$MODS_DIR"
	# fi

	# echo "Changing to mods directory: $MODS_DIR"
	# cd "$MODS_DIR"

	# update_misc_mods "$mc_version"

	edit_startup_sh_replace_jar "$newjar" || true

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
