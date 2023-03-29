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
	[ -n "$install_cmd" ] && echo "Try: \`${install_cmd}\`"  >&2
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

tree_hash() {
	local -r ref="${1:-HEAD}"
	git rev-parse "${ref}^{tree}"
}

sig_generate(){
	local -r vcs_ref="$1"
	local -r review_hash="${2:-null}"
	local -r version="v0"
	local -r sig_type="pgp"
	local -r tree_hash="$(tree_hash)"
	local -r body="sig:$version:$vcs_ref:$tree_hash:$review_hash:$sig_type"
	local -r signature=$(\
		printf "%s" "$body" \
		| gpg \
			--detach-sign \
			--local-user "$key" \
		| openssl base64 -A \
	)
	printf "%s" "$body:$signature"
}

parse_gpg_status() {
	local -r gpg_status="$1"
	local -r error="$2"
	while read -r values; do
		local key array sig_fp sig_date sig_status sig_author sig_body
		IFS=" " read -r -a array <<< "$values"
		key=${array[1]}
		case $key in
			"BADSIG"|"ERRSIG"|"EXPSIG"|"EXPKEYSIG"|"REVKEYSIG")
				sig_fp="${array[2]}"
				sig_status="$key"
			;;
			"GOODSIG")
				sig_author="${values:34}"
				sig_fp="${array[2]}"
			;;
			"VALIDSIG")
				sig_status="$key"
				sig_date="${array[4]}"
			;;
			"SIG_ID")
				sig_date="${array[4]}"
			;;
			"NEWSIG")
				sig_author="${sig_author:-Unknown User <${array[2]}>}"
			;;
			TRUST_*)
				sig_trust="${key//TRUST_/}"
			;;
		esac
	done <<< "$gpg_status"
	sig_fp=$(get_primary_fp "$sig_fp")
	sig_body="pgp:$sig_fp:$sig_status:$sig_trust:$sig_date:$sig_author:$error"
	printf "%s" "$sig_body"
}

verify_git_note(){
	local -r line="${1}"
	local -r ref="${2:-HEAD}"
	local -r commit=$(git rev-parse "$ref")
	IFS=':' read -r -a line_parts <<< "$line"
	local -r identifier=${line_parts[0]}
	local -r version=${line_parts[1]}
	local -r vcs_hash=${line_parts[2]}
	local -r tree_hash=${line_parts[3]}
	local -r review_hash=${line_parts[4]:-null}
	local -r sig_type=${line_parts[5]}
	local -r sig=${line_parts[6]}
	local -r body="sig:$version:$vcs_hash:$tree_hash:$review_hash:$sig_type"
	local error="" commit_tree_hash
	[[ "$identifier" == "sig" \
		&& "$version" == "v0" \
		&& "$sig_type" == "pgp" \
	]] || {
		return 1;
	}
	gpg_sig_raw="$(
		gpg --verify --status-fd=1 \
		<(printf '%s' "$sig" | openssl base64 -d -A) \
		<(printf '%s' "$body") 2>/dev/null \
	)"
	[[ "$vcs_hash" == "$commit" ]] || {
		error="COMMIT_NOMATCH"
	}
	commit_tree_hash=$(tree_hash "$commit")
	[[ "$tree_hash" == "$commit_tree_hash" ]] || {
		error="TREEHASH_NOMATCH;$commit;$tree_hash;$commit_tree_hash";
	}
	parse_gpg_status "$gpg_sig_raw" "$error"
}

verify_git_notes(){
	local -r ref="${1:-HEAD}"
	local -r commit=$(git rev-parse "$ref")
	local code=1
	while IFS='' read -r line; do
		printf "%s\n" "$(verify_git_note "$line" "$ref")"
		code=0
	done < <(git notes --ref signatures show "$commit" 2>&1 | grep "^sig:")
	return $code
}

verify_git_commit(){
	local -r ref="${1:-HEAD}"
	local gpg_sig_raw
	gpg_sig_raw=$(git verify-commit "$ref" --raw 2>&1)
	parse_gpg_status "$gpg_sig_raw"
}

