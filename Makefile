all: test

test:
	make -wC tests-perl test
	make -wC tests test

.PHONY: all test
