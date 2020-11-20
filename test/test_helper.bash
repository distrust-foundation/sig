#!/bin/bash

setup(){
	test -f /usr/bin/git || sudo apt install --reinstall -y git
	test -f /usr/bin/getopt || sudo apt install --reinstall -y util-linux
	test -f /usr/bin/gpg || sudo apt install --reinstall -y gpg
	test -f /usr/bin/openssl || sudo apt install --reinstall -y openssl
	bin_dir=/tmp/bin
	temp_dir=$(mktemp -d -t test-XXXXXXXXXX)
	mkdir -p /tmp/bin
	cp /home/test/sig/sig /tmp/bin/sig
	export PATH=${bin_dir}:${PATH}
	cd "$temp_dir" || return 1
	rm -rf ~/.gnupg
	rm -rf ~/.gitconfig
	killall gpg-agent || :
}

teardown(){
	rm -rf "$temp_dir"
}

set_identity(){
	local -r name="${1?}"
	killall gpg-agent || :
	rm -rf ~/.gnupg || :
	rm -rf ~/.gitconfig || :
	gpg --import ${HOME}/sig/test/keys/*.pub.asc
	gpg --import ${HOME}/sig/test/keys/${name}.sec.asc
	local -r fingerprint=$( \
		gpg --list-keys --with-colons "${name}" 2>&1 \
		| awk -F: '$1 == "fpr" {print $10}' \
		| head -n1 \
    )
	git config --global user.email "${name}@example.com"
	git config --global user.name "${name}"
	git config --global user.signingKey "${fingerprint}"
	git config --global commit.gpgSign "true"
	git config --global merge.gpgSign "true"
	echo "default-key ${fingerprint}" > ~/.gnupg/gpg.conf
}
