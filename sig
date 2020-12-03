#! /usr/bin/env bash
set -e

readonly MIN_BASH_VERSION=5
readonly MIN_GPG_VERSION=2.2
readonly MIN_OPENSSL_VERSION=1.1
readonly MIN_GETOPT_VERSION=2.33

## Private Functions

### Exit with error message
die() {
	echo "$@" >&2
	exit 1
}

### Bail and instruct user on missing package to install for their platform
die_pkg() {
	local -r package=${1?}
	local -r version=${2?}
	local install_cmd
	case "$OSTYPE" in
		linux*)
			if command -v "apt" >/dev/null; then
				install_cmd="apt install ${package}"
			elif command -v "yum" >/dev/null; then
				install_cmd="yum install ${package}"
			elif command -v "pacman" >/dev/null; then
				install_cmd="pacman -Ss ${package}"
			elif command -v "emerge" >/dev/null; then
				install_cmd="emerge ${package}"
			elif command -v "nix-env" >/dev/null; then
				install_cmd="nix-env -i ${package}"
			fi
		;;
		bsd*)     install_cmd="pkg install ${package}" ;;
		darwin*)  install_cmd="port install ${package}" ;;
		*) die "Error: Your operating system is not supported" ;;
	esac
	echo "Error: ${package} ${version}+ does not appear to be installed." >&2
	[ ! -z "$install_cmd" ] && echo "Try: \`${install_cmd}\`"  >&2
	exit 1
}

### Ask user to make a binary decision
### If not an interactive terminal: auto-accept default
ask() {
	local prompt default
	while true; do
		prompt=""
		default=""
		if [ "${2}" = "Y" ]; then
			prompt="Y/n"
			default=Y
		elif [ "${2}" = "N" ]; then
			prompt="y/N"
			default=N
		else
			prompt="y/n"
			default=
		fi
		printf "\\n%s [%s] " "$1" "$prompt"
		read -r reply
		[ -z "$reply" ] && reply=$default
		case "$reply" in
			Y*|y*) return 0 ;;
			N*|n*) return 1 ;;
		esac
	done
}

