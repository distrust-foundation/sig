load test_helper

@test "Outputs help if run without arguments" {
	run git-sig
	[ "$status" -eq 0 ]
	echo "${output}" | grep "multisig trust for git"
}

@test "Outputs help if run with help" {
	run git-sig help
	[ "$status" -eq 0 ]
	echo "${output}" | grep "multisig trust for git"
}

@test "Outputs version if run with version" {
	run git-sig version
	[ "$status" -eq 0 ]
	echo "${output}" | grep "v0.3"
}

@test "Outputs advice to install missing openssl" {
	sudo rm /usr/bin/openssl
	run git-sig version
	echo "${output}" | grep "apt install openssl"
}

@test "Outputs advice to install missing gpg" {
	sudo rm /usr/bin/gpg
	run git-sig version
	echo "${output}" | grep "apt install gnupg"
}

@test "Outputs advice to install missing getopt" {
	sudo rm /usr/bin/getopt
	run git-sig version
	echo "${output}" | grep "apt install getopt"
}

@test "Verify fails if git is in use and tree is dirty" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	echo "dirty" > somefile
	run git-sig verify
	[ "$status" -eq 1 ]
}

@test "Exit 1 if git method requested but not a repo" {
	run git-sig verify
	[ "$status" -eq 1 ]
}

@test "Verify succeeds when 1 unique git git-sig requirement is satisfied" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	run git-sig verify
	[ "$status" -eq 0 ]
}

@test "Verify succeeds when 3 unique git git-sig requirement is satisfied" {
	git init
	set_identity "user1"
	echo "test string 1" > somefile1
	git add .
	git commit -m "user1 commit"
	set_identity "user2"
	git log
	git-sig add
	set_identity "user3"
	git-sig add
	run git-sig verify --threshold 3
	[ "$status" -eq 0 ]
}

@test "Verify fails when 2 unique git git-sig requirement is not satisfied" {
	git init
	set_identity "user1"
	echo "test string 1" > somefile1
	git add .
	git commit -m "user1 commit"
	git-sig add
	run git-sig verify --threshold 2
	[ "$status" -eq 1 ]
}

@test "Verify succeeds when 1 group git git-sig requirement is satisifed" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	git-sig fetch --group maintainers AE08157232C35F04309FA478C5EBC4A7CF55A2D0
	run git-sig verify --group maintainers
	[ "$status" -eq 0 ]
}

@test "Verify succeeds when 3 group git git-sig requirement is satisifed" {
	set_identity "user1"
	echo "test string" > somefile1
	git init
	git add .
	git commit -m "User 1 Commit"
	set_identity "user2"
	git-sig add
	set_identity "user3"
	git-sig add
	git-sig fetch --group maintainers AE08157232C35F04309FA478C5EBC4A7CF55A2D0
	git-sig fetch --group maintainers BE4D60F6CFD2237A8AF978583C51CADD33BD0EE8
	git-sig fetch --group maintainers 3E45AC9E190B4EE32BAE9F61A331AFB540761D69
	run git-sig verify --threshold 3 --group maintainers
	[ "$status" -eq 0 ]
}

@test "Verify fails when 2 group git git-sig requirement is not satisifed" {
	set_identity "user1"
	echo "test string" > somefile
	git init
	git add .
	git commit -m "initial commit"
	git-sig fetch --group maintainers AE08157232C35F04309FA478C5EBC4A7CF55A2D0
	run git-sig verify --threshold 2 --group maintainers
	[ "$status" -eq 1 ]
}

@test "Verify succeeds on past commit ref" {
	git init

	set_identity "user1"
	echo "test string" > testfile
	git add .
	git commit -m "User 1 Commit"

	set_identity "user2"
	git-sig add

	set_identity "user1"
	echo "updated test string" > somefile1
	git add .
	git commit -m "User 1 Update Commit"

	run git-sig verify --threshold 2 --ref HEAD~1
	[ "$status" -eq 0 ]
}

@test "Verify diff shows changes between feature branch and verified master" {
	git init

	set_identity "user1"
	echo "test string" > testfile
	git add .
	git commit -m "User 1 Commit"

	set_identity "user2"
	git-sig add

	set_identity "user1"
	git checkout -b feature_branch
	echo "updated test string" > somefile1
	git add .
	git commit -m "User 1 Update Commit"

	run git-sig verify --diff --ref master --threshold 2
	[ "$status" -eq 0 ]
	echo "${output}" | grep "updated test string"
}

@test "Verify diff can automatically discover most recent valid commit" {
	git init

	set_identity "user1"
	echo "test string" > testfile
	git add .
	git commit -m "User 1 Commit 1"

	set_identity "user2"
	git-sig add

	set_identity "user3"
	git-sig add

	set_identity "user1"
	echo "test string 2" > testfile
	git add .
	git commit -m "User 1 Commit 2"

	set_identity "user2"
	git-sig add

	set_identity "user1"
	git checkout -b feature_branch
	echo "updated test string" > somefile1
	git add .
	git commit -m "User 1 Commit 3"

	run git-sig verify --diff --threshold 3
	[ "$status" -eq 0 ]
	echo "${output}" | grep "updated test string"
}
