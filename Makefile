.PHONY: all
all: lint test verify

.PHONY: test
test: test-image
	docker run \
		--rm \
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

.PHONY: verify
verify: test-image
	docker run \
		--rm \
		--interactive \
		--volume $(PWD)/:/home/test/sig \
		local/sig-test /bin/bash -c " \
			cp -R sig /tmp/sig; \
			cd /tmp/sig; \
			./sig fetch \
				--group maintainers \
				6B61ECD76088748C70590D55E90A401336C8AAA9; \
			./sig verify --threshold 1 --method=git --group maintainers; \
			./sig verify --threshold 3 --method=detached --group maintainers; \
		"

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
		--tty \
		--interactive \
		--volume $(PWD)/:/home/test/sig \
		local/sig-test \
		bash