### Check if actual binary version is >= minimum version
check_version(){
	local pkg="${1?}"
	local have="${2?}"
	local need="${3?}"
	local i ver1 ver2 IFS='.'
	[[ "$have" == "$need" ]] && return 0
	read -r -a ver1 <<< "$have"
	read -r -a ver2 <<< "$need"
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
	if [ -z "${BASH_VERSINFO[0]}" ] \
	|| [ "${BASH_VERSINFO[0]}" -lt "${MIN_BASH_VERSION}" ]; then
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

### Get files that will be added to the manifest for signing
### Use git if available, else fall back to find
get_files(){
	if [ -d '.git' ] && command -v git >/dev/null; then
		git ls-files \
			--cached \
			--others \
			--exclude-standard \
		| grep -v ".${PROGRAM}"
	else
		find . \
			-type f \
			-not -path "./.git/*" \
			-not -path "./.${PROGRAM}/*"
	fi
}

### Get primary UID for a given fingerprint
get_uid(){
	local -r fp="${1?}"
	gpg --list-keys --with-colons "${fp}" 2>&1 \
		| awk -F: '$1 == "uid" {print $10}' \
		| head -n1
}

### Get primary fingerprint for given search
get_primary_fp(){
	local -r search="${1?}"
	gpg --list-keys --with-colons "${search}" 2>&1 \
		| awk -F: '$1 == "fpr" {print $10}' \
		| head -n1
}

### Get fingerprint for a given pgp file
get_file_fp(){
	local -r filename="${1?}"
	gpg --list-packets "${filename}" \
		| grep keyid \
		| sed 's/.*keyid //g'
}

### Get raw gpgconf group config
group_get_config(){
	local -r config=$(gpgconf --list-options gpg | grep ^group)
	printf '%s' "${config##*:}"
}

### Add fingerprint to a given group
group_add_fp(){
	local -r fp=${1?}
	local -r group_name=${2?}
	local -r config=$(group_get_config)
	local group_names=()
	local member_lists=()
	local name member_list config i data

	while IFS=' =' read -rd, name member_list; do
		group_names+=("${name:1}")
		member_lists+=("$member_list")
	done <<< "$config,"

	printf '%s\n' "${group_names[@]}" \
		| grep -w "${group_name}" \
		|| group_names+=("${group_name}")

	for i in "${!group_names[@]}"; do
		[ "${group_names[$i]}" == "${group_name}" ] \
			&& member_lists[$i]="${member_lists[$i]} ${fp}"
		data+=$(printf '"%s = %s,' "${group_names[$i]}" "${member_lists[$i]}")
	done

	echo "Adding key \"${fp}\" to group \"${group_name}\""
	gpg --list-keys >/dev/null 2>&1
	printf 'group:0:%s' "${data%?}" \
		| gpgconf --change-options gpg >/dev/null 2>&1
}

### Get fingerprints for a given group
group_get_fps(){
	local -r group_name=${1?}
	gpg --with-colons --list-config group \
		| grep -i "^cfg:group:${group_name}:" \
		| cut -d ':' -f4
}

### Check if fingerprint belongs to a given group
### Give user option to add it if they wish
group_check_fp(){
	local -r fp=${1?}
	local -r group_name=${2?}
	local -r group_fps=$(group_get_fps "${group_name}")
	local -r uid=$(get_uid "${fp}")

	if [ -z "$group_fps" ] \
		|| [[ "${group_fps}" != *"${fp}"* ]]; then

		cat <<-_EOF

			The following key is not a member of group "${group_name}":

			Fingerprint: ${fp}
			Primary UID: ${uid}
		_EOF
		if ask "Add key to group \"${group_name}\" ?" "N"; then
			group_add_fp "${fp}" "${group_name}"
		else
			return 1
		fi
	fi
}


### Verify a file has 0-N unique valid detached signatures
### Optionally verify all signatures belong to keys in gpg alias group
verify_detached() {
	[ $# -eq 3 ] || die "Usage: verify_detached <threshold> <group> <file>"
	local -r threshold="${1}"
	local -r group="${2}"
	local -r filename="${3}"
	local fp uid sig_count=0 seen_fps=""

	for sig_filename in "${filename%.*}".*.asc; do
		gpg --verify "${sig_filename}" "${filename}" >/dev/null 2>&1 || {
			echo "Invalid detached signature: ${sig_filename}";
			return 1;
		}
		file_fp=$( get_file_fp "${sig_filename}" )
		fp=$( get_primary_fp "${file_fp}" )
		uid=$( get_uid "${fp}" )

		[[ "${seen_fps}" == *"${fp}"* ]] && {
			echo "Duplicate signature: ${sig_filename}";
			return 1;
		}

		echo "Verified detached signature by \"${uid}\""

		if [ ! -z "${group}" ]; then
			group_check_fp "${fp}" "${group}" || {
				echo "Detached signing key not in group \"${group}\": ${fp}";
				return 1;
			}
		fi

		seen_fps="${seen_fps} ${fp}"
		((sig_count=sig_count+1))
	done
	[[ "${sig_count}" -ge "${threshold}" ]] || {
		echo "Minimum detached signatures not found: ${sig_count}/${threshold}";
		return 1;
	}
}

### Verify head commit is signed
### Optionally verify unique signed git tags to meet a threshold
### Optionally verify all signatures belong to keys in gpg alias group
verify_git(){
	[ $# -eq 2 ] || die "Usage: verify_git <threshold> <group>"
	local -r threshold="${1}"
	local -r group="${2}"
	local seen_fps="" sig_count=0 depth=0 ref commit fp uid

	git verify-commit HEAD >/dev/null 2>&1 \
		|| die "HEAD commit not signed"

	fp=$(git log --format="%GP" HEAD -n1 )
	seen_fps="${fp}"
	sig_count=1
	uid=$( get_uid "${fp}" )
	echo "Verified signed git commit by \"${uid}\""

	for tag in $(git tag --points-at HEAD); do
		git tag --verify "$tag" >/dev/null 2>&1 && {
			fp=$( \
				git verify-tag --raw extra-sig 2>&1 \
					| grep VALIDSIG \
					| sed 's/.*VALIDSIG \([A-Z0-9]\+\).*/\1/g' \
			)
			uid=$( get_uid "${fp}" )
			seen_fps="${seen_fps} ${fp}"
			if [[ "${seen_fps}" != *"${fp}"* ]]; then
				seen_fps="${seen_fps} ${fp}"
				echo "Verified signed git tag by \"${uid}\""
				((sig_count=sig_count+1))
			fi
		}
	done

	[[ "${sig_count}" -ge "${threshold}" ]] || {
		echo "Minimum git signatures not found: ${sig_count}/${threshold}";
		return 1;
	}

	if [ ! -z "$group" ]; then
		for fp in "${seen_fps}"; do
			group_check_fp "${fp}" "${group}" || {
				echo "Git signing key not in group \"${group}\": ${fp}";
				return 1;
			}
		done
	fi
}

## Get temporary dir reliably across different mktemp implementations
get_temp(){
	echo "$(
		mktemp \
			--quiet \
			--directory \
			-t "$(basename "$0").XXXXXX" 2>/dev/null \
		|| mktemp \
			--quiet \
			--directory
	)"
}


## Verify specified branch and show diff between that and current HEAD
verify_git_diff(){
	[ $# -eq 4 ] \
		|| die "Usage: verify_git_diff <ref> <threshold> <group> <method>"
	command -v git >/dev/null 2>&1 \
		|| die "Error: verify diff requires 'git' which is not installed"
	local -r diff_ref=${1}
	local -r threshold=${2}
	local -r group=${3}
	local -r method=${4}
	local -r temp_repo=$(get_temp)
	local -r git_root=$(git rev-parse --show-toplevel)
	local -r curr_ref=$(git rev-parse HEAD)
	set -x
	cp -a "${git_root}/." "${temp_repo}/"
	cd "${temp_repo}"
	git reset --hard "${diff_ref}" >/dev/null 2>&1
	if verify "${threshold}" "${group}" "${method}"; then
		git --no-pager diff "${diff_ref}" "${curr_ref}"
	else
		echo "Verification of specifed diff ref failed: ${ref}"
	fi
	set +x
}

## Verify current folder/repo with specified signing rules
verify(){
	[ $# -eq 3 ] || die "Usage: verify <threshold> <group> <method>"
	local -r threshold=${1}
	local -r group=${2}
	local -r method=${3}
	if [ -z "$method" ] || [ "$method" == "git" ]; then
		if [ "$method" == "git" ]; then
			command -v git >/dev/null 2>&1 \
			|| die "Error: method 'git' specified and git is not installed"
		fi
		if command -v git >/dev/null 2>&1 \
			&& ( [ -d .git ] || git rev-parse --git-dir > /dev/null 2>&1 );
		then
			verify_git "${threshold}" "${group}" || return 1
		fi
	fi

	if [ -z "$method" ] || [ "$method" == "detached" ]; then
		( [ -d ".${PROGRAM}" ] && ls ."${PROGRAM}"/*.asc >/dev/null 2>&1 ) || {
			echo "Error: No signatures";
			return 1;
		}
		cmd_manifest || return 1
		verify_detached "${threshold}" "${group}" ."${PROGRAM}"/manifest.txt \
			|| return 1
	fi
}

## Add detached signature for contents of this folder
sign_detached(){
	cmd_manifest
	gpg --armor --detach-sig ."${PROGRAM}"/manifest.txt >/dev/null 2>&1
	local -r fp=$( \
		gpg --list-packets ."${PROGRAM}"/manifest.txt.asc \
			| grep "issuer key ID" \
			| sed 's/.*\([A-Z0-9]\{16\}\).*/\1/g' \
	)
	mv ."${PROGRAM}"/manifest.{"txt.asc","${fp}.asc"}
}

## Add signed tag pointing at this commit.
## Optionally push to origin.
sign_tag(){
	[ -d '.git' ] \
		|| die "Not a git repository"
	command -v git >/dev/null \
		|| die "Git not installed"
	git config --get user.signingKey >/dev/null \
		|| die "Git user.signingKey not set"
	local -r push="${1}"
	local -r short_hash=$(git rev-parse --short HEAD)
	local -r signing_fp=$( \
		git config --get user.signingKey \
			| sed 's/.*\([A-Z0-9]\{16\}\).*/\1/g' \
	)
	local -r name="sig-${short_hash}-${signing_fp}"
	git tag -fsm "$name" "$name"
	[[ $push -eq 1 ]] && git push --tags
}



## Public Commands

cmd_manifest() {
	mkdir -p ".${PROGRAM}"
	printf "%s" "$(get_files | xargs openssl sha256 -r)" \
		| sed -e 's/ \*/ /g' -e 's/ \.\// /g' \
		| LC_ALL=C sort -k2 \
		> ".${PROGRAM}/manifest.txt"
}

cmd_verify() {
	local opts threshold=1 group="" method="" diff=""
	local -r args="$@"
	opts="$(getopt -o t:g:m:d: -l threshold:,group:,method:,diff: -n "$PROGRAM" -- "$@")"
	eval set -- "$opts"
	while true; do case $1 in
		-t|--threshold) threshold="$2"; shift 2 ;;
		-g|--group) group="$2"; shift 2 ;;
		-m|--method) method="$2"; shift 2 ;;
		-d|--diff) diff="$2"; shift 2 ;;
		--) shift; break ;;
	esac done

	if verify "$threshold" "$group" "$method"; then
		return 0
	elif [ ! -z "$diff" ]; then
		echo "Verification failed."
		echo "Attempting verified diff against git ref ${diff} ..."
		verify_git_diff "$diff" "$threshold" "$group" "$method"
	fi
	return 1
}

