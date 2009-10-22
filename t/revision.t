use Test::Simple tests => 3;
use Wikiprep::revision qw( getDumpDate );

$wikirev = &getDumpDate("/var/wikipedia/enwiki-20080103rev1-pages-articles.xml");
ok($wikirev eq "20080103rev1");

$wikirev = &getDumpDate("/var/wikipedia/enwiki-20080103-pages-articles.xml");
ok($wikirev eq "20080103");

$wikirev = &getDumpDate("bogus");
ok($wikirev eq "unknown");
