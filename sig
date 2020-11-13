#! /usr/bin/env bash
set -e

MIN_BASH_VERSION=4
MIN_GPG_VERSION=2.2
MIN_OPENSSL_VERSION=1.1

die() {
	echo "$@" >&2
	exit 1
}

check_version(){
    [[ $2 == $3 ]] && return 0
    local IFS=.
    local i ver1=($2) ver2=($3)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++));
    	do ver1[i]=0;
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        [[ -z ${ver2[i]} ]] && ver2[i]=0
        ((10#${ver1[i]} > 10#${ver2[i]})) && return 0
        ((10#${ver1[i]} < 10#${ver2[i]})) && die \
			"Error: ${1} ${3}+ not found"
    done
}

check_tools(){
	if [ -z "${BASH_VERSINFO}" ] \
	|| [ -z "${BASH_VERSINFO[0]}" ] \
	|| [ ${BASH_VERSINFO[0]} -lt ${MIN_BASH_VERSION} ]; then
		die "Error: bash ${MIN_BASH_VERSION}+ not found";
	fi
	for cmd in "$@"; do
		command -v "$1" >/dev/null || die "Error: $cmd not found"
		case $cmd in
			gpg)
				version=$(gpg --version | head -n1 | cut -d" " -f3)
				check_version "gpg" "${version}" "${MIN_GPG_VERSION}"
			;;
			openssl)
				version=$(openssl version | cut -d" " -f2 | sed 's/[a-z]//g')
				check_version "openssl" "${version}" "${MIN_OPENSSL_VERSION}"
			;;
		esac
	done
}

get_temp(){
	echo "$(
		mktemp \
			--quiet \
			--directory \
			-t "$(basename "$0").XXXXXX" 2>/dev/null
		|| mktemp \
			--quiet \
			--directory
	)"
}

get_files(){
	if command -v git >/dev/null; then
		git ls-files | grep -v ".${PROGRAM}"
	else
		find . \
			-type f \
			-not -path "./.git/*" \
			-not -path "./.${PROGRAM}/*"
	fi
}

cmd_manifest() {
	mkdir -p ".${PROGRAM}"
	printf "$(get_files | xargs openssl sha256 -r)" \
	| sed -e 's/ \*/ /g' -e 's/ \.\// /g' \
	| LC_ALL=C sort -k2 \
	> ".${PROGRAM}/manifest.txt"
}

verify_file() {
	[ $# -eq 2 ] || die \
		"Usage: verify_file <threshold> <file>"
	local threshold="${1}"
	local filename="${2}"
	local sig_count=0
	local seen_fingerprints=""
	local fingerprint
	local signer
	for sig_filename in "${filename%.*}".*.asc; do
		gpg --verify "${sig_filename}" "${filename}" >/dev/null 2>&1 || {
			echo "Invalid signature: ${sig_filename}";
			exit 1;
		}
		fingerprint=$( \
			gpg --list-packets "${sig_filename}" \
			| grep keyid \
			| sed 's/.*keyid //g'
		)
		signer=$( \
			gpg \
				--list-keys \
				--with-colons "${fingerprint}" 2>&1 \
			| awk -F: '$1 == "uid" {print $10}' \
			| head -n1 \
		)
		[[ "${seen_fingerprints}" == *"${fingerprint}"* ]] && {
			echo "Duplicate signature: ${sig_filename}";
			exit 1;
		}
		echo "Verified signature by \"${signer}\""
		seen_fingerprints="${seen_fingerprints} ${fingerprint}"
		((sig_count=sig_count+1))
	done
	[[ "$sig_count" -ge "$threshold" ]] || {
		echo "Minimum number of signatures not met: ${sig_count}/${threshold}";
		exit 1;
	}
}

cmd_verify() {
	#TODO: support --min to override the default minimum of 3
	local min=3
	#TODO: support --group for a gpg-group
	local group=""
	#TODO: if git: show git signature status to aid in trust building
	#TODO: if git and if invalid: show diff against last valid version
	( [ -d ".${PROGRAM}" ] && ls .${PROGRAM}/*.asc >/dev/null 2>&1 ) \
		|| die "Error: No signatures"
	cmd_manifest
	verify_file "${min}" .${PROGRAM}/manifest.txt
}

cmd_add(){
	cmd_manifest
	gpg --armor --detach-sig .${PROGRAM}/manifest.txt
	local fingerprint=$( \
		gpg --list-packets .${PROGRAM}/manifest.txt.asc \
			| grep "issuer key ID" \
			| sed 's/.*\([A-Z0-9]\{16\}\).*/\1/g' \
	)
	mv .${PROGRAM}/manifest.{"txt.asc","${fingerprint}.asc"}
}

cmd_version() {
	cat <<-_EOF
	============================================
	=  sig: simple multisig trust toolchain    =
	=                                          =
	=                  v0.0.1                  =
	=                                          =
	=     https://gitlab.com/pchq/sig          =
	============================================
	_EOF
}

cmd_usage() {
	cmd_version
	cat <<-_EOF
	Usage:
	    $PROGRAM verify
	        Verify all signing policies for this directory are met
	    $PROGRAM add
	        Add signature to manifest for this directory
	    $PROGRAM manifest
	        Generate hash manifest for this directory
	    $PROGRAM help
	        Show this text.
	    $PROGRAM version
	        Show version information.
	_EOF
}

check_tools head cut find sort sed gpg openssl

PROGRAM="${0##*/}"
COMMAND="$1"

case "$1" in
	verify) shift;              cmd_verify "$@" ;;
	add) shift;                 cmd_add "$@" ;;
	manifest) shift;            cmd_manifest "$@" ;;
	version|--version) shift;   cmd_version "$@" ;;
	help|--help) shift;         cmd_usage "$@" ;;
	*)                          cmd_usage "$@" ;;
esac
exit 0