cmd_fetch() {
	local opts group="" group_fps=""
	opts="$(getopt -o g: -l group: -n "$PROGRAM" -- "$@")"
	eval set -- "$opts"
	while true; do case $1 in
		-g|--group) group="${2:-1}"; shift 2 ;;
		--) shift; break ;;
	esac done
	[ $# -eq 1 ] || \
		die "Usage: $PROGRAM fetch <fingerprint> [-g,--group=<group>]"
	local -r fingerprint=${1}

	if [ ! -z "$group" ]; then
		group_fps=$(group_get_fps "${group_name}")
		if [[ "${group_fps}" == *"${fingerprint}"* ]]; then
			echo "Key \"${fingerprint}\" is already in group \"${group}\""
		else
			group_add_fp "${fingerprint}" "${group}"
		fi
	fi

	gpg --list-keys "${fingerprint}" > /dev/null 2>&1 \
		&& echo "Key \"${fingerprint}\" is already in local keychain" \
		&& return 0

	echo "Requested key is not in keyring. Trying keyservers..."
	for server in \
        ha.pool.sks-keyservers.net \
        hkp://keyserver.ubuntu.com:80 \
        hkp://p80.pool.sks-keyservers.net:80 \
        pgp.mit.edu \
    ; do
        echo "Fetching key \"${fingerprint}\" from \"${server}\"";
       	gpg \
       		--recv-key \
       		--keyserver "$server" \
       		--keyserver-options timeout=10 \
       		--recv-keys "${fingerprint}" \
       	&& break
    done
}

