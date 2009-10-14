use Test::Simple tests => 4;
use Wikiprep::revision qw( getWikiprepRevision getDumpDate );

$svnrev = &getWikiprepRevision();
ok($svnrev =~ /^\w+$/, "revision '$svnrev'");

$wikirev = &getDumpDate("/var/wikipedia/enwiki-20080103rev1-pages-articles.xml");
ok($wikirev eq "20080103rev1");

$wikirev = &getDumpDate("/var/wikipedia/enwiki-20080103-pages-articles.xml");
ok($wikirev eq "20080103");

$wikirev = &getDumpDate("bogus");
ok($wikirev eq "unknown");
