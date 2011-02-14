use Test::More tests => 14;
use Wikiprep::ParserFunction;

my $pf = $Wikiprep::ParserFunction::parserFunctions{'padleft'};
is($pf->(undef, 0, ""), "");
is($pf->(undef, 0, "xyz"), "xyz");
is($pf->(undef, 0, "xyz", "5"), "00xyz");
is($pf->(undef, 0, "xyz", "5", "_"), "__xyz");
is($pf->(undef, 0, "xyz", "5", "abc"), "abxyz");
is($pf->(undef, 0, "xyz", "2"), "xyz");
is($pf->(undef, 0, "", "1", "xyz"), "x");

$pf = $Wikiprep::ParserFunction::parserFunctions{'padright'};
is($pf->(undef, 0, ""), "");
is($pf->(undef, 0, "xyz"), "xyz");
is($pf->(undef, 0, "xyz", "5"), "xyz00");
is($pf->(undef, 0, "xyz", "5", "_"), "xyz__");
is($pf->(undef, 0, "xyz", "5", "abc"), "xyzab");
is($pf->(undef, 0, "xyz", "2"), "xyz");
is($pf->(undef, 0, "", "1", "xyz"), "x");