cmd_add(){
	local opts method="default" push=0
	local -r args="$@"
	opts="$(getopt -o m:p:: -l method:push:: -n "$PROGRAM" -- "$@")"
	eval set -- "$opts"
	while true; do case $1 in
		-m|--method) method="$2"; shift 2 ;;
		-p|--push) push="1"; shift 2 ;;
		--) shift; break ;;
	esac done
	case $method in
		default)
			if [ -d '.git' ]; then
				sign_tag "$push"
			else
				sign_detached
			fi
			;;
		detached) sign_detached ;;
		git) sign_tag "$push" ;;
		*) cmd_help ;;
		--) shift; break ;;
	esac
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
	    $PROGRAM add [-m,--method=<git|detached>] [-p,--push]
	        Add signature to manifest for this directory
	    $PROGRAM verify [-g,--group=<group>] [-t,--threshold=<N>] [-m,--method=<git|detached> ] [d,--diff=<branch>]
	        Verify m-of-n signatures by given group are present for directory.
	    $PROGRAM fetch [-g,--group=<group>]
	    	Fetch key by fingerprint. Optionally add to group.
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
readonly PROGRAM="${0##*/}"

# Export public sub-commands
case "$1" in
	verify)            shift; cmd_verify   "$@" ;;
	add)               shift; cmd_add      "$@" ;;
	manifest)          shift; cmd_manifest "$@" ;;
	fetch)             shift; cmd_fetch    "$@" ;;
	version|--version) shift; cmd_version  "$@" ;;
	help|--help)       shift; cmd_usage    "$@" ;;
	*)                        cmd_usage    "$@" ;;
esac
