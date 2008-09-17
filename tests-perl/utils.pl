use Test::More tests => 1;
use Wikiprep::utils qw( trimWhitespaceBothSides );

is(&trimWhitespaceBothSides("  hello  "), "hello");
