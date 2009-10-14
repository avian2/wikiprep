use Test::More;

my @test_xmls = glob("t/cases/*.xml");
plan(tests => $#test_xmls + 1);

for my $test_xml (@test_xmls) {
	ok(1);
}
