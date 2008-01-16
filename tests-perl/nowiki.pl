use Test::Simple tests => 3;
use nowiki;

my ($t, $r);
my %tok;

print "Generated unique strings:\n";
print "  ", &nowiki::randomString(), "\n";
print "  ", &nowiki::randomString(), "\n";
print "  ", &nowiki::randomString(), "\n";
print "  ", &nowiki::randomString(), "\n";

$t = <<END
hello<nowiki>, world!</nowiki>
END
;
$r = $t;

&nowiki::extractTags("(<nowiki>.*?</nowiki>)", \$t, \%tok);
&nowiki::replaceTags(\$t, \%tok);

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

&nowiki::extractTags("(<nowiki>.*?</nowiki>)", \$t, \%tok);

ok($t =~ /nice day/);

&nowiki::replaceTags(\$t, \%tok);

ok($t eq $r);
