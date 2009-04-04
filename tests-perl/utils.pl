use Test::More tests => 1;
use Wikiprep::utils qw( encodeXmlChars );

my $t = "Hello & goodbye, world!";
&encodeXmlChars(\$t);
is($t, "Hello &amp; goodbye, world!");
