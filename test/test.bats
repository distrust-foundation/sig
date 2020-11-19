load test_helper

@test "Outputs help if run without arguments" {
	run sig
	[ "$status" -eq 0 ]
	echo "${output}" | grep "simple multisig trust toolchain"
}

@test "Outputs help if run with help" {
	run sig help
	[ "$status" -eq 0 ]
	echo "${output}" | grep "simple multisig trust toolchain"
}

@test "Outputs version if run with version" {
	run sig version
	[ "$status" -eq 0 ]
	echo "${output}" | grep "v0.0.1"
}

@test "Outputs advice to install missing openssl" {
	mask_command openssl
	run sig version
	echo "${output}" | grep "apt install openssl"
}

@test "Outputs advice to install missing gpg" {
	mask_command gpg
	run sig version
	echo "${output}" | grep "apt install gnupg"
}

@test "Outputs advice to install missing getopt" {
	mask_command getopt
	run sig version
	echo "${output}" | grep "apt install getopt"
}

@test "Can generate manifest for folder with git installed" {
	echo "test string" > somefile
	sig manifest
	run grep 37d2046a395cbfc .sig/manifest.txt
	[ "$status" -eq 0 ]
}

@test "Can generate manifest for folder with git not installed" {
	mask_command git
	echo "test string" > somefile
	sig manifest
	run grep 37d2046a395cbfc .sig/manifest.txt
	[ "$status" -eq 0 ]
}

@test "Can generate manifest for git repo" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	sig manifest
	run grep -q "1" <(wc -l .sig/manifest.txt)
	[ "$status" -eq 0 ]
	run grep 37d2046a395cbfc .sig/manifest.txt
	[ "$status" -eq 0 ]
}
