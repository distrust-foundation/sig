.PHONY: test
test: test-image
	docker run \
		--rm \
		--interactive \
		--volume $(PWD)/:/home/test/sig \
		local/sig-test \
		bats sig/test/test.bats

.PHONY: lint
lint: test-image
	docker run \
		--rm \
		--interactive \
		--volume $(PWD)/:/home/test/sig \
		local/sig-test \
		shellcheck sig/sig

.PHONY: test-image
test-image:
	docker build \
		--tag local/sig-test \
		--file $(PWD)/test/Dockerfile \
		$(PWD)

.PHONY: test-shell
test-shell: test-image
	docker run \
		--rm \
		--interactive \
		--volume $(PWD)/:/home/test/sig \
		local/sig-test \
		bash
