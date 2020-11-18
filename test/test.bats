load test_helper

@test "Outputs help if run without arguments" {
	run ./sig
	[ "$status" -eq 0 ]
}
