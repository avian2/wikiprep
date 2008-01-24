# vim:sw=2:tabstop=2:expandtab

use strict;

package revision;

sub getWikiprepRevision() {
  my $svnrev = '$Rev$';

  $svnrev =~ s/.*: ([0-9]+).*/$1/;

  return $svnrev;
}

sub getDumpDate($) {
  my ($dumpFile) = @_;

  if($dumpFile =~ /enwiki-([0-9]+)-pages-articles.xml$/) {
    return $1;
  } else {
    return undef;
  }
}

sub writeVersion($$) {
  my ($versionFile, $dumpFile) = @_;

  open(VERSIONF, "> $versionFile") or die "Cannot open $versionFile: $!";

  my $dumpDate = &getDumpDate($dumpFile);
  my $svnrev = &getWikiprepRevision();

  print(VERSIONF "mediawiki-dump-date: $dumpDate\n");
  print(VERSIONF "wikiprep-revision: $svnrev\n");

  close(VERSIONF);
}

1
