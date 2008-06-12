TESTS = utils.pl \
	images.pl \
	nowiki.pl \
	revision.pl \
	languages.pl \
	templates.pl \
	css.pl

all: test

test: $(TESTS)
	perl runtests.pl $^

.PHONY: all test
