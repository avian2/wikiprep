all: test

test:
	make -wC tests test

.PHONY: all test
