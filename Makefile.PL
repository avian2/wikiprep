use ExtUtils::MakeMaker;

WriteMakefile(
	NAME		=> "Wikiprep",
	EXE_FILES	=> [ 'bin/wikiprep' ],
	VERSION_FROM	=> "bin/wikiprep",

	PREREQ_PM	=> {
				'Parse::MediaWikiDump'	=> '0.90',
				'Regexp::Common'	=> 0,
				'Inline::C'		=> 0,
				'XML::Writer'		=> 0,           
				'BerkeleyDB'		=> 0,
				'Log::Handler'		=> 0,
			},

	($] >= 5.005 ?
		(ABSTRACT 	=> 'MediaWiki syntax preprocessor and information extractor',
		 AUTHOR		=> 'Tomaz Solc <tomaz.solc@tablix.org') : ()),
);
