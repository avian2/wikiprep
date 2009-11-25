use Test::More;
use File::Path qw(rmtree);

my @clean_suffixes = (
	'anchor_text',
	'anchor_text.sorted',
	'external_anchors',
	'cat_hier',
	'hgw.xml',
	'local.xml',
	'log',
	'related_links',
	'stat.categories',
	'stat.inlinks',
	'redir.xml',
	'disambig',
	'min_local_id',
	'version',
	'gum.xml',
	'tmpl.xml',
	'count.db',
	'namespaces.db',
	'templates.db',
	'title2id.db',
	'redir.db',
	'templates',
	'interwiki',
	'interwiki.xml',
	'profile' );

sub run_test {
	my ($test_xml, $clean) = @_;

	my ($volume, $directories, $file) = File::Spec->splitpath($test_xml);
	$options_file = File::Spec->catpath($volume, $directories, "options");

	my $options;
	open(OPTIONS, "<", $options_file);
	while(my $line = <OPTIONS>) {
		$options = $line if $line =~ /$file/;
	}
	close(OPTIONS);

	my @args;
	if($options) {
		chomp $options;
		$options =~ s/^.*://;
		@args = split(/ +/, $options);
	}

	my $test_basename = $test_xml; 
	$test_basename =~ s/\.xml$//;

	# First run Wikiprep
	my $cmd = [ $^X, '-Mblib', 'bin/wikiprep', '-log', 'debug', '-f', $test_xml, @args ];
	my $rv = system(@$cmd) >> 8;
	is($rv, 0, "run $test_xml");

	# Then compare any files that need to be checked
	for my $vetted_result (glob("$test_basename.*.vetted")) {
		my $r = $vetted_result; 
		$r =~ s/\.vetted$//;
		$r =~ s/!/\//g;

		my $cmd = [ 'diff', '-u', $vetted_result, $r ];
		my $rv = system(@$cmd) >> 8;
		SKIP: {
			skip "failed to execute 'diff'", 1 if $? == -1;
			is($rv, 0, "check $r");
		}
	}

	# Then validate any XML files generated
	for my $xml_result (glob("$test_basename.*.xml")) {
		my $cmd = [ 'xmllint', '--noout', $xml_result ];
		my $rv = system(@$cmd) >> 8;

		SKIP: {
			skip "failed to execute 'xmllint'", 1 if $? == -1;
			is($rv, 0, "validate $xml_result");
		}
	}

	# Then clean-up
	if( $clean ) {
		for my $suffix (@clean_suffixes) {
			for my $fn (glob("$test_basename*.$suffix")) {
				rmtree($fn);
			}
		}
	}
}

sub run_all {
	my $composite_num = 0;
	open(OPTIONS, "<", "t/cases/options");
	while(my $line = <OPTIONS>) {
		$composite_num++ if $line =~ /composite/;
	}
	close(OPTIONS);

	my @test_xmls = grep { !/\.(?:hgw|redir|tmpl|gum)\./ } glob("t/cases/*.xml");
	my @vetted_results = glob("t/cases/*.vetted");
	plan(tests => ($#test_xmls + 1) * 3 + $composite_num + ($#vetted_results + 1));
	
	for my $test_xml (@test_xmls) {
		run_test($test_xml, 1);
	}
}

if(@ARGV) {
	plan(tests => 1);
	for my $test_xml (@ARGV) {
		run_test($test_xml, 0);
	}
} else {
	run_all();
}
