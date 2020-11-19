#!/bin/bash

setup(){
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

mask_command(){
	local -r command="${1?}"
	echo "echo >&2 \"bash: ${command}: command not found\" && exit 127" \
		> "${command}"
	chmod +x "${command}"
	export PATH="$PWD:$PATH" "${command}"
}
