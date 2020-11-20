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
	sudo rm /usr/bin/openssl
	run sig version
	echo "${output}" | grep "apt install openssl"
}

@test "Outputs advice to install missing gpg" {
	sudo rm /usr/bin/gpg
	run sig version
	echo "${output}" | grep "apt install gnupg"
}

@test "Outputs advice to install missing getopt" {
	sudo rm /usr/bin/getopt
	run sig version
	echo "${output}" | grep "apt install getopt"
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

@test "Can generate manifest for folder with git not installed" {
	sudo rm /usr/bin/git
	echo "test string" > somefile
	sig manifest
	run grep 37d2046a395cbfc .sig/manifest.txt
	[ "$status" -eq 0 ]
}

@test "Can generate manifest for folder with git installed" {
	echo "test string" > somefile
	sig manifest
	run grep 37d2046a395cbfc .sig/manifest.txt
	[ "$status" -eq 0 ]
}

@test "Can verify git repo has signed commits by anyone" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	run sig verify --method git
	[ "$status" -eq 0 ]
}

@test "Can verify git repo has signed commits by three different identities" {

	git init

	set_identity "user1"
	echo "test string 1" > somefile1
	git add .
	git commit -m "user1 commit"

	set_identity "user2"
	echo "test string 2" > somefile2
	git add .
	git commit -m "user2 commit"

	set_identity "user3"
	echo "test string 3" > somefile3
	git add .
	git commit -m "user3 commit"

	run sig verify --method git --threshold 3
	[ "$status" -eq 0 ]
}


