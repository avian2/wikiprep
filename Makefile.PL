use ExtUtils::MakeMaker;

WriteMakefile(
	NAME		=> "Wikiprep",
	EXE_FILES	=> [ 'bin/wikiprep' ],
	VERSION_FROM	=> "bin/wikiprep"
);

#all: test
#
#test:
#	make -wC tests-perl test
#	make -wC tests test
#
#clean:
#	make -wC tests clean
#
#.PHONY: all test clean
