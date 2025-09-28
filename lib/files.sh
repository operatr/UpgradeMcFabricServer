#!/usr/bin/env bash

HASH_CMD=""
detect_hash_cmd() {
	if command -v sha512sum >/dev/null 2>&1; then
		HASH_CMD="sha512sum"
	elif command -v sha1sum >/dev/null 2>&1; then
		HASH_CMD="sha1sum"
	elif command -v shasum >/dev/null 2>&1; then
		HASH_CMD="shasum"
	else
		HASH_CMD=""
	fi
}

compute_hash() {
	local file="$1" algo="${2:-sha1}"
	if [ ! -f "$file" ]; then
		return 1
	fi
	if [ "$algo" = "sha512" ]; then
		if command -v sha512sum >/dev/null 2>&1; then
			sha512sum "$file" | awk '{print $1}'; return 0
		elif command -v shasum >/dev/null 2>&1; then
			shasum -a 512 "$file" | awk '{print $1}'; return 0
		fi
	fi
	if [ "$algo" = "sha1" ]; then
		if command -v sha1sum >/dev/null 2>&1; then
			sha1sum "$file" | awk '{print $1}'; return 0
		elif command -v shasum >/dev/null 2>&1; then
			shasum -a 1 "$file" | awk '{print $1}'; return 0
		fi
	fi
	return 1
}

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Required command '$1' not found. Please install it and re-run this script." >&2
		exit 1
	fi
}