verify_git_tags(){
	local gpg_sig_raw code=1
	for tag in $(git tag --points-at HEAD); do
		git tag --verify "$tag" >/dev/null 2>&1 && {
			gpg_sig_raw=$( git verify-tag --raw "$tag" 2>&1 )
			printf "%s\n" "$(parse_gpg_status "$gpg_sig_raw")"
			code=0
		}
	done
	return $code
}

### Verify head commit is signed
### Optionally verify total unique commit/tag/note signatures meet a threshold
### Optionally verify all signatures belong to keys in gpg alias group
verify(){
	[ $# -eq 3 ] || die "Usage: verify <threshold> <group> <ref>"
	local -r threshold="${1}"
	local -r group="${2}"
	local -r ref=${3:-HEAD}
	local sig_count=0 seen_fps fp commit_sig tag_sigs note_sigs
	git rev-parse --git-dir >/dev/null 2>&1 \
	    || die "Error: This folder is not a git repository"
	if [[ $(git diff --stat) != '' ]]; then
		die "Error: git tree is dirty"
	fi

	commit_sig=$(verify_git_commit "$ref")
	if [ -n "$commit_sig" ]; then
		IFS=':' read -r -a sig <<< "$commit_sig"
		fp="${sig[1]}"
		uid="${sig[5]}"
		echo "Verified signed git commit by \"$uid\""
		seen_fps="${fp}"
	fi

	tag_sigs=$(verify_git_tags "$ref") && \
	while IFS= read -r line; do
		IFS=':' read -r -a sig <<< "$line"
		fp="${sig[1]}"
		uid="${sig[5]}"
		echo "Verified signed git tag by \"${uid}\""
		if [[ "${seen_fps}" != *"${fp}"* ]]; then
			seen_fps+=" ${fp}"
		fi
	done <<< "$tag_sigs"

	note_sigs=$(verify_git_notes "$ref") && \
	while IFS= read -r line; do
		IFS=':' read -r -a sig <<< "$line"
		fp="${sig[1]}"
		uid="${sig[5]}"
		error="${sig[6]}"
		[ "$error" == "" ] || {
			echo "Error: $error";
			return 1;
		}
		echo "Verified signed git note by \"${uid}\""
		if [[ "${seen_fps}" != *"${fp}"* ]]; then
			seen_fps+=" ${fp}"
		fi
	done <<< "$note_sigs"

	for seen_fp in ${seen_fps}; do
		if [ -n "$group" ]; then
			group_check_fp "${seen_fp}" "${group}" || {
				echo "Git signing key not in group \"${group}\": ${seen_fp}";
				return 1;
			}
		fi
		((sig_count=sig_count+1))
	done

	[[ "${sig_count}" -ge "${threshold}" ]] || {
		echo "Minimum unique signatures not found: ${sig_count}/${threshold}";
		return 1;
	}
}

## Get temporary dir reliably across different mktemp implementations
get_temp(){
	mktemp \
		--quiet \
		--directory \
		-t "$(basename "$0").XXXXXX" 2>/dev/null \
	|| mktemp \
		--quiet \
		--directory
}

## Add signed tag pointing at this commit.
## Optionally push to origin.
sign_tag(){
	git rev-parse --git-dir >/dev/null 2>&1 \
		|| die "Not a git repository"
	command -v git >/dev/null \
		|| die "Git not installed"
	git config --get user.signingKey >/dev/null \
		|| die "Git user.signingKey not set"
	local -r push="${1}"
	local -r commit=$(git rev-parse --short HEAD)
	local -r fp=$( \
		git config --get user.signingKey \
			| sed 's/.*\([A-Z0-9]\{16\}\).*/\1/g' \
	)
	local -r name="sig-${commit}-${fp}"
	git tag -fsm "$name" "$name"
	[[ "$push" -eq "0" ]] || $PROGRAM push
}

## Add signed git note to this commit
## Optionally push to origin.
sign_note() {
	git rev-parse --git-dir >/dev/null 2>&1 \
		|| die "Not a git repository"
	command -v git >/dev/null \
		|| die "Git not installed"
	git config --get user.signingKey >/dev/null \
		|| die "Git user.signingKey not set"
	local -r push="${1}"
	local -r key=$( \
		git config --get user.signingKey \
			| sed 's/.*\([A-Z0-9]\{16\}\).*/\1/g' \
	)
	local -r commit=$(git rev-parse HEAD)

	sig_generate "$commit" | git notes --ref signatures append --file=-

	[[ "$push" -eq "0" ]] || $PROGRAM push
}

## Public Commands

cmd_remove() {
	git notes --ref signatures remove
}

cmd_verify() {
	local opts threshold=1 group="" method="" diff=""
	opts="$(getopt -o t:g:m:d:: -l threshold:,group:,ref:,diff:: -n "$PROGRAM" -- "$@")"
	eval set -- "$opts"
	while true; do case $1 in
		-t|--threshold) threshold="$2"; shift 2 ;;
		-g|--group) group="$2"; shift 2 ;;
		-r|--ref) ref="$2"; shift 2 ;;
		-d|--diff) diff="1"; shift 2 ;;
		--) shift; break ;;
	esac done

	local -r head=$(git rev-parse --short HEAD)
	if [ -n "$diff" ] && [ -z "$ref" ]; then
		while read -r commit; do
			echo "Checking commit: $commit"
			if verify "$threshold" "$group" "$commit"; then
				git --no-pager diff "${commit}" "${head}"
				return 0
			fi
		done <<< "$(git log --show-notes=signatures --pretty=format:"%H")"
	else
		if verify "$threshold" "$group" "$ref"; then
			if [ -n "$diff" ] && [ -n "$ref" ]; then
				local -r commit=$(git rev-parse --short "${ref}")
				[ "${commit}" != "${head}" ] && \
					git --no-pager diff "${commit}" "${head}"
			fi
			return 0
		fi
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

	if [ -n "$group" ]; then
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
		keys.openpgp.org \
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
	local opts method="" push="0"
	opts="$(getopt -o m:p:: -l method:,push:: -n "$PROGRAM" -- "$@")"
	eval set -- "$opts"
	while true; do case $1 in
		-m|--method) method="$2"; shift 2 ;;
		-p|--push) push="1"; shift 2 ;;
		--) shift; break ;;
	esac done
	case $method in
		note) sign_note "$push" ;;
		tag) sign_tag "$push" ;;
		*) sign_note "$push" ;;
	esac
}

