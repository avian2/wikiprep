use Test::Simple tests => 1;
use Wikiprep::languages qw( languageName );

my $r;

$r = &languageName("en");

ok($r eq "English");
