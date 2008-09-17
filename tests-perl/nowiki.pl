use Test::Simple tests => 3;
use Wikiprep::nowiki qw( randomString extractTags replaceTags );

my ($t, $r);
my %tok;

my $regex = qr/(<nowiki>.*?<\/nowiki>)/;

print "Generated unique strings:\n";
print "  ", &randomString(), "\n";
print "  ", &randomString(), "\n";
print "  ", &randomString(), "\n";
print "  ", &randomString(), "\n";

$t = <<END
hello<nowiki>, world!</nowiki>
END
;
$r = $t;

&extractTags(\$regex, \$t, \%tok);
&replaceTags(\$t, \%tok);

ok($r eq $t);

$t = <<END
hello<nowiki>, 
world!</nowiki> nice day
<nowiki>[[not a link]]</nowiki>
\x7fUNIQ1234567812345678
END
;
$r = $t;

%tok = ();

&extractTags(\$regex, \$t, \%tok);

ok($t =~ /nice day/);

&replaceTags(\$t, \%tok);

ok($t eq $r);
