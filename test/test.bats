load test_helper

@test "Outputs help if run without arguments" {
	run ./sig
	[ "$status" -eq 0 ]
	echo "${output}" | grep "simple multisig trust toolchain"
}

@test "Outputs help if run with help" {
	run ./sig help
	[ "$status" -eq 0 ]
	echo "${output}" | grep "simple multisig trust toolchain"
}


@test "Outputs version if run with version" {
	run ./sig version
	[ "$status" -eq 0 ]
	echo "${output}" | grep "v0.0.1"
}