cmd_push() {
	[ "$#" -eq 0 ] || { usage push; exit 1; }
	git fetch origin refs/notes/signatures:refs/notes/origin/signatures
	git notes --ref signatures merge -s cat_sort_uniq origin/signatures
	git push --tags origin refs/notes/signatures
}

cmd_version() {
	cat <<-_EOF
	==============================================
	=  sig: simple multisig trust toolchain      =
	=                                            =
	=                  v0.2                      =
	=                                            =
	= https://github.com/distrust-foundation/sig =
	==============================================
	_EOF
}

cmd_usage() {
	cmd_version
	cat <<-_EOF
	Usage:
	    $PROGRAM add [-m,--method=<note|tag>] [-p,--push]
	        Add signature for this repository
	    $PROGRAM remove
	        Remove all signatures on current ref
	    $PROGRAM verify [-g,--group=<group>] [-t,--threshold=<N>] [d,--diff=<branch>]
	        Verify m-of-n signatures by given group are present for directory.
	    $PROGRAM fetch [-g,--group=<group>]
	        Fetch key by fingerprint. Optionally add to group.
	    $PROGRAM help
	        Show this text.
	    $PROGRAM version
	        Show version information.
	_EOF
}

# Verify all tools in this list are installed at needed versions
check_tools git head cut find sort sed getopt gpg openssl

# Allow entire script to be namespaced based on filename
readonly PROGRAM="${0##*/}"

# Export public sub-commands
case "$1" in
	verify)            shift; cmd_verify   "$@" ;;
	add)               shift; cmd_add      "$@" ;;
	remove)            shift; cmd_remove   "$@" ;;
	fetch)             shift; cmd_fetch    "$@" ;;
	push)              shift; cmd_push     "$@" ;;
	version|--version) shift; cmd_version  "$@" ;;
	help|--help)       shift; cmd_usage    "$@" ;;
	*)                        cmd_usage    "$@" ;;
esac
