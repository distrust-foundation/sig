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
}

teardown(){
	rm -rf "$temp_dir"
}

set_identity(){
	local -r name="${1?}"
	echo "set key to $name"
	git config --global user.email "${name}@example.com"
	git config --global user.name "${name}"
}
