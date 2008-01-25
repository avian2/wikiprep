all: test

test:
	make -wC tests-perl test
	make -wC tests test

clean:
	make -wC tests clean

.PHONY: all test clean
