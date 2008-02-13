TESTS = images.pl \
	nowiki.pl \
	revision.pl \
	languages.pl

all: test

test: $(TESTS)
	perl runtests.pl $^

.PHONY: all test
