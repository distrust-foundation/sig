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

@test "Verify fails if git is in use and tree is dirty" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	echo "dirty" > somefile
	run sig verify --method="git"
	[ "$status" -eq 1 ]
}

@test "Exit 1 if git method requested but not a repo" {
	run sig verify --method="git"
	[ "$status" -eq 1 ]
}

@test "Verify succeeds when 1 unique git sig requirement is satisifed" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	run sig verify --method git
	[ "$status" -eq 0 ]
}

@test "Verify succeeds when 3 unique git sig requirement is satisfied" {
	git init
	set_identity "user1"
	echo "test string 1" > somefile1
	git add .
	git commit -m "user1 commit"
	set_identity "user2"
	git log
	sig add
	set_identity "user3"
	sig add
	run sig verify --method git --threshold 3
	[ "$status" -eq 0 ]
}

@test "Verify fails when 2 unique git sig requirement is not satisfied" {
	git init
	set_identity "user1"
	echo "test string 1" > somefile1
	git add .
	git commit -m "user1 commit"
	sig add
	run sig verify --method git --threshold 2
	[ "$status" -eq 1 ]
}

@test "Verify succeeds when 1 group git sig requirement is satisifed" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	sig fetch --group maintainers AE08157232C35F04309FA478C5EBC4A7CF55A2D0
	run sig verify --method git --group maintainers
	[ "$status" -eq 0 ]
}

@test "Verify succeeds when 3 group git sig requirement is satisifed" {
	set_identity "user1"
	echo "test string" > somefile1
	git init
	git add .
	git commit -m "User 1 Commit"
	set_identity "user2"
	sig add
	set_identity "user3"
	sig add
	sig fetch --group maintainers AE08157232C35F04309FA478C5EBC4A7CF55A2D0
	sig fetch --group maintainers BE4D60F6CFD2237A8AF978583C51CADD33BD0EE8
	sig fetch --group maintainers 3E45AC9E190B4EE32BAE9F61A331AFB540761D69
	run sig verify --method git --threshold 3 --group maintainers
	[ "$status" -eq 0 ]
}

@test "Verify fails when 2 group git sig requirement is not satisifed" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	run sig verify --method git --threshold 2 --group maintainers
	[ "$status" -eq 1 ]
}

@test "Verify succeeds when 1 unique detached sig requirement is satisifed" {
	set_identity "user1"
	run sig add
	run sig verify --method detached
	[ "$status" -eq 0 ]
}

@test "Verify succeeds when 2 unique detached sig requirement is satisifed" {
	set_identity "user1"
	run sig add
	set_identity "user2"
	run sig add
	run sig verify --threshold 2 --method detached
	[ "$status" -eq 0 ]
}

@test "Verify fails when 2 unique detached sig requirement is not satisifed" {
	set_identity "user1"
	run sig add
	run sig verify --threshold 2 --method detached
	[ "$status" -eq 1 ]
}

@test "Verify succeeds when 1 group detached sig requirement is satisifed" {
	set_identity "user1"
	sig add
	sig fetch --group maintainers AE08157232C35F04309FA478C5EBC4A7CF55A2D0
	run sig verify --method detached --group maintainers
	[ "$status" -eq 0 ]
}

@test "Verify succeeds when 3 group detached sig requirement is satisifed" {
	set_identity "user1"
	sig add
	set_identity "user2"
	sig add
	set_identity "user3"
	sig add
	sig fetch --group maintainers AE08157232C35F04309FA478C5EBC4A7CF55A2D0
	sig fetch --group maintainers BE4D60F6CFD2237A8AF978583C51CADD33BD0EE8
	sig fetch --group maintainers 3E45AC9E190B4EE32BAE9F61A331AFB540761D69
	run sig verify --method detached --threshold 3 --group maintainers
	[ "$status" -eq 0 ]
}

@test "Verify fails when 2 group detached sig requirement is not satisifed" {
	set_identity "user1"
	sig add
	run sig verify --method detached --threshold 2 --group maintainers
	[ "$status" -eq 1 ]
}

@test "Verify diff shows changes between feature branch and verified master" {
	git init

	set_identity "user1"
	echo "test string" > testfile
	git add .
	git commit -m "User 1 Commit"

	set_identity "user2"
	sig add

	set_identity "user1"
	git checkout -b feature_branch
	echo "updated test string" > somefile1
	git add .
	git commit -m "User 1 Update Commit"

	run sig verify --diff master --threshold 2
	[ "$status" -eq 1 ]
	echo "${output}" | grep "updated test string"
}
