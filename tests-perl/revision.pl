use Test::Simple tests => 4;
use revision;

$svnrev = revision::getWikiprepRevision();
ok($svnrev =~ /^\w+$/, "revision '$svnrev'");

$wikirev = revision::getDumpDate("/var/wikipedia/enwiki-20080103rev1-pages-articles.xml");
ok($wikirev eq "20080103rev1");

$wikirev = revision::getDumpDate("/var/wikipedia/enwiki-20080103-pages-articles.xml");
ok($wikirev eq "20080103");

$wikirev = revision::getDumpDate("bogus");
ok($wikirev eq "unknown");
