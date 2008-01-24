use Test::Simple tests => 3;
use revision;

$svnrev = revision::getWikiprepRevision();
ok($svnrev =~ /[0-9]+/);

$wikirev = revision::getDumpDate("/var/wikipedia/enwiki-20080103-pages-articles.xml");
ok($wikirev eq "20080103");

$wikirev = revision::getDumpDate("bogus");
ok(not defined($wikirev));
