use Test::Simple tests => 1;
use languages;

my $r;

$r = &languages::languageName("en");

ok($r eq "English");
