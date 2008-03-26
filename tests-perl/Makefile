TESTS = images.pl \
	nowiki.pl \
	revision.pl \
	languages.pl \
	templates.pl

all: test

test: $(TESTS)
	perl runtests.pl $^

.PHONY: all test
