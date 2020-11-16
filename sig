#! /usr/bin/env bash
set -e

MIN_BASH_VERSION=4
MIN_GPG_VERSION=2.2
MIN_OPENSSL_VERSION=1.1
MIN_GETOPT_VERSION=2.33

## Private Functions

### Bail with error message
die() {
	echo "$@" >&2
	exit 1
}

### Bail and instruct user on missing package to install for their platform
die_pkg() {
	local package=${1?}
	local version=${2?}
	local install_cmd
	case "$OSTYPE" in
		linux*)
			if command -v "apt" >/dev/null; then
				install_cmd="apt install ${package}"
			elif command -v "yum" >/dev/null; then
				install_cmd="yum install ${package}"
			elif command -v "pacman" >/dev/null; then
				install_cmd="pacman -Ss ${package}"
			elif command -v "nix-env" >/dev/null; then
				install_cmd="nix-env -i ${package}"
			fi
		;;
		bsd*)     install_cmd="pkg install ${package}" ;;
		darwin*)  install_cmd="port install ${package}" ;;
		*) die "Error: Your operating system is not supported" ;;
	esac
	echo "Error: ${package} ${version}+ does not appear to be installed." >&2
	[ ! -z "$install_cmd" ] && printf "Try: \`${install_cmd}\`" >&2
	exit 1
}

### Check if actual binary version is >= minimum version
check_version(){
	local pkg="${1?}"
	local have="${2?}"
	local need="${3?}"
    [[ "$have" == "$need" ]] && return 0
    local IFS=.
    local i ver1=($have) ver2=($need)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++));
    	do ver1[i]=0;
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        [[ -z ${ver2[i]} ]] && ver2[i]=0
        ((10#${ver1[i]} > 10#${ver2[i]})) && return 0
        ((10#${ver1[i]} < 10#${ver2[i]})) && die_pkg "${pkg}" "${need}"
    done
}

### Check if required binaries are installed at appropriate versions
check_tools(){
	if [ -z "${BASH_VERSINFO}" ] \
	|| [ -z "${BASH_VERSINFO[0]}" ] \
	|| [ ${BASH_VERSINFO[0]} -lt ${MIN_BASH_VERSION} ]; then
		die_pkg "bash" "${MIN_BASH_VERSION}"
	fi
	for cmd in "$@"; do
		command -v "$1" >/dev/null || die "Error: $cmd not found"
		case $cmd in
			gpg)
				version=$(gpg --version | head -n1 | cut -d" " -f3)
				check_version "gnupg" "${version}" "${MIN_GPG_VERSION}"
			;;
			openssl)
				version=$(openssl version | cut -d" " -f2 | sed 's/[a-z]//g')
				check_version "openssl" "${version}" "${MIN_OPENSSL_VERSION}"
			;;
			getopt)
				version=$(getopt --version | cut -d" " -f4 | sed 's/[a-z]//g')
				check_version "getopt" "${version}" "${MIN_GETOPT_VERSION}"
			;;
		esac
	done
}

### Handle different implementations of mktemp across platforms
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

### Get files that will be added to the manifest for signing
### Use git if available, else fall back to find
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

### Verify a file has 0-N unique valid detached signatures
### Optionally verify all signatures belong to keys in gpg alias group
verify_file() {
	[ $# -eq 3 ] || die "Usage: verify_file <threshold> <group> <file>"
	local threshold="${1}"
	local group="${2}"
	local filename="${3}"
	local group_config=""
	local sig_count=0
	local seen_fingerprints=""
	local fingerprint
	local signer

	if [ ! -z "$group" ]; then
		group_config="$( \
			gpg --with-colons --list-config group \
				| grep -i "^cfg:group:${group}:" \
		)" || die "Error: group \"${group}\" not found in ~/.gnupg/gpg.conf"
	fi

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

		[[ "${seen_fingerprints}" == *"${fingerprint}"* ]] \
			&& die "Duplicate signature: ${sig_filename}";

		[ ! -z "$group_config" ] \
			&& [[ "${group_config}" != *"${fingerprint}"* ]] \
			&& die "Signature not in group \"${group}\": ${sig_filename}";

		echo "Verified signature by \"${signer}\""

		seen_fingerprints="${seen_fingerprints} ${fingerprint}"
		((sig_count=sig_count+1))
	done
	[[ "$sig_count" -ge "$threshold" ]] || {
		echo "Minimum number of signatures not met: ${sig_count}/${threshold}";
		exit 1;
	}
}

### Verify all commits in git repo have valid signatures
### Optionally verify a minimum number of valid unique signatures
### Optionally verify all signatures belong to keys in gpg alias group
verify_git(){
	[ $# -eq 2 ] || die "Usage: verify_git <threshold> <group>"
	local threshold="${1}"
	local group="${2}"
	#for commit in $(git log --format='%H%GP'); do
	#	echo "$commit"
  	#done
}


## Public Commands

cmd_manifest() {
	mkdir -p ".${PROGRAM}"
	printf "$(get_files | xargs openssl sha256 -r)" \
		| sed -e 's/ \*/ /g' -e 's/ \.\// /g' \
		| LC_ALL=C sort -k2 \
		> ".${PROGRAM}/manifest.txt"
}

cmd_verify() {
	local opts min=1 group=""
	opts="$(getopt -o m:g: -l min:,group: -n "$PROGRAM" -- "$@")"
	eval set -- "$opts"
	while true; do case $1 in
		-m|--min) min="$2"; shift 2 ;;
		-g|--group) group="$2"; shift 2 ;;
		--) shift; break ;;
	esac done

	command -v git >/dev/null 2>&1 \
		&& ( [ -d .git ] || git rev-parse --git-dir > /dev/null 2>&1 ) \
		&& verify_git "${min}" "${group}"

	#TODO: if git and if invalid: show diff against last valid version
	( [ -d ".${PROGRAM}" ] && ls .${PROGRAM}/*.asc >/dev/null 2>&1 ) \
		|| die "Error: No signatures"
	cmd_manifest
	verify_file "${min}" "${group}" .${PROGRAM}/manifest.txt
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
	==========================================
	=  sig: simple multisig trust toolchain  =
	=                                        =
	=                  v0.0.1                =
	=                                        =
	=     https://gitlab.com/pchq/sig        =
	==========================================
	_EOF
}

cmd_usage() {
	cmd_version
	cat <<-_EOF
	Usage:
	    $PROGRAM verify [--group=<group>,-g <group>] [--min=<N>,-m <N>]
	        Verify m-of-n signatures by given group are present for directory
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

# Verify all tools in this list are installed at needed versions
check_tools head cut find sort sed getopt gpg openssl

# Allow entire script to be namespaced based on filename
PROGRAM="${0##*/}"

# Export public sub-commands
case "$1" in
	verify)            shift; cmd_verify   "$@" ;;
	add)               shift; cmd_add      "$@" ;;
	manifest)          shift; cmd_manifest "$@" ;;
	version|--version) shift; cmd_version  "$@" ;;
	help|--help)       shift; cmd_usage    "$@" ;;
	*)                        cmd_usage    "$@" ;;
esac
